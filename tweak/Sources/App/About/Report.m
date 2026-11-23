// Mod > Report a problem: what went wrong, a screen recording of it happening and the diagnostics, kept
// in one folder on this phone — Application Support/Retrine/Reports/<uuid>/ with report.json,
// diagnostics.txt and its .mov recordings — since the mod has no server; Send hands them to the share
// sheet. The list of the reports kept so far opens each one to add more, refresh the diagnostics, send
// it again or delete it.
//
// The recording is ReplayKit's in-app recorder, microphone off, and its Stop button is a small window
// of the mod's at UIWindowLevelAlert + 1, so it floats over Spotify's player and everything else the
// user reaches while the problem is recorded.
#import <ReplayKit/ReplayKit.h>
#import "Core/SGCore.h"
#import "Core/SGDataRoot.h"
#import "Settings/SGPageStyle.h"
#import "Settings/SGModPage.h"
#import "About.h"
#import "ReportFolder.h"

static NSString *const kReportFile = @"report.json";
static NSString *const kDiagnosticsFile = @"diagnostics.txt";

// ---- storage -------------------------------------------------------------------------------------------

static NSURL *reportRoot(void) {
    return [SGDataRoot(NSApplicationSupportDirectory) URLByAppendingPathComponent:@"Reports" isDirectory:YES];
}

static NSURL *reportFolder(NSString *identifier) {
    return [reportRoot() URLByAppendingPathComponent:identifier isDirectory:YES];
}

static NSString *isoNow(void) {
    static NSISO8601DateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ formatter = [NSISO8601DateFormatter new]; });
    return [formatter stringFromDate:NSDate.date];
}

static NSDate *dateFromISO(id value) {
    if (![value isKindOfClass:NSString.class]) return nil;
    static NSISO8601DateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ formatter = [NSISO8601DateFormatter new]; });
    return [formatter dateFromString:value];
}

static NSString *dateText(id iso) {
    NSDate *date = dateFromISO(iso);
    if (!date) return @"";
    static NSDateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [NSDateFormatter new];
        formatter.dateStyle = NSDateFormatterMediumStyle;
        formatter.timeStyle = NSDateFormatterShortStyle;
    });
    return [formatter stringFromDate:date];
}

static NSDictionary *readMeta(NSURL *folder) {
    NSData *data = [NSData dataWithContentsOfURL:[folder URLByAppendingPathComponent:kReportFile]];
    id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    return [json isKindOfClass:NSDictionary.class] ? json : nil;
}

static void writeMeta(NSURL *folder, NSDictionary *meta) {
    // Updates never recreate a deleted report; only ensureReport creates a new folder.
    NSData *data = [NSJSONSerialization dataWithJSONObject:meta options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
    [data writeToURL:[folder URLByAppendingPathComponent:kReportFile] atomically:YES];
}

static NSArray<NSString *> *recordingsIn(NSDictionary *meta) {
    NSArray *names = meta[@"recordings"];
    return [names isKindOfClass:NSArray.class] ? names : @[];
}

static void appendRecording(NSString *identifier, NSString *name) {
    NSURL *folder = reportFolder(identifier);
    NSMutableDictionary *meta = [readMeta(folder) mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *recordings = [recordingsIn(meta) mutableCopy];
    if (![recordings containsObject:name]) [recordings addObject:name];
    meta[@"recordings"] = recordings;
    writeMeta(folder, meta);
}

// Every report on the phone, newest first: report.json's created date is ISO 8601 in UTC, so the
// strings sort as the times do. A folder without a report.json is a recording that never finished.
static NSArray<NSDictionary *> *allReports(void) {
    NSArray<NSURL *> *folders = [NSFileManager.defaultManager contentsOfDirectoryAtURL:reportRoot()
                                                          includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                                                                             options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                               error:nil];
    NSMutableArray<NSDictionary *> *reports = [NSMutableArray array];
    for (NSURL *folder in folders) {
        id directory = nil;
        [folder getResourceValue:&directory forKey:NSURLIsDirectoryKey error:nil];
        if (![directory boolValue]) continue;
        NSDictionary *meta = readMeta(folder);
        if (!meta) continue;
        [reports addObject:@{@"id": folder.lastPathComponent, @"meta": meta}];
    }
    [reports sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"meta"][@"created"] ?: @"" compare:a[@"meta"][@"created"] ?: @""];
    }];
    return reports;
}

static NSString *firstLine(NSString *text) {
    for (NSString *line in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (trimmed.length) return trimmed;
    }
    return nil;
}

static void reportAlert(NSString *title, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"settings.report.action.ok", @"OK") style:UIAlertActionStyleCancel handler:nil]];
    SGPresentDark(alert);
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

// ---- the page ------------------------------------------------------------------------------------------

@class SGReportPage;

// The recording session is the file's to know, not the capsule window's: the window can be missing
// (Start succeeded with no foreground scene) while the recorder runs, and Stop must still own the file.
typedef NS_ENUM(NSInteger, SGReportRecordingState) {
    SGReportRecordingIdle,
    SGReportRecordingStarting,    // startRecordingWithHandler was asked; the recorder has not answered
    SGReportRecordingRecording,
    SGReportRecordingStopping,    // Stop asked for the file; the completion handler keeps it
};
static SGReportRecordingState sg_recordingState = SGReportRecordingIdle;
static UIWindow *sg_capsuleWindow;
static UIButton *sg_capsuleStop;
static SGReportPage *sg_recordingPage;   // kept while a recording runs, so Stop can go back to it
static NSString *sg_recordingReport;
static NSString *sg_recordingName;

@interface SGReportPage : SGPage <UITextViewDelegate>
// nil opens a new report; an identifier opens one kept before, to add to it or send it again.
- (instancetype)initWithReport:(NSString *)identifier;
- (void)recordingSaved:(NSString *)name;
- (void)recordingFailed:(NSString *)message;
@end

// A window this level covers Spotify's, so only the capsule under the finger takes the touch and
// everything else reaches the app as if the window were not there.
@interface SGReportCapsuleWindow : UIWindow
@end

@implementation SGReportCapsuleWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self.rootViewController.view ? nil : hit;
}

@end

static CAShapeLayer *reportRedSquare(UIButton *button) {
    CAShapeLayer *square = [CAShapeLayer layer];
    square.path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 10, 10) cornerRadius:2.5].CGPath;
    square.fillColor = UIColor.whiteColor.CGColor;
    square.frame = CGRectMake(0, 0, 10, 10);
    [button.layer addSublayer:square];
    return square;
}

static void stopReportRecording(void);
static void returnToReportPage(void);
static void showCapsule(void);

static void hideCapsule(void) {
    UIWindow *window = sg_capsuleWindow;
    sg_capsuleWindow = nil;
    sg_capsuleStop = nil;
    window.hidden = YES;
    window.rootViewController = nil;
    // The key window is Spotify's again, or the keyboard and the text field stay without one.
    for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *other in scene.windows) {
            if (other == window || other.hidden || other.windowLevel != UIWindowLevelNormal) continue;
            [other makeKeyWindow];
            break;
        }
    }
}

// The floating red Stop: small, above Spotify's chrome, read out as the one control that ends the
// recording. The square is drawn by hand so the label sits beside a mark, not a glyph.
// Start can succeed with no scene foreground-active (Spotify in the background at the wrong moment):
// the window cannot be made then, so it is made the moment a scene activates.
static void watchSceneActivation(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [NSNotificationCenter.defaultCenter addObserverForName:UISceneDidActivateNotification object:nil queue:nil
                                                    usingBlock:^(NSNotification *note) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (sg_recordingState == SGReportRecordingStarting || sg_recordingState == SGReportRecordingRecording) showCapsule();
            });
        }];
    });
}

static void showCapsule(void) {
    if (sg_capsuleWindow) return;
    if (sg_recordingState != SGReportRecordingStarting && sg_recordingState != SGReportRecordingRecording) return;
    UIWindowScene *scene = nil;
    for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
        if (![candidate isKindOfClass:UIWindowScene.class] || candidate.activationState != UISceneActivationStateForegroundActive) continue;
        scene = (UIWindowScene *)candidate;
        break;
    }
    if (!scene) return;
    SGReportCapsuleWindow *window = [[SGReportCapsuleWindow alloc] initWithWindowScene:scene];
    window.windowLevel = UIWindowLevelAlert + 1;
    window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    window.backgroundColor = UIColor.clearColor;
    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = UIColor.clearColor;
    UIButton *stop = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *look = [UIButtonConfiguration filledButtonConfiguration];
    look.title = SGL(@"settings.report.recording.stop", @"Stop");
    look.baseBackgroundColor = SGRed();
    look.baseForegroundColor = UIColor.whiteColor;
    look.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    look.contentInsets = NSDirectionalEdgeInsetsMake(0, 30, 0, 16);
    look.attributedTitle = [[NSAttributedString alloc] initWithString:look.title attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold],
        NSForegroundColorAttributeName: UIColor.whiteColor,
    }];
    stop.configuration = look;
    stop.accessibilityLabel = SGL(@"settings.report.recording.stop.label", @"Stop recording");
    stop.accessibilityHint = SGL(@"settings.report.recording.stop.hint", @"Ends the recording and goes back to the report.");
    [stop addAction:[UIAction actionWithTitle:SGL(@"settings.report.recording.stop", @"Stop") image:nil identifier:nil
                                       handler:^(UIAction *action) { stopReportRecording(); }]
      forControlEvents:UIControlEventTouchUpInside];
    // The square sits in the leading padding, so the title clears it.
    [root.view addSubview:stop];
    stop.translatesAutoresizingMaskIntoConstraints = NO;
    UILayoutGuide *safe = root.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stop.centerXAnchor constraintEqualToAnchor:root.view.centerXAnchor],
        [stop.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [stop.heightAnchor constraintEqualToConstant:36],
    ]];
    CAShapeLayer *square = reportRedSquare(stop);
    square.position = CGPointMake(18, 18);
    window.rootViewController = root;
    window.hidden = NO;
    sg_capsuleWindow = window;
    sg_capsuleStop = stop;
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, stop);
}

// ---- ReplayKit -----------------------------------------------------------------------------------------

@interface SGReportRecorder : NSObject <RPScreenRecorderDelegate>
+ (instancetype)shared;
@end

@implementation SGReportRecorder

+ (instancetype)shared {
    static SGReportRecorder *recorder;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ recorder = [SGReportRecorder new]; });
    return recorder;
}

// The recorder ended on its own (an interruption, the screen locking): the file is not there to keep,
// and the capsule must not stay over Spotify for it.
- (void)screenRecorder:(RPScreenRecorder *)recorder didStopRecordingWithPreviewViewController:(RPPreviewViewController *)preview error:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        // Our own Stop asked for the file: the completion handler below is the one that keeps it.
        if (sg_recordingState == SGReportRecordingStopping) return;
        if (sg_recordingState == SGReportRecordingIdle) return;
        NSString *identifier = sg_recordingReport;
        NSString *name = sg_recordingName;
        sg_recordingState = SGReportRecordingIdle;
        hideCapsule();
        sg_recordingReport = nil;
        sg_recordingName = nil;
        if (identifier && name) {
            NSURL *url = [reportFolder(identifier) URLByAppendingPathComponent:name];
            [NSFileManager.defaultManager removeItemAtURL:url error:nil];
        }
        [sg_recordingPage recordingFailed:error.localizedDescription];
        sg_recordingPage = nil;
    });
}

@end

static void returnToReportPage(void) {
    SGReportPage *page = sg_recordingPage;
    if (!page) return;
    UINavigationController *nav = page.navigationController;
    if (nav && nav.viewControllers.count > 1 && nav.topViewController != page) {
        [nav popToViewController:page animated:YES];
        return;
    }
    // The page left the stack while the screen recorded (the tab bar was tapped away from its stack):
    // it comes back over whatever is on screen, rather than leaving the recording with nowhere to go.
    if (page.presentingViewController || page.view.window) return;
    UINavigationController *shown = [[UINavigationController alloc] initWithRootViewController:page];
    SGPresentDark(shown);
    [SGTopController() presentViewController:shown animated:YES completion:nil];
}

static void finishRecording(NSString *identifier, NSString *name, NSURL *url, NSError *error) {
    sg_recordingState = SGReportRecordingIdle;
    hideCapsule();
    SGReportPage *page = sg_recordingPage;
    sg_recordingReport = nil;
    sg_recordingName = nil;
    if (!identifier || !name) {
        sg_recordingPage = nil;
        returnToReportPage();
        return;
    }
    if (error) {
        [NSFileManager.defaultManager removeItemAtURL:url error:nil];
        [page recordingFailed:error.localizedDescription];
    } else {
        appendRecording(identifier, name);
        [page recordingSaved:name];
    }
    returnToReportPage();
    sg_recordingPage = nil;
}

static void stopReportRecording(void) {
    // Stop can be pressed twice (a double tap, or the capsule and its button): the file is asked for once.
    if (sg_recordingState == SGReportRecordingStopping) return;
    RPScreenRecorder *recorder = RPScreenRecorder.sharedRecorder;
    NSString *identifier = sg_recordingReport;
    NSString *name = sg_recordingName;
    if (!recorder.isRecording || !identifier || !name) {
        sg_recordingState = SGReportRecordingIdle;
        hideCapsule();
        returnToReportPage();
        sg_recordingReport = nil;
        sg_recordingName = nil;
        sg_recordingPage = nil;
        return;
    }
    NSURL *url = [reportFolder(identifier) URLByAppendingPathComponent:name];
    // ReplayKit writes a new file there, so nothing may hold the name already.
    [NSFileManager.defaultManager removeItemAtURL:url error:nil];
    sg_recordingState = SGReportRecordingStopping;
    sg_capsuleStop.enabled = NO;
    [recorder stopRecordingWithOutputURL:url completionHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ finishRecording(identifier, name, url, error); });
    }];
}

static void startReportRecording(NSString *identifier, SGReportPage *page) {
    RPScreenRecorder *recorder = RPScreenRecorder.sharedRecorder;
    if (sg_recordingState != SGReportRecordingIdle) {
        [page recordingFailed:SGL(@"settings.report.recording.busy.message", @"A recording is already running.")];
        return;
    }
    if (!recorder.isAvailable) {
        [page recordingFailed:SGL(@"settings.report.recording.unavailable.message",
                                  @"This iPhone does not offer ReplayKit's recording, or screen recording is turned off in Settings.")];
        return;
    }
    if (recorder.isRecording) {
        [page recordingFailed:SGL(@"settings.report.recording.busy.message", @"A recording is already running.")];
        return;
    }
    recorder.microphoneEnabled = NO;
    recorder.delegate = SGReportRecorder.shared;
    sg_recordingState = SGReportRecordingStarting;
    sg_recordingReport = identifier;
    sg_recordingName = [NSString stringWithFormat:@"recording-%lu.mov", (unsigned long)NSDate.date.timeIntervalSince1970];
    sg_recordingPage = page;
    watchSceneActivation();
    [recorder startRecordingWithHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                sg_recordingState = SGReportRecordingIdle;
                hideCapsule();
                sg_recordingReport = nil;
                sg_recordingName = nil;
                sg_recordingPage = nil;
                [page recordingFailed:error.localizedDescription
                                 ?: SGL(@"settings.report.recording.unavailable.message",
                                        @"This iPhone does not offer ReplayKit's recording, or screen recording is turned off in Settings.")];
                return;
            }
            // A Stop asked for while starting owns the session now; its handler ends it.
            if (sg_recordingState == SGReportRecordingStopping) return;
            sg_recordingState = SGReportRecordingRecording;
            showCapsule();
        });
    }];
}

// ---- the report page -----------------------------------------------------------------------------------

enum { SGReportSectionText, SGReportSectionActions, SGReportSectionList, SGReportSectionDelete };

@implementation SGReportPage {
    NSString *_identifier;                 // nil until this report is first written to disk
    NSMutableDictionary *_meta;
    UITextView *_text;
    UILabel *_hint;
    NSString *_recordingStatus;            // the sentence under Record, until the page is left
    UIView *_shareFrom;                    // the cell the share sheet points its popover at
    BOOL _deleted;                         // the folder is gone; nothing may write it back
    NSArray<NSDictionary *> *_reports;     // the snapshot represented by the table's row indices
    BOOL _sending;
}

- (instancetype)initWithReport:(NSString *)identifier {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    _identifier = [identifier copy];
    if (identifier) _meta = [readMeta(reportFolder(identifier)) mutableCopy];
    if (!_meta) _meta = [NSMutableDictionary dictionary];
    _reports = allReports();
    self.title = SGL(@"settings.report.title", @"Report a problem");
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self reloadList];
    // An older report's diagnostics are brought up to this build whenever it is opened, so what Send
    // hands over never describes the build before.
    if (_identifier && !_deleted)
        SGExportDiagnosticsToURL([reportFolder(_identifier) URLByAppendingPathComponent:kDiagnosticsFile], nil);
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (!self.isMovingFromParentViewController && !self.isBeingDismissed) return;
    [self saveText];
}

// The report is made on disk the first time it has something to keep: its own text, a recording, or
// a send. Its identifier is a uuid, its created date the moment it was.
- (NSString *)ensureReport {
    if (_deleted) return nil;
    if (_identifier) return _identifier;
    NSURL *folder = SGCreateReportFolder(reportRoot());
    if (!folder) return nil;
    _identifier = folder.lastPathComponent;
    _meta[@"created"] = isoNow();
    _meta[@"mod"] = @(SG_VERSION);
    _meta[@"spotify"] = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown";
    _meta[@"ios"] = UIDevice.currentDevice.systemVersion;
    _meta[@"text"] = @"";
    _meta[@"recordings"] = @[];
    writeMeta(folder, _meta);
    return _identifier;
}

- (void)saveText {
    if (_deleted) return;
    // A page whose text card was never drawn has nothing to write over what the file holds.
    if (!_text) return;
    NSString *trimmed = [_text.text ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    // Empty text on a report with nothing on disk makes no report: Back from a blank page leaves no folder.
    if (!_identifier && !trimmed.length) return;
    NSString *identifier = [self ensureReport];
    if (!identifier) return;
    _meta[@"text"] = _text.text ?: @"";
    writeMeta(reportFolder(identifier), _meta);
}

- (void)recordingSaved:(NSString *)name {
    if (_deleted) return;
    _recordingStatus = SGL(@"settings.report.recording.saved", @"Recording saved to this report.");
    // The recorder wrote the name into the folder's report.json itself; Send reads this copy of it.
    if (_identifier) {
        NSDictionary *meta = readMeta(reportFolder(_identifier));
        if (meta) _meta = [meta mutableCopy];
    }
    [self reloadList];
}

- (void)recordingFailed:(NSString *)message {
    if (_deleted) return;
    if (message.length) reportAlert(SGL(@"settings.report.recording.failed.title", @"Could not record the screen"), message);
    [self reloadList];
}

- (void)reloadList {
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_reports = allReports();
        [self.tableView reloadData];
        UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, nil);
    });
}

// ---- actions ----

- (void)record {
    if (_deleted) return;
    [self saveText];
    [self reloadList];
    NSString *identifier = [self ensureReport];
    if (identifier) startReportRecording(identifier, self);
}

- (void)send {
    if (_deleted || _sending || !SGDiagnosticsCanPresentFrom(self)) return;
    [self saveText];
    [self reloadList];
    NSString *text = _text ? _text.text : (_meta[@"text"] ?: @"");
    BOOL hasText = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length > 0;
    // Nothing written and nothing recorded: there is no report to make on disk just to say so.
    if (!_identifier && !hasText) {
        reportAlert(SGL(@"settings.report.share.empty.title", @"Nothing to send yet"),
                    SGL(@"settings.report.share.empty.message", @"Write what went wrong, record the screen, or both."));
        return;
    }
    NSString *identifier = [self ensureReport];
    if (!identifier) return;
    NSURL *folder = reportFolder(identifier);
    _sending = YES;
    SGExportDiagnosticsToURL([folder URLByAppendingPathComponent:kDiagnosticsFile], ^(NSError *error) {
        // The flag owns the export only. A skipped or refused presentation must never latch Send.
        self->_sending = NO;
        if (self->_deleted || !SGDiagnosticsCanPresentFrom(self)) return;
        if (error) {
            reportAlert(SGL(@"settings.mod.share_diagnostics.title", @"Share diagnostics"), error.localizedDescription);
            return;
        }
        [self shareText:text folder:folder];
    });
}

- (void)shareText:(NSString *)text folder:(NSURL *)folder {
    BOOL hasText = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length > 0;
    NSMutableArray *items = [NSMutableArray array];
    if (hasText) [items addObject:text];
    NSURL *diagnostics = [folder URLByAppendingPathComponent:kDiagnosticsFile];
    if ([NSFileManager.defaultManager fileExistsAtPath:diagnostics.path]) [items addObject:diagnostics];
    for (NSString *name in recordingsIn(_meta)) {
        NSURL *url = [folder URLByAppendingPathComponent:name];
        if ([NSFileManager.defaultManager fileExistsAtPath:url.path]) [items addObject:url];
    }
    if (!items.count) {
        reportAlert(SGL(@"settings.report.share.empty.title", @"Nothing to send yet"),
                    SGL(@"settings.report.share.empty.message", @"Write what went wrong, record the screen, or both."));
        return;
    }
    UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil];
    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    if (popover) {
        // iPad needs a source; the row that was tapped, else the page's own view.
        popover.sourceView = _shareFrom ?: self.view;
        popover.sourceRect = _shareFrom ? _shareFrom.bounds : CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    }
    __weak SGReportPage *weakSelf = self;
    sheet.completionWithItemsHandler = ^(UIActivityType type, BOOL completed, NSArray *returned, NSError *error) {
        SGReportPage *page = weakSelf;
        if (!page) return;
        if (!completed || page->_deleted || !page->_identifier) return;
        page->_meta[@"shared"] = isoNow();
        writeMeta(reportFolder(page->_identifier), page->_meta);
        [page reloadList];
    };
    SGPresentDark(sheet);
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)deleteReport {
    // A report not yet on disk has no folder of its own: reportFolder(nil) would name every report's.
    if (!_identifier.length) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    // The recorder writes into this report's folder when it stops: deleting it now would leave it writing
    // into a folder that is gone, or the folder coming back with only a recording in it.
    NSString *recordingReport = sg_recordingReport;
    if (sg_recordingState != SGReportRecordingIdle && [recordingReport isEqualToString:_identifier]) {
        reportAlert(SGL(@"settings.report.delete.recording.title", @"Recording in progress"),
                    SGL(@"settings.report.delete.recording.message", @"Stop the recording, then delete the report."));
        return;
    }
    NSUInteger recordings = recordingsIn(_meta).count;
    NSString *message = recordings
        ? [NSString stringWithFormat:SGL(@"settings.report.delete.alert.message_recordings", @"Its text, diagnostics and %lu recording(s) are removed from this phone. This cannot be undone."), (unsigned long)recordings]
        : SGL(@"settings.report.delete.alert.message", @"Its text and diagnostics are removed from this phone. This cannot be undone.");
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGL(@"settings.report.delete.alert.title", @"Delete this report?")
                                                                  message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"settings.report.delete.alert.action", @"Delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        // Set before the folder goes: viewWillDisappear: saves the text, and that save would make it again.
        self->_deleted = YES;
        [NSFileManager.defaultManager removeItemAtURL:reportFolder(self->_identifier) error:nil];
        [self.navigationController popViewControllerAnimated:YES];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    SGPresentDark(alert);
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)openReport:(NSString *)identifier {
    if ([identifier isEqualToString:_identifier]) return;
    [self saveText];
    for (UIViewController *controller in self.navigationController.viewControllers) {
        if (![controller isKindOfClass:SGReportPage.class]) continue;
        SGReportPage *page = (SGReportPage *)controller;
        if (![page->_identifier isEqualToString:identifier]) continue;
        if (!page->_deleted) [self.navigationController popToViewController:page animated:YES];
        return;
    }
    [self.navigationController pushViewController:[[SGReportPage alloc] initWithReport:identifier] animated:YES];
}

// ---- the table ----

- (NSDictionary *)metaForRow:(NSInteger)row {
    return row >= 0 && row < (NSInteger)_reports.count ? _reports[(NSUInteger)row] : nil;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    return 4;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case SGReportSectionText: return 1;
        case SGReportSectionActions: return 2;
        case SGReportSectionList: return (NSInteger)_reports.count;
        default: return _identifier ? 1 : 0;   // a report with nothing on disk yet cannot be deleted
    }
}

- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case SGReportSectionText: return SGL(@"settings.report.what.title", @"What went wrong");
        case SGReportSectionList: return SGL(@"settings.report.list.title", @"Your reports");
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case SGReportSectionText: return SGL(@"settings.report.what.note", @"What you were doing, which song, and what the screen did. It stays on this phone until you send it.");
        case SGReportSectionList:
            return _reports.count ? nil : SGL(@"settings.report.list.empty", @"No reports on this phone yet.");
        default: return nil;
    }
}

- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path {
    // The text view fills a card of its own; five lines is enough to read what was written and scrolls past.
    return path.section == SGReportSectionText ? 160 : UITableViewAutomaticDimension;
}

- (UITableViewCell *)textCell {
    static NSString *const identifier = @"report-text";
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:identifier];
    if (cell) return cell;
    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.backgroundColor = SGCardBackground();
    _text = [UITextView new];
    _text.translatesAutoresizingMaskIntoConstraints = NO;
    _text.backgroundColor = UIColor.clearColor;
    _text.textColor = UIColor.whiteColor;
    _text.tintColor = SGGreen();
    _text.font = SGTitleFont();
    _text.keyboardAppearance = UIKeyboardAppearanceDark;
    _text.textContainerInset = UIEdgeInsetsMake(8, 6, 8, 6);
    _text.text = _meta[@"text"] ?: @"";
    _text.delegate = self;
    _text.accessibilityLabel = SGL(@"settings.report.what.title", @"What went wrong");
    [cell.contentView addSubview:_text];
    [NSLayoutConstraint activateConstraints:@[
        [_text.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:10],
        [_text.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-10],
        [_text.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:4],
        [_text.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-4],
    ]];
    _hint = [UILabel new];
    _hint.translatesAutoresizingMaskIntoConstraints = NO;
    _hint.text = SGL(@"settings.report.what.placeholder", @"What went wrong?");
    _hint.font = SGTitleFont();
    _hint.textColor = SGGrey();
    _hint.userInteractionEnabled = NO;
    _hint.hidden = _text.text.length > 0;
    [cell.contentView addSubview:_hint];
    [NSLayoutConstraint activateConstraints:@[
        [_hint.leadingAnchor constraintEqualToAnchor:_text.leadingAnchor constant:11],
        [_hint.topAnchor constraintEqualToAnchor:_text.topAnchor constant:8],
        [_hint.trailingAnchor constraintLessThanOrEqualToAnchor:_text.trailingAnchor],
    ]];
    return cell;
}

- (UITableViewCell *)actionCellFor:(UITableView *)table at:(NSIndexPath *)path {
    UITableViewCell *cell = SGDequeueCell(table, @"report-action");
    BOOL record = path.row == 0;
    NSString *title = record ? SGL(@"settings.report.action.record.title", @"Record the screen")
                             : SGL(@"settings.report.action.send.title", @"Send");
    NSString *subtitle;
    if (record) subtitle = _recordingStatus ?: SGL(@"settings.report.action.record.subtitle",
                                                     @"A red Stop floats over Spotify while it records. The recording is saved into this report.");
    else subtitle = SGL(@"settings.report.action.send.subtitle", @"Share the text, the diagnostics and the recordings.");
    SGFillCell(cell, title, subtitle, nil, nil);
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.accessoryView = nil;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section == SGReportSectionText) return [self textCell];
    if (path.section == SGReportSectionActions) return [self actionCellFor:table at:path];
    if (path.section == SGReportSectionDelete) {
        UITableViewCell *cell = SGDequeueCell(table, @"report-delete");
        SGFillCell(cell, SGL(@"settings.report.delete.title", @"Delete report"), nil, SGRed(), nil);
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        return cell;
    }
    NSDictionary *entry = [self metaForRow:path.row];
    if (!entry) return SGDequeueCell(table, @"report-row");
    NSDictionary *meta = entry[@"meta"];
    UITableViewCell *cell = SGDequeueCell(table, @"report-row");
    NSString *line = firstLine(meta[@"text"] ?: @"") ?: SGL(@"settings.report.list.none_title", @"(no text)");
    NSString *status = meta[@"shared"]
        ? [NSString stringWithFormat:SGL(@"settings.report.status.shared_format", @"Shared on %@"), dateText(meta[@"shared"])]
        : SGL(@"settings.report.status.saved", @"Saved on this phone");
    NSArray<NSString *> *recordings = recordingsIn(meta);
    NSString *detail = recordings.count
        ? [NSString stringWithFormat:SGL(@"settings.report.list.recordings_format", @"%@ · %lu recording(s)"), status, (unsigned long)recordings.count]
        : status;
    SGFillCell(cell, dateText(meta[@"created"]), [NSString stringWithFormat:@"%@\n%@", line, detail], nil, nil);
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.accessoryView = SGChevronView();
    return cell;
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    [self.view endEditing:YES];
    switch (path.section) {
        case SGReportSectionActions:
            _shareFrom = [table cellForRowAtIndexPath:path];
            if (path.row == 0) [self record]; else [self send];
            break;
        case SGReportSectionList: {
            NSString *identifier = [self metaForRow:path.row][@"id"];
            if (identifier) [self openReport:identifier];
            break;
        }
        case SGReportSectionDelete:
            [self deleteReport];
            break;
        default:
            break;
    }
}

- (void)textViewDidChange:(UITextView *)textView {
    _hint.hidden = textView.text.length > 0;
}

- (void)textViewDidEndEditing:(UITextView *)textView {
    [self saveText];
    [self reloadList];
}

@end

UIViewController *SGReportListPage(void) {
    return [[SGReportPage alloc] initWithReport:nil];
}

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <OSLog/OSLog.h>
#import <sys/utsname.h>
#import "Core/SGCore.h"
#import "Core/SGDataRoot.h"
#import "Shared/AdBlock/AdBlock.h"
#import "Shared/SponsorBlock/SponsorBlock.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Settings/SGPageStyle.h"
#import "About.h"
#import "SGDiagnosticRedaction.h"
#import "Redesigned/Player/Player.h"

// Every key under the prefix travels, the way the reset sweeps them, so a new switch needs nothing
// here. What is left out belongs to this install rather than to its user's choices.
static BOOL isSetting(NSString *key) {
    if (![key hasPrefix:@"spotifyglass."]) return NO;
    if (SGPrivatePreferenceKey(key) || [key isEqual:SGKeySponsorBlockServer] || [key isEqual:@"spotifyglass.wireguard"]) return NO;
    for (NSString *local in @[@"spotifyglass.adblock.counts", @"spotifyglass.privacy.counts", @"spotifyglass.update.",
                              @"spotifyglass.signing.", @"spotifyglass.onboarding.", @"spotifyglass.navbar.stock",
                              @"spotifyglass.redesign.navbar.stock", @"spotifyglass.automix.saved",
                              @"spotifyglass.lossless.savedQuality", @"spotifyglass.liveActivity.startedAt"]) {
        if ([key hasPrefix:local]) return NO;
    }
    return YES;
}

static NSDictionary *storedDefaults(void) {
    return [NSUserDefaults.standardUserDefaults persistentDomainForName:NSBundle.mainBundle.bundleIdentifier] ?: @{};
}

static UIAlertController *showAlert(UIViewController *presenter, NSString *title, NSString *message, UIAlertAction *confirm, void (^cancelled)(void)) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    if (confirm) [alert addAction:confirm];
    [alert addAction:[UIAlertAction actionWithTitle:confirm ? SGL(@"common.cancel", @"Cancel") : SGL(@"common.ok", @"OK") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        if (cancelled) cancelled();
    }]];
    [presenter presentViewController:alert animated:YES completion:nil];
    return alert;
}

static NSDictionary *exportSettings(NSDictionary *stored) {
    NSMutableDictionary *settings = [NSMutableDictionary dictionary];
    [stored enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        if (isSetting(key) && [NSJSONSerialization isValidJSONObject:@[value]]) settings[key] = value;
    }];
    return settings;
}

void SGExportSettings(void) {
    NSDictionary *file = @{
        @"mod": @(SG_VERSION),
        @"spotify": [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown",
        @"settings": exportSettings(storedDefaults()),
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:file options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"spotifyglass-settings.json"]];
    [data writeToURL:url atomically:YES];

    UIViewController *top = SGTopController();
    UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    sheet.popoverPresentationController.sourceView = top.view;
    [top presentViewController:sheet animated:YES completion:nil];
}

static NSMutableString *diagnosticMetadata(void) {
    NSMutableString *text = [NSMutableString string];
    struct utsname machine;
    uname(&machine);
    [text appendFormat:@"Retrine %s, Spotify %@, iOS %@, %s\n", SG_VERSION,
        [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown",
        UIDevice.currentDevice.systemVersion, machine.machine];
    [text appendFormat:@"look %@, hide ads %d, hide upsells %d, spoof premium %d, EeveeSpotify %d\n\n",
        SGRedesignedUIStored() ? @"redesign" : @"native", SGHidden(SGKeyHideAds), SGHidden(SGKeyHideUpsells),
        SGHidden(SGKeyFakePremium), SGEeveeSpotifyInjected()];
    [text appendString:@"== ads blocked (stopped of checked)\n"];
    for (NSString *label in SGAdBlockLabels()) {
        NSUInteger checked = SGAdBlockChecked(label);
        [text appendFormat:@"%@: %lu%@\n", label, (unsigned long)SGAdBlockCount(label),
            checked == NSNotFound ? @"" : [NSString stringWithFormat:@" of %lu", (unsigned long)checked]];
    }
    return text;
}

static dispatch_queue_t diagnosticWriter(void) {
    static dispatch_queue_t writer;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ writer = dispatch_queue_create("spotifyglass.diagnostics.export", DISPATCH_QUEUE_SERIAL); });
    return writer;
}

// Only the writer queue reads the system log and writes diagnostic files.
static NSError *writeDiagnostics(NSMutableString *text, NSURL *url) {
        // Release builds keep no log of their own. Retain only the newest matching lines, even
        // when a whole day's launch holds tens of thousands.
        [text appendString:@"\n== log, this launch\n"];
        NSError *error = nil;
        OSLogStore *store = [OSLogStore storeWithScope:OSLogStoreCurrentProcessIdentifier error:&error];
        NSPredicate *ours = [NSPredicate predicateWithFormat:
            @"composedMessage BEGINSWITH '[spotifyglass]' AND NOT composedMessage BEGINSWITH '[spotifyglass] screen dump'"];
        const NSUInteger limit = 1500;
        NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithCapacity:limit];
        NSUInteger oldest = 0;
        for (OSLogEntry *entry in [store entriesEnumeratorWithOptions:0 position:nil predicate:ours error:&error]) {
            @autoreleasepool {
                NSString *line = [NSString stringWithFormat:@"%@ %@", entry.date, [entry.composedMessage substringFromIndex:15]];
                if (lines.count < limit) [lines addObject:line];
                else {
                    lines[oldest] = line;
                    oldest = (oldest + 1) % limit;
                }
            }
        }
        for (NSUInteger i = 0; i < lines.count; i++)
            [text appendFormat:@"%@%@", i ? @"\n" : @"", lines[(oldest + i) % lines.count]];
        if (!lines.count) [text appendFormat:@"(none: %@)", error.localizedDescription ?: @"the log is empty"];
        NSURL *caches = SGDataRoot(NSCachesDirectory);
        NSString *config = [NSString stringWithContentsOfURL:[caches URLByAppendingPathComponent:@"live-config.txt"]
                                                    encoding:NSUTF8StringEncoding error:nil];
        [text appendFormat:@"\n\n== config Spotify's server last sent\n%@", config ?: @"(none yet: Spoof Premium is off, or no fetch so far)\n"];
        NSError *writeError = nil;
        NSString *safe = SGRedactDiagnostics(text, NSUserDefaults.standardUserDefaults.dictionaryRepresentation);
        [safe writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:&writeError];
        if (writeError) SGLog(@"diagnostics export failed: %@", writeError.localizedDescription);
        return writeError;
}

void SGExportDiagnosticsToURL(NSURL *url, void (^completion)(NSError *error)) {
    NSMutableString *text = diagnosticMetadata();
    dispatch_async(diagnosticWriter(), ^{
        NSError *error = writeDiagnostics(text, url);
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
    });
}

// NativeDownloads resolves this exact signature with dlsym from its report queue.
NSURL *SGWriteDiagnosticsFile(void) {
    __block NSMutableString *text;
    dispatch_sync(dispatch_get_main_queue(), ^{ text = diagnosticMetadata(); });
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"retrine-diagnostics.txt"]];
    __block NSError *error;
    dispatch_sync(diagnosticWriter(), ^{ error = writeDiagnostics(text, url); });
    return error ? nil : url;
}

BOOL SGDiagnosticsCanPresentFrom(UIViewController *presenter) {
    if (!presenter.viewIfLoaded.window) return NO;
    for (UIViewController *page = presenter; page; page = page.parentViewController) {
        if (page.presentedViewController || page.isBeingPresented || page.isBeingDismissed || page.transitionCoordinator) return NO;
    }
    return YES;
}

void SGShareDiagnostics(UIViewController *presenter) {
    static BOOL exporting;   // main thread, from the settings action and the export's completion
    if (exporting || !SGDiagnosticsCanPresentFrom(presenter)) return;
    exporting = YES;
    __weak UIViewController *weakPresenter = presenter;
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"retrine-diagnostics.txt"]];
    SGExportDiagnosticsToURL(url, ^(NSError *error) {
        exporting = NO;
        UIViewController *owner = weakPresenter;
        if (!SGDiagnosticsCanPresentFrom(owner)) return;
        if (error) {
            showAlert(owner, SGL(@"settings.mod.share_diagnostics.title", @"Share diagnostics"), error.localizedDescription, nil, nil);
            return;
        }
        UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
        sheet.popoverPresentationController.sourceView = owner.view;
        SGPresentDark(sheet);
        [owner presentViewController:sheet animated:YES completion:nil];
    });
}

static Class kindOf(id value) {
    for (Class kind in @[NSNumber.class, NSString.class, NSArray.class, NSDictionary.class]) {
        if ([value isKindOfClass:kind]) return kind;
    }
    return Nil;
}

// A key already stored keeps its type: the hooks send boolValue to whatever they find at launch, and
// an array there would crash Spotify before the reset row could be reached.
// Settings exported by Chroma (spoti.pw 0.50) under its own names, in ours. Its player background knows only
// Fluid (0) and Animated (1); its artwork sources call Spotify's clips "spotify". Its menu row cache and
// one-time notices have no counterpart and are left out.
static NSDictionary *fromChroma(NSDictionary *settings) {
    NSDictionary<NSString *, NSString *> *renamed = @{
        @"spotifyglass.redesign.sing": @"spotifyglass.sing",
        @"spotifyglass.redesign.sing.ignoreHeat": @"spotifyglass.sing.ignoreHeat",
        @"spotifyglass.redesign.spatialVoice": @"spotifyglass.sing.spatial",
        @"spotifyglass.redesign.player.hideVideoSwitch": @"spotifyglass.hide.videoSwitch",
        @"spotifyglass.gestures.head": @"spotifyglass.headgestures",
        @"spotifyglass.redesign.inlinePlayer": @"spotifyglass.redesign.navbar.minimize",
    };
    NSSet<NSString *> *dropped = [NSSet setWithArray:@[@"spotifyglass.redesign.menuNumbers", @"spotifyglass.eevee.warned",
                                                       @"spotifyglass.spotifyversion.warned", @"spotifyglass.lockscreen.lyricsartwork"]];
    NSMutableDictionary *ours = [NSMutableDictionary dictionary];
    for (NSString *key in settings) {
        id value = settings[key];
        if ([dropped containsObject:key]) continue;
        if ([key isEqualToString:@"spotifyglass.redesign.player.backdrop"]) {
            if (![value isKindOfClass:NSNumber.class] && ![value isKindOfClass:NSString.class]) continue;
            ours[@"spotifyglass.redesign.player.background"] = @([value integerValue] == 1 ? SGRPlayerBackgroundAnimated : SGRPlayerBackgroundFluid);
        } else if ([key isEqualToString:@"spotifyglass.redesign.player.artworksources"] && [value isKindOfClass:NSArray.class]) {
            NSMutableArray *sources = [NSMutableArray array];
            for (NSString *source in value) [sources addObject:[source isEqual:@"spotify"] ? @"canvas" : source];
            ours[@"spotifyglass.motion.sources"] = sources;
        } else {
            ours[renamed[key] ?: key] = value;
        }
    }
    return ours;
}

static void importSettings(NSDictionary *settings, NSUserDefaults *store, NSDictionary *stored) {
    settings = fromChroma(settings);
    for (NSString *key in stored) {
        if (isSetting(key)) [store removeObjectForKey:key];
    }
    NSUInteger skipped = 0;
    for (NSString *key in settings) {
        id value = settings[key];
        id current = stored[key];
        BOOL fits = isSetting(key)
            && [NSPropertyListSerialization propertyList:value isValidForFormat:NSPropertyListBinaryFormat_v1_0]
            && (!current || kindOf(current) == kindOf(value));
        if (fits) [store setObject:value forKey:key];
        else skipped++;
    }
    SGLog(@"import: set %lu keys, skipped %lu", (unsigned long)(settings.count - skipped), (unsigned long)skipped);
}

@interface SGSettingsPicker : NSObject <UIDocumentPickerDelegate>
@property (nonatomic, weak) UIViewController *presenter;
@property (nonatomic, weak) UIDocumentPickerViewController *picker;
@property (nonatomic) BOOL pending, reading;
- (void)finish;
@end

static const NSUInteger kSettingsImportLimitBytes = 5 * 1024 * 1024;

// The picker gives us a local copy. Reject a large file before reading it, and bound the stream too
// so a file that grows after the size check cannot make the import allocate without a limit.
static NSDictionary *readSettingsFile(NSURL *url) {
    NSNumber *size = nil;
    if (![url getResourceValue:&size forKey:NSURLFileSizeKey error:nil] || size.unsignedLongLongValue > kSettingsImportLimitBytes) return nil;
    NSInputStream *stream = [NSInputStream inputStreamWithURL:url];
    [stream open];
    NSMutableData *data = [NSMutableData data];
    uint8_t buffer[16384];
    NSInteger count = 0;
    while (data.length <= kSettingsImportLimitBytes
           && (count = [stream read:buffer maxLength:MIN(sizeof(buffer), kSettingsImportLimitBytes + 1 - data.length)]) > 0) {
        [data appendBytes:buffer length:(NSUInteger)count];
    }
    [stream close];
    if (count < 0 || data.length > kSettingsImportLimitBytes) return nil;
    id file = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [file isKindOfClass:NSDictionary.class] && [file[@"settings"] isKindOfClass:NSDictionary.class] ? file : nil;
}

@implementation SGSettingsPicker

- (void)finish {
    self.pending = NO;
    self.reading = NO;
    self.presenter = nil;
    self.picker = nil;
}

- (void)presentFile:(NSDictionary *)file {
    UIViewController *owner = self.presenter;
    if (!SGDiagnosticsCanPresentFrom(owner)) {
        [self finish];
        return;
    }
    NSString *title, *message;
    UIAlertAction *confirm = nil;
    if (file) {
        NSString *mod = [file[@"mod"] isKindOfClass:NSString.class] ? file[@"mod"] : @"unknown";
        title = SGL(@"settings.mod.backup.import_confirm.alert.title", @"Import settings?");
        message = [NSString stringWithFormat:SGL(@"settings.mod.backup.import_confirm.alert.message", @"Your settings are replaced by the file's, exported from version %@. Anything it does not have goes back to its default, and Spotify restarts."), mod];
        confirm = [UIAlertAction actionWithTitle:SGL(@"settings.mod.backup.action.import_and_restart", @"Import and restart") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            [self finish];
            importSettings(file[@"settings"], NSUserDefaults.standardUserDefaults, storedDefaults());
            SGRestartSpotify();
        }];
    } else {
        title = SGL(@"settings.mod.backup.invalid_file.alert.title", @"Not a settings file");
        message = SGL(@"settings.mod.backup.invalid_file.alert.message", @"Pick a file made by Export settings.");
    }
    UIAlertController *alert = showAlert(owner, title, message, confirm, ^{ [self finish]; });
    if (owner.presentedViewController != alert) [self finish];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)picker {
    if (self.picker == picker) [self finish];
}

- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (!self.pending || self.reading || self.picker != picker) return;
    self.reading = YES;
    NSURL *url = urls.firstObject;
    // Finish the picker's own dismissal before reading, so even a tiny file cannot race it.
    void (^read)(void) = ^{
        if (self.picker != picker) return;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSDictionary *file = readSettingsFile(url);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.picker == picker) [self presentFile:file];
            });
        });
    };
    if (picker.isBeingDismissed && picker.transitionCoordinator) {
        [picker.transitionCoordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) { read(); }];
    } else if (picker.presentingViewController) {
        [picker dismissViewControllerAnimated:YES completion:read];
    } else {
        read();
    }
}

@end

void SGImportSettings(UIViewController *presenter) {
    static SGSettingsPicker *delegate;
    if (!delegate) delegate = [SGSettingsPicker new];
    if (delegate.pending || !SGDiagnosticsCanPresentFrom(presenter)) return;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeJSON] asCopy:YES];
    delegate.pending = YES;
    delegate.presenter = presenter;
    delegate.picker = picker;
    picker.delegate = delegate;
    [presenter presentViewController:picker animated:YES completion:nil];
    if (presenter.presentedViewController != picker) [delegate finish];
}

// The Local files page under Playback & local files: Import audio files, which opens Files and copies what is picked
// into Documents (LocalAudioImport.h), and the Imported files page listing those copies, a swipe deleting one
// after asking.
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPage.h"
#import "Settings/SGPageStyle.h"
#import "LocalAudioImport.h"
#import "LocalMusicPages.h"
#import "LocalMusicStore.h"

#pragma mark - the Imported files page

@interface SGImportedAudioPage : SGPage
@end

@implementation SGImportedAudioPage {
    NSArray<NSString *> *_names;
    UIView *_footer;
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = SGL(@"settings.localfiles.imported.title", @"Imported files");
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _footer = SGNote(SGL(@"settings.localfiles.imported.footer", @"Only files imported here are listed. Swipe left on a file to delete it."));
    self.tableView.tableFooterView = _footer;
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    SGFitNote(self.tableView, _footer, 16, 24);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadNames];
}

- (void)reloadNames {
    _names = SGLocalAudioImportedNames(SGLocalAudioFolder(), NSUserDefaults.standardUserDefaults);
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return MAX((NSInteger)_names.count, 1);
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = SGDequeueCell(table, @"audio");
    if (!_names.count) SGFillCell(cell, SGL(@"settings.localfiles.imported.empty", @"No imported files"), nil, SGGrey(), nil);
    else SGFillCell(cell, _names[(NSUInteger)path.row], nil, nil, @"music.note");
    return cell;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)table trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)path {
    if (!_names.count) return nil;
    NSString *name = _names[(NSUInteger)path.row];
    __weak typeof(self) weakSelf = self;
    UIContextualAction *delete = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:SGL(@"common.delete", @"Delete")
        handler:^(UIContextualAction *action, UIView *view, void (^done)(BOOL)) {
            SGImportedAudioPage *page = weakSelf;
            if (!page) { done(NO); return; }
            [page confirmDelete:name done:done];
        }];
    delete.image = [UIImage systemImageNamed:@"trash"];
    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[delete]];
    configuration.performsFirstActionWithFullSwipe = NO;   // a full swipe must not skip the question
    return configuration;
}

- (void)confirmDelete:(NSString *)name done:(void (^)(BOOL))done {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGL(@"settings.localfiles.delete.title", @"Delete this file?")
        message:[NSString stringWithFormat:SGL(@"settings.localfiles.delete.message", @"%@ is deleted from this iPhone and leaves Spotify's Local Files."), name]
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) { done(NO); }]];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.delete", @"Delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        BOOL deleted = SGLocalAudioDelete(name, SGLocalAudioFolder(), NSUserDefaults.standardUserDefaults);
        [NSNotificationCenter.defaultCenter postNotificationName:SGLocalMusicFilesDidChangeNotification object:nil];
        if (deleted) [self reloadNames];
        else SGPresentInformation(self, SGL(@"settings.localfiles.delete.failed", @"Could not delete the file"), name);
        done(deleted);
    }]];
    SGPresentDark(alert);
    [self presentViewController:alert animated:YES completion:nil];
}

@end

#pragma mark - the picker

// One answer for the whole pick: the count imported, and the names that could not be.
static void report(UIViewController *presenter, NSUInteger imported, NSArray<NSString *> *failed) {
    NSString *title = imported == 1 ? SGL(@"settings.localfiles.import.done.one", @"Imported 1 file")
        : imported ? [NSString stringWithFormat:SGL(@"settings.localfiles.import.done.many", @"Imported %lu files"), (unsigned long)imported]
        : SGL(@"settings.localfiles.import.failed.title", @"Could not import");
    NSString *message = failed.count
        ? [NSString stringWithFormat:SGL(@"settings.localfiles.import.failed.message", @"These files could not be copied:\n%@"), [failed componentsJoinedByString:@"\n"]] : nil;
    SGPresentInformation(presenter, title, message);
}

@interface SGAudioPicker : NSObject <UIDocumentPickerDelegate>
@property (nonatomic, weak) UIViewController *presenter;   // the page that opened Files
@end

@implementation SGAudioPicker

- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (!urls.count) return;
    UIViewController *presenter = self.presenter;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<NSString *> *failed = nil;
        NSUInteger imported = SGLocalAudioImport(urls, SGLocalAudioFolder(), NSUserDefaults.standardUserDefaults, &failed).count;
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:SGLocalMusicFilesDidChangeNotification object:nil];
            if ([presenter isKindOfClass:SGModPage.class]) [((SGModPage *)presenter).tableView reloadData];
            if (presenter) report(presenter, imported, failed);
        });
    });
}

@end

void SGLocalAudioPresentPicker(UIViewController *top) {
    static SGAudioPicker *delegate;
    if (!delegate) delegate = [SGAudioPicker new];
    delegate.presenter = top;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeAudio] asCopy:YES];
    picker.allowsMultipleSelection = YES;
    picker.delegate = delegate;
    SGPresentDark(picker);
    [top presentViewController:picker animated:YES completion:nil];
}

UIViewController *SGLocalFilesSettingsPage(void) {
    SGModRow *import = SGWithSymbol(SGActionRow(SGL(@"settings.localfiles.import.title", @"Import audio files"),
        SGL(@"settings.localfiles.import.subtitle", @"Copied from Files, never moved"), ^{ SGLocalAudioPresentPicker(SGTopController()); }), @"square.and.arrow.down");
    SGModRow *imported = SGWithSymbol(SGPageRow(SGL(@"settings.localfiles.imported.title", @"Imported files"), ^UIViewController *{ return [SGImportedAudioPage new]; }), @"music.note.list");
    imported.value = ^NSString *{
        NSUInteger count = SGLocalAudioImportedNames(SGLocalAudioFolder(), NSUserDefaults.standardUserDefaults).count;
        return count ? @(count).stringValue : SGL(@"settings.localfiles.imported.value.none", @"None");
    };
    return [[SGModPage alloc] initWithTitle:SGL(@"settings.localfiles.title", @"Local files") intro:nil sections:@[
        SGNotedSection(nil, @[import], SGL(@"settings.localfiles.import.footer", @"Imported files show in Spotify's Local Files once its setting for showing audio files from this device is on, in Spotify's settings. A file with a name already in use gets a number after it.")),
        SGSection(nil, @[imported, SGWithSymbol(SGPageRow(SGL(@"settings.localmusic.library", @"Local Library"),
            ^UIViewController *{ return SGLocalMusicLibraryPage(); }), @"square.stack")]),
    ] footer:nil];
}

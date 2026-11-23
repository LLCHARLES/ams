// Imported lyrics files, on the Lyrics page beside the sources: the files kept (a swipe deletes one),
// Import for current track…, which links the file to the song playing, Paste, which keeps the
// clipboard's lyrics for it, and Import lyrics…, matched by title and artist. Import opens Files and
// copies the file in; what it holds, TTML, LRC or plain text, is decided by its content.
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "Core/SGCore.h"
#import "Settings/SGPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Player/PlayerState.h"
#import "LocalFiles.h"
#import "LocalLyrics.h"

typedef NS_ENUM(NSInteger, SGLRCImportRow) {
    SGLRCImportForTrack,
    SGLRCImportPasted,
    SGLRCImportByName,
    SGLRCRemoveForTrack,
    SGLRCImportRowCount,
};

static NSString *playingSong(void) {
    NSString *uri = SGURIString(SGPlayerState().track.URI);
    return SGLocalFileIs(uri) || [uri hasPrefix:@"spotify:track:"] ? uri : nil;
}

// Why an import was refused, as its own words: the code says it, so every page says it the same.
static NSString *refusalText(NSError *error) {
    switch (error.code) {
        case SGLyricsImportErrorType:
            return SGL(@"settings.locallyrics.error.type", @"Choose an LRC, TTML, XML or TXT file.");
        case SGLyricsImportErrorNothing:
            return SGL(@"settings.locallyrics.error.nothing", @"There is nothing to import.");
        case SGLyricsImportErrorTooLarge:
            return SGL(@"settings.locallyrics.error.toolarge", @"The lyrics are larger than 1 MB.");
        case SGLyricsImportErrorUnreadableFile:
            return SGL(@"settings.locallyrics.error.unreadablefile", @"The file could not be read.");
        case SGLyricsImportErrorStorage:
            return SGL(@"settings.locallyrics.error.storage", @"The lyrics could not be saved. The ones it had are unchanged.");
        default:
            return SGL(@"settings.locallyrics.error.unreadable", @"The lyrics could not be read as text.");
    }
}

@interface SGImportedLRCFilesPage : SGPage <UIDocumentPickerDelegate, SGPlayerStateObserver>
@end

@implementation SGImportedLRCFilesPage {
    NSArray<NSString *> *_files;
    UIView *_footer;
    // The song playing when Files opened, even if the player has since moved on.
    NSString *_linkTo;
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = SGL(@"settings.locallyrics.title", @"Imported lyrics files");
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    SGAddPlayerStateObserver(self);
    _footer = SGNote(SGL(@"settings.locallyrics.song.footer", @"Import or paste lyrics for the song playing. For local files, Import lyrics… can also match by title and artist. Swipe left on a file to delete it."));
    self.tableView.tableFooterView = _footer;
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    if (self.viewIfLoaded.window) [self.tableView reloadData];
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
    [self reloadFiles];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    return 2;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? MAX((NSInteger)_files.count, 1) : SGLRCImportRowCount;
}

- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    return section == 0 ? SGSectionHeader(table, SGL(@"settings.locallyrics.files.header", @"Files")) : nil;
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    return section == 0 ? SGSectionHeaderHeight() : SGSectionGap;
}

- (UIView *)tableView:(UITableView *)table viewForFooterInSection:(NSInteger)section {
    return nil;
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section == 1) {
        UITableViewCell *cell = SGDequeueCell(table, @"import");
        if (path.row == SGLRCImportByName) {
            SGFillCell(cell, SGL(@"settings.locallyrics.importbyname.title", @"Import lyrics…"), SGL(@"settings.locallyrics.importbyname.subtitle", @"Matched by title and artist"), nil, @"square.and.arrow.down");
        } else {
            NSString *uri = playingSong();
            BOOL paste = path.row == SGLRCImportPasted, remove = path.row == SGLRCRemoveForTrack;
            NSString *action = remove ? SGL(@"settings.locallyrics.song.remove", @"Remove lyrics for current track")
                : paste ? SGL(@"settings.locallyrics.paste.title", @"Paste") : SGL(@"settings.locallyrics.importfortrack.title", @"Import for current track…");
            NSString *subtitle = !uri ? SGL(@"settings.locallyrics.song.notplaying", @"Play a song first")
                : remove ? SGImportedLRCLinkedTo(uri) : SGPlayerState().track.trackTitle ?: uri;
            SGFillCell(cell, action, subtitle, (!uri || (remove && !subtitle)) ? SGGrey() : nil,
                       remove ? @"trash" : paste ? @"doc.on.clipboard" : @"music.note");
        }
        BOOL enabled = [self tableView:table shouldHighlightRowAtIndexPath:path];
        cell.selectionStyle = enabled ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
        cell.accessibilityTraits = enabled ? UIAccessibilityTraitButton : UIAccessibilityTraitButton | UIAccessibilityTraitNotEnabled;
        return cell;
    }
    UITableViewCell *cell = SGDequeueCell(table, @"file");
    if (!_files.count) {
        SGFillCell(cell, SGL(@"settings.locallyrics.files.empty", @"No imported files"), nil, SGGrey(), nil);
        return cell;
    }
    NSString *name = _files[(NSUInteger)path.row];
    SGFillCell(cell, name, [SGImportedLRCLinkedTo(playingSong()) isEqual:name] ? SGPlayerState().track.trackTitle : nil, nil, nil);
    return cell;
}

- (BOOL)tableView:(UITableView *)table shouldHighlightRowAtIndexPath:(NSIndexPath *)path {
    return path.section == 1 && (path.row == SGLRCImportByName ||
        (path.row == SGLRCRemoveForTrack ? SGImportedLRCLinkedTo(playingSong()) != nil : playingSong() != nil));
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (path.section != 1) return;
    _linkTo = path.row == SGLRCImportByName ? nil : playingSong();
    if (!_linkTo && path.row != SGLRCImportByName) return;
    if (path.row == SGLRCRemoveForTrack) {
        SGDeleteImportedLRC(SGImportedLRCLinkedTo(_linkTo), ^(BOOL deleted) {
            [self reloadFiles];
            if (!deleted) SGPresentInformation(self, SGL(@"settings.locallyrics.error.deletefailed", @"Could not delete the file"), nil);
        });
        return;
    }
    if (path.row == SGLRCImportPasted) {
        [self pasteInto:_linkTo];
        return;
    }
    NSMutableArray *types = [NSMutableArray array];
    for (NSString *ext in @[@"lrc", @"ttml", @"xml", @"txt"])
        [types addObject:[UTType typeWithFilenameExtension:ext conformingToType:UTTypeData]];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

// Read only once the row is tapped: the page itself never touches the clipboard, and an empty one says
// so instead of importing nothing.
- (void)pasteInto:(NSString *)uri {
    NSString *text = UIPasteboard.generalPasteboard.string;
    if (!text.length) {
        SGPresentInformation(self, SGL(@"settings.locallyrics.error.nothing.title", @"Nothing to import"), SGL(@"settings.locallyrics.clipboard.empty", @"The clipboard has no text."));
        return;
    }
    SGImportPastedLyrics(text, uri, ^(NSString *name, NSError *error) {
        if (!name) {
            BOOL nothing = error.code == SGLyricsImportErrorNothing;
            SGPresentInformation(self, nothing ? SGL(@"settings.locallyrics.error.nothing.title", @"Nothing to import")
                                               : SGL(@"settings.locallyrics.error.pastefailed", @"Could not import the lyrics"), refusalText(error));
            return;
        }
        [self reloadFiles];
        [self sayLinked:name to:uri];
    });
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)table trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section != 0 || !_files.count) return nil;
    NSString *name = _files[(NSUInteger)path.row];
    // The store answers on the main queue once the file is gone, which is when the row goes and the
    // swipe's own completion can be told.
    __weak typeof(self) weakSelf = self;
    UIContextualAction *delete = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:SGL(@"common.delete", @"Delete")
        handler:^(UIContextualAction *action, UIView *view, void (^done)(BOOL)) {
            SGDeleteImportedLRC(name, ^(BOOL deleted) {
                SGImportedLRCFilesPage *page = weakSelf;
                if (deleted) [page reloadFiles];
                else if (page) SGPresentInformation(page, SGL(@"settings.locallyrics.error.deletefailed", @"Could not delete the file"), nil);
                done(deleted);
            });
        }];
    delete.image = [UIImage systemImageNamed:@"trash"];
    return [UISwipeActionsConfiguration configurationWithActions:@[delete]];
}

- (void)reloadFiles {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("app.retrine.lyrics-list", DISPATCH_QUEUE_SERIAL); });
    dispatch_async(queue, ^{
        NSArray *names = SGImportedLRCFiles();
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_files = names;
            [self.tableView reloadData];
        });
    });
}

// Says what the file now gives, for a file linked to the local file playing.
- (void)sayLinked:(NSString *)name to:(NSString *)uri {
    if (!uri) return;
    NSString *title = [uri isEqual:playingSong()] ? SGPlayerState().track.trackTitle : nil;
    title = title ?: SGLocalFileInfo(uri)[@"title"] ?: uri;
    SGPresentInformation(self, SGL(@"settings.locallyrics.linked.title", @"Lyrics linked"), [NSString stringWithFormat:SGL(@"settings.locallyrics.linked.message", @"%@ now gives the lyrics for %@."), name,
                                                                 [NSString stringWithFormat:@"\"%@\"", title]]);
}

- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    NSString *linkTo = _linkTo;
    SGImportLRC(url, linkTo, ^(NSString *name, NSError *error) {
        if (!name) {
            SGPresentInformation(self, SGL(@"settings.locallyrics.error.importfailed", @"Could not import the file"), refusalText(error));
            return;
        }
        [self reloadFiles];
        [self sayLinked:name to:linkTo];
    });
}

@end

UIViewController *SGImportedLRCPage(void) {
    return [SGImportedLRCFilesPage new];
}

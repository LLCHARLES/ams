// The Blocked artists page: the switch, whether a featured credit counts, blocking someone off the
// track playing now, and the list, swiped to unblock. The hook reads all of it per track, so a change
// needs no restart.
#import "Core/SGCore.h"
#import "Settings/SGPage.h"
#import "Settings/SGPageStyle.h"
#import "ArtistBlock.h"

typedef NS_ENUM(NSInteger, SGArtistSection) {
    SGArtistSectionSwitch,
    SGArtistSectionMode,
    SGArtistSectionAdd,
    SGArtistSectionList,
    SGArtistSectionCount,
};

@interface SGArtistBlockPage : SGPage
@end

@implementation SGArtistBlockPage {
    NSArray<NSDictionary *> *_blocked;
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = SGL(@"settings.artistblock.title", @"Blocked Artists");
    _blocked = SGBlockedArtists();
    return self;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}

- (void)reload {
    _blocked = SGBlockedArtists();
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    return SGArtistSectionCount;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    if (section == SGArtistSectionMode) return 2;
    if (section == SGArtistSectionList) return MAX((NSInteger)_blocked.count, 1);
    return 1;
}

- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    if (section == SGArtistSectionMode) return SGSectionHeader(table, SGL(@"settings.artistblock.mode.header", @"Skip when the artist is"));
    if (section == SGArtistSectionList) return SGSectionHeader(table, SGL(@"settings.artistblock.list.header", @"Blocked"));
    return nil;
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    return section == SGArtistSectionMode || section == SGArtistSectionList ? SGSectionHeaderHeight() : SGSectionGap;
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = SGDequeueCell(table, @"artist");
    switch (path.section) {
        case SGArtistSectionSwitch: {
            SGFillCell(cell, SGL(@"settings.artistblock.enable.title", @"Skip blocked artists"), nil, nil, nil);
            UISwitch *toggle = [UISwitch new];
            toggle.onTintColor = SGGreen();
            toggle.on = SGFlag(SGKeyArtistBlock, NO);
            [toggle addTarget:self action:@selector(toggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
            break;
        }
        case SGArtistSectionMode: {
            BOOL featured = path.row == 1;
            SGFillCell(cell, featured ? SGL(@"settings.artistblock.mode.featured.title", @"Main or featured") : SGL(@"settings.artistblock.mode.main.title", @"The main artist"),
                       featured ? SGL(@"settings.artistblock.mode.featured.subtitle", @"Any credit on the track") : SGL(@"settings.artistblock.mode.main.subtitle", @"The first name on the track"), nil, nil);
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            if (featured == SGFlag(SGKeyArtistBlockFeatured, NO)) {
                UIImageView *tick = SGSymbolView(@"checkmark", 13, UIImageSymbolWeightSemibold, 16);
                tick.tintColor = SGGreen();
                cell.accessoryView = tick;
            }
            break;
        }
        case SGArtistSectionAdd:
            SGFillCell(cell, SGL(@"settings.artistblock.add_playing.title", @"Block from what's playing…"), nil, nil, @"person.crop.circle.badge.xmark");
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            break;
        default:
            if (!_blocked.count) {
                SGFillCell(cell, SGL(@"settings.artistblock.empty.title", @"No one yet"), nil, SGGrey(), nil);
                break;
            }
            NSDictionary *artist = _blocked[(NSUInteger)path.row];
            SGFillCell(cell, artist[SGArtistName], artist[SGArtistURI], nil, nil);
            break;
    }
    BOOL enabled = path.section == SGArtistSectionSwitch || SGFlag(SGKeyArtistBlock, NO);
    cell.userInteractionEnabled = enabled;
    cell.contentView.alpha = cell.accessoryView.alpha = enabled ? 1 : 0.45;
    if (enabled) cell.accessibilityTraits &= ~UIAccessibilityTraitNotEnabled;
    else cell.accessibilityTraits |= UIAccessibilityTraitNotEnabled;
    return cell;
}

- (BOOL)tableView:(UITableView *)table canEditRowAtIndexPath:(NSIndexPath *)path {
    return path.section == SGArtistSectionList && _blocked.count > 0 && SGFlag(SGKeyArtistBlock, NO);
}

- (NSString *)tableView:(UITableView *)table titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)path {
    return SGL(@"settings.artistblock.action.unblock", @"Unblock");
}

- (void)tableView:(UITableView *)table commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)path {
    if (style != UITableViewCellEditingStyleDelete || ![self tableView:table canEditRowAtIndexPath:path]) return;
    SGUnblockArtist(_blocked[(NSUInteger)path.row][SGArtistURI]);
    [self reload];
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (!SGFlag(SGKeyArtistBlock, NO)) return;
    if (path.section == SGArtistSectionMode) {
        SGSetEnabled(SGKeyArtistBlockFeatured, path.row == 1);
        [self reload];
    } else if (path.section == SGArtistSectionAdd) {
        [self pickFromPlaying:[table cellForRowAtIndexPath:path]];
    }
}

- (void)pickFromPlaying:(UIView *)source {
    NSArray<NSDictionary *> *artists = SGPlayingArtists();
    if (!artists.count) {
        SGPresentInformation(self, SGL(@"settings.artistblock.nothing_playing.alert.title", @"Nothing playing"),
                             SGL(@"settings.artistblock.nothing_playing.alert.message", @"Play a track by the artist first, then come back here."));
        return;
    }
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:SGL(@"settings.artistblock.pick.action_sheet.title", @"Block")
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    [artists enumerateObjectsUsingBlock:^(NSDictionary *artist, NSUInteger index, BOOL *stop) {
        BOOL blocked = SGArtistBlocked(artist[SGArtistURI]);
        NSString *title = index == 0 ? artist[SGArtistName] : [NSString stringWithFormat:SGL(@"settings.artistblock.pick.featured.format", @"%@ (featured)"), artist[SGArtistName]];
        UIAlertAction *action = [UIAlertAction actionWithTitle:title style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
            SGBlockArtist(artist);
            [self reload];
        }];
        action.enabled = !blocked;
        [sheet addAction:action];
    }];
    [sheet addAction:[UIAlertAction actionWithTitle:SGL(@"common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = source;
    sheet.popoverPresentationController.sourceRect = source.bounds;
    SGPresentDark(sheet);
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)toggled:(UISwitch *)toggle {
    SGSetEnabled(SGKeyArtistBlock, toggle.on);
    [self reload];
}

@end

UIViewController *SGArtistBlockSettingsPage(void) {
    return [SGArtistBlockPage new];
}

@interface SGSongBlockPage : SGPage
@end

@implementation SGSongBlockPage {
    NSDictionary<NSString *, NSArray<NSString *> *> *_songs;
    NSArray<NSString *> *_uris;
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = SGL(@"settings.songblock.title", @"Blocked Songs");
    return self;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)reload {
    _songs = SGBlockedSongs();
    _uris = [_songs.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [self->_songs[a].firstObject localizedCaseInsensitiveCompare:self->_songs[b].firstObject];
    }];
    [self.tableView reloadData];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return MAX((NSInteger)_uris.count, 1);
}

- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    return SGL(@"settings.songblock.footer", @"Block a song from the player's ⋯ menu. Blocked songs are skipped wherever they come up. Swipe to unblock. After five skips in ten seconds, a blocked track is left playing to prevent an endless skip loop.");
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = SGDequeueCell(table, @"song");
    if (!_uris.count) {
        SGFillCell(cell, SGL(@"settings.songblock.empty", @"No blocked songs"), nil, SGGrey(), nil);
    } else {
        NSArray<NSString *> *song = _songs[_uris[(NSUInteger)path.row]];
        SGFillCell(cell, song.firstObject, song.lastObject, nil, nil);
    }
    return cell;
}

- (BOOL)tableView:(UITableView *)table canEditRowAtIndexPath:(NSIndexPath *)path {
    return _uris.count > 0;
}

- (NSString *)tableView:(UITableView *)table titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)path {
    return SGL(@"settings.artistblock.action.unblock", @"Unblock");
}

- (void)tableView:(UITableView *)table commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)path {
    if (style != UITableViewCellEditingStyleDelete) return;
    SGSetSongBlocked(_uris[(NSUInteger)path.row], nil, nil, NO);
    [self reload];
}
@end

UIViewController *SGSongBlockSettingsPage(void) {
    return [SGSongBlockPage new];
}

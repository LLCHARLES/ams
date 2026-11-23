// Player redesign: the ⋯ beside the title, where the Music app has it, opens the system menu (Redesigned/ContextMenu):
// the song's actions first and Retrine's after them. Share, Add to playlist and Add to queue in a row at its top, then
// the title row's own buttons, which the ⋯ takes the place of -- the add button (Save to Your Library, or Change
// Where It's Saved once saved) and Spotify's X when it shows one (feedback_headunit_right_ban_button, "Don't play
// this") -- each fired as a tap on it would be, and each left out while Spotify's rows have its action (Add to Liked
// Songs for a song not saved yet, Hide in this playlist or album). With Star add button on, the add button stays on the
// row as a star (Kit/SGRPlainCheck.x) and the ⋯ stands in the row's end after it, so the menu has no add item. Then
// the rest of Spotify's rows, and then the
// player's own items here, which take over what Speed and pitch's block is on Spotify's sheet:
//
//     Speed, Pitch & Reverb   opens the sliders in a popover from the ⋯ (SGPlayerShowSpeedPitchPanel): speed,
//                             pitch, reverb and Pitch follows speed, as on Spotify's sheet (issue #14)
//     Audio effects           Mod Settings' Audio effects page as a sheet over the player (AudioEffectsPage.h),
//                             what the effects are doing under its name, as Mod Settings' row reads it
//     Share Song Card         a song's cover, title and artist as a picture, through the share sheet (ShareCards.h)
//     Search Lyrics           LRCLIB searched by hand for the song, its pick pinned to it (Redesigned/Lyrics/LyricsTools.h)
//     Show Fluid Artwork, Show Animated Artwork, Show Visualizer
//                             a button for each of the two the background is not, while it is one of the
//                             three, named for what it switches to
//     Lyrics Source           a song's lyrics from another source than the one the order chose (issue #67), in a
//                             popover from the ⋯ that asks every source and lists each as it answers
//
// The item says under its name what is not as Spotify plays it, so the menu reads as a settings summary.
#import "Core/SGCore.h"
#import "Redesigned/ContextMenu/ContextMenu.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/SpeedPitch.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsSources/LyricsSources.h"
#import "Settings/SGPageStyle.h"
#import "Player.h"
#import "Redesigned/Lyrics/LyricsTools.h"
#import "Redesigned/Lyrics/LyricsLook.h"
#import "Core/SGLocalize.h"
#import "Shared/LyricsPiP/LyricsPiP.h"
#import "PlayerQueue.h"
#import "ShareCards.h"
#import "Shared/ArtistBlock/ArtistBlock.h"
#import "Shared/AudioEffects/AudioEffectsPage.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Kit/SGRRefinements.h"

static __weak UIView *sg_moreButton;   // the ⋯ the panels come from: the mod's, beside the title
static __weak UIView *sg_spotifyMore;  // Spotify's own ⋯ in the header, whose action brings its sheet up
// The title row's buttons the ⋯ took the place of: the add button (a UIButton) and the X (an Encore button, a UIControl).
static __weak UIControl *sg_addButton, *sg_banButton;

static UIImage *symbol(NSString *name) {
    return [UIImage systemImageNamed:name];
}

static NSString *speedText(double speed) {
    NSString *text = [NSString stringWithFormat:@"%.2f", speed];
    while ([text hasSuffix:@"0"]) text = [text substringToIndex:text.length - 1];
    if ([text hasSuffix:@"."]) text = [text substringToIndex:text.length - 1];
    return [text stringByAppendingString:@"×"];
}

static NSString *semitonesText(float semitones) {
    if (semitones == 0) return @"Original";
    return [NSString stringWithFormat:@"%@%.0f %@", semitones > 0 ? @"+" : @"−", fabsf(semitones), fabsf(semitones) == 1 ? @"Semitone" : @"Semitones"];
}

// While pitch follows a speed that is not normal, the speed sets the pitch and the semitones are not played
// (SGTimePitch.h), so they stand aside, as on the sheet.
static BOOL pitchFollowing(void) {
    return SGPlayerSpeedAllowed() && SGPlayerPitchFollowsSpeed() && SGPlayerSpeed() != 1;
}

// One item for the three, which says what is not as Spotify plays it, or Normal.
static UIAction *soundMenu(void) {
    NSMutableArray<NSString *> *changed = [NSMutableArray array];
    if (SGPlayerSpeedAllowed() && fabs(SGPlayerSpeed() - 1) >= 0.01) [changed addObject:speedText(SGPlayerSpeed())];
    if (SGPlayerPitchAvailable() && !pitchFollowing() && SGPlayerPitch() != 0) [changed addObject:semitonesText(SGPlayerPitch())];
    if (SGPlayerReverb() > 0) [changed addObject:[NSString stringWithFormat:@"Reverb %.0f%%", SGPlayerReverb()]];
    UIAction *open = [UIAction actionWithTitle:SGL(@"settings.player.sound_menu", @"Speed, Pitch & Reverb") image:symbol(@"slider.horizontal.3") identifier:nil
                                       handler:^(UIAction *action) { SGPlayerShowSpeedPitchPanel(sg_moreButton); }];
    open.subtitle = changed.count ? [changed componentsJoinedByString:@", "] : @"Normal";
    return open;
}

static UIAction *audioEffectsItem(void) {
    UIAction *open = [UIAction actionWithTitle:SGL(@"settings.main.audio_effects.title", @"Audio effects") image:symbol(@"slider.vertical.3") identifier:nil
                                       handler:^(UIAction *action) { SGDSPShowSettingsSheet(sg_moreButton); }];
    open.subtitle = SGDSPSummary();
    return open;
}

static NSString *sheetKind(void);

static NSString *timingText(NSArray<SGKaraokeLine *> *lines) {
    switch (SGKaraokeLinesTiming(lines)) {
        case SGKaraokeTimingWords: return SGL(@"settings.lyricssources.timing.words", @"Word by word");
        case SGKaraokeTimingLine: return SGL(@"settings.lyricssources.timing.lines", @"Line by line");
        default: return SGL(@"settings.lyricssources.timing.none", @"Not synced");
    }
}

// A row of the panel: a source to pick (nil key: Automatic), or one still asked, or the note that none has lines.
@interface SGRSourceRow : NSObject
@property (nonatomic, copy) NSString *key, *title, *subtitle;
@property (nonatomic) BOOL picked, asking, note;
@end

@implementation SGRSourceRow
@end

// The Lyrics Source panel, a popover from the ⋯ like Speed, Pitch & Reverb's: a menu's submenu ran its rows
// under its own title when scrolled, and could not take a source that answered after it opened. Here the title
// scrolls with the rows, and each answer fills its row in while the panel is open.
@interface SGRLyricsSourcePanel : UITableViewController
@property (nonatomic, copy) NSString *track;
@end

@implementation SGRLyricsSourcePanel {
    NSArray<SGRSourceRow *> *_rows;
}

static const CGFloat kSourcePanelWidth = 300, kSourcePanelMaxHeight = 440;

- (instancetype)init {
    return [super initWithStyle:UITableViewStylePlain];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundColor = UIColor.clearColor;
    UILabel *title = [UILabel new];
    title.text = SGL(@"settings.lyricssources.pick.menu", @"Lyrics Source");
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    title.textColor = UIColor.labelColor;
    title.accessibilityTraits = UIAccessibilityTraitHeader;
    title.frame = CGRectMake(20, 16, kSourcePanelWidth - 40, ceil(title.font.lineHeight));
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kSourcePanelWidth, CGRectGetMaxY(title.frame) + 6)];
    [header addSubview:title];
    self.tableView.tableHeaderView = header;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(offersChanged:) name:SGLyricsOffersDidChangeNotification object:nil];
    SGLyricsAskOffers(_track);
    [self rebuild];
}

- (void)offersChanged:(NSNotification *)note {
    if ([note.object isEqual:_track]) [self rebuild];
}

// Automatic, checked while nothing is picked and naming what the order chose, then the sources in the order:
// those with lines for the track, the one picked checked, and those still asked with a spinner.
- (void)rebuild {
    NSArray<NSString *> *asking = nil;
    NSDictionary<NSString *, SGLyricsResult *> *offers = SGLyricsOffersSoFar(_track, &asking);
    NSString *current = SGLyricsChosenSource(_track);
    SGRSourceRow *automatic = [SGRSourceRow new];
    automatic.title = SGL(@"settings.lyricssources.pick.automatic", @"Automatic");
    automatic.subtitle = current ? SGL(@"settings.lyricssources.pick.order", @"As the order chooses") : SGLyricsCreditFor(_track);
    automatic.picked = !current;
    NSMutableArray<SGRSourceRow *> *rows = [NSMutableArray arrayWithObject:automatic];
    for (NSString *key in SGLyricsOrder()) {
        SGLyricsResult *offer = offers[key];
        BOOL out = [asking containsObject:key];
        if (!offer && !out) continue;
        SGRSourceRow *row = [SGRSourceRow new];
        row.key = key;
        row.title = SGLyricsProviderFor(key).name;
        row.subtitle = offer ? timingText(offer.karaokeLines) : SGL(@"settings.lyricssources.offers.loading", @"Asking…");
        row.asking = !offer;
        row.picked = offer && [key isEqualToString:current];
        [rows addObject:row];
    }
    if (rows.count == 1) {
        SGRSourceRow *none = [SGRSourceRow new];
        none.title = SGL(@"settings.lyricssources.offers.empty", @"No Source Has Lyrics");
        none.note = YES;
        [rows addObject:none];
    }
    _rows = rows;
    [self.tableView reloadData];
    [self.tableView layoutIfNeeded];
    self.preferredContentSize = CGSizeMake(kSourcePanelWidth, MIN(self.tableView.contentSize.height, kSourcePanelMaxHeight));
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return _rows.count;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    SGRSourceRow *row = _rows[path.row];
    UITableViewCell *cell = [table dequeueReusableCellWithIdentifier:@"source"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"source"];
    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    content.text = row.title;
    content.secondaryText = row.subtitle;
    BOOL dim = row.asking || row.note;
    content.textProperties.color = dim ? UIColor.secondaryLabelColor : UIColor.labelColor;
    content.secondaryTextProperties.color = UIColor.secondaryLabelColor;
    cell.contentConfiguration = content;
    cell.backgroundColor = UIColor.clearColor;
    cell.tintColor = UIColor.labelColor;
    cell.selectionStyle = dim ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleDefault;
    cell.accessoryType = row.picked ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    UIActivityIndicatorView *spinner = nil;
    if (row.asking) {
        spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        [spinner startAnimating];
    }
    cell.accessoryView = spinner;
    cell.accessibilityTraits = dim ? UIAccessibilityTraitNotEnabled : UIAccessibilityTraitButton | (row.picked ? UIAccessibilityTraitSelected : 0);
    return cell;
}

- (NSIndexPath *)tableView:(UITableView *)table willSelectRowAtIndexPath:(NSIndexPath *)path {
    SGRSourceRow *row = _rows[path.row];
    return row.asking || row.note ? nil : path;
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    SGRSourceRow *row = _rows[path.row];
    if (row.key) SGLyricsChooseSource(_track, row.key);
    else SGLyricsChooseAutomatic(_track);
    [self dismissViewControllerAnimated:YES completion:nil];
}
@end

static UIAction *lyricsSourceItem(void) {
    NSString *track = SGKaraokePlayingTrack();
    if (!SGLyricsEnabled() || !track.length || [sheetKind() isEqualToString:@"episode"]) return nil;
    UIAction *open = [UIAction actionWithTitle:SGL(@"settings.lyricssources.pick.menu", @"Lyrics Source") image:symbol(@"quote.bubble") identifier:nil handler:^(UIAction *action) {
        SGRLyricsSourcePanel *panel = [SGRLyricsSourcePanel new];
        panel.track = track;
        panel.preferredContentSize = CGSizeMake(kSourcePanelWidth, 200);
        SGPresentPopover(panel, sg_moreButton);
    }];
    open.subtitle = SGLyricsCreditFor(track);
    return open;
}

static NSArray<UIMenuElement *> *playerItems(void) {
    NSMutableArray<UIMenuElement *> *items = [NSMutableArray arrayWithObjects:soundMenu(), audioEffectsItem(), nil];
    SPTPlayerTrack *track = SGPlayerState().track;
    NSString *uri = SGURIString(track.URI);
    if ([uri hasPrefix:@"spotify:track:"]) {
        // The song as a picture to share: its cover, title and artist (ShareCards.h).
        [items addObject:[UIAction actionWithTitle:SGL(@"settings.player.song_card.menu", @"Share Song Card") image:symbol(@"photo.on.rectangle")
                                        identifier:nil handler:^(UIAction *action) { SGRShareSongCard(sg_moreButton); }]];
        BOOL blocked = SGSongBlocked(uri);
        NSString *title = track.trackTitle;
        NSString *artist = track.artistName;
        UIAction *block = [UIAction actionWithTitle:blocked ? SGL(@"settings.songblock.unblock", @"Unblock This Song") : SGL(@"settings.songblock.block", @"Block This Song")
                                              image:symbol(blocked ? @"hand.raised.slash" : @"hand.raised") identifier:nil
                                            handler:^(UIAction *action) { SGSetSongBlocked(uri, title, artist, !blocked); }];
        if (!blocked) block.attributes = UIMenuElementAttributesDestructive;
        [items addObject:block];
    }
    [items addObject:[UIAction actionWithTitle:SGLyricsPiPMenuTitle() image:symbol(@"pip") identifier:nil
        handler:^(UIAction *action) { SGLyricsPiPToggle(sg_moreButton); }]];
    // What plays after this, a song's or an episode's (PlayerQueue.m).
    [items addObject:[UIAction actionWithTitle:SGL(@"settings.player.queue.menu", @"Playing Next") image:symbol(@"list.bullet") identifier:nil
        handler:^(UIAction *action) { SGRPlayerShowQueue(sg_moreButton); }]];
    // Not for a podcast: LRCLIB has songs.
    UIAction *search = [sheetKind() isEqualToString:@"episode"] ? nil : SGRLyricsSearchAction(SGKaraokePlayingTrack());
    if (search) [items addObject:search];
    if (![sheetKind() isEqualToString:@"episode"])
        [items addObject:SGRLyricsStyleMenu(SGL(@"settings.lyricsstyle.menu", @"Lyrics Style"))];
    if (SGPlayerMenuOffersAnimatedArtwork()) {
        // Buttons named for what they do, not checkmarks: the HIG's changeable label for a toggled item.
        NSArray<NSArray *> *backgrounds = @[
            @[@(SGRPlayerBackgroundFluid), SGL(@"settings.player.menu.show_fluid", @"Show Fluid Artwork"), @"drop"],
            @[@(SGRPlayerBackgroundAnimated), SGL(@"settings.player.menu.show_animated", @"Show Animated Artwork"), @"play.rectangle.on.rectangle"],
            @[@(SGRPlayerBackgroundVisualiser), SGL(@"settings.player.menu.show_visualizer", @"Show Visualizer"), @"waveform"],
        ];
        SGRPlayerBackgroundKind current = SGRPlayerBackground();
        for (NSArray *background in backgrounds) {
            SGRPlayerBackgroundKind kind = [background[0] integerValue];
            if (kind == current) continue;
            [items addObject:[UIAction actionWithTitle:background[1] image:symbol(background[2]) identifier:nil
                                               handler:^(UIAction *action) { SGRPlayerMenuSetBackground(kind); }]];
        }
    }
    UIAction *lyrics = lyricsSourceItem();
    if (lyrics) [items addObject:lyrics];
    return items;
}

// What the player is playing, from its URI (spotify:track:…, spotify:episode:…, spotify:local:…): a podcast's
// sheet has other rows than a song's.
static NSString *sheetKind(void) {
    NSArray<NSString *> *parts = [SGURIString(SGPlayerState().track.URI) componentsSeparatedByString:@":"];
    return parts.count > 2 ? parts[1] : @"";
}

#pragma mark - the title row's buttons

// Whether Spotify shows `button`: neither it nor a view above it in `row` hidden. Its slot's alpha is the mod's (the ⋯
// is drawn in its place), so alpha is not asked.
static BOOL shownBySpotify(UIView *button, UIView *row) {
    if (!button.window || button.bounds.size.width < 1) return NO;
    for (UIView *view = button; view && view != row; view = view.superview) {
        if (view.hidden) return NO;
    }
    return YES;
}

// The rows of Spotify's sheet that do what the title row's buttons do, by their identifiers (Spotify's item numbers,
// read off 9.1.90's and 9.2.0's sheets): Add to Liked Songs, which the sheet has for a song not saved yet, as the add
// button saves it (a saved song's sheet has no such row; an episode's is Add to Your Episodes, the same item); and
// Hide in this playlist, or album, which the X does there
// (outside one the sheet has none, and a hidden song's has Show in this playlist, 8, instead). The menu leaves a
// button's item out while it shows its row (ContextMenu.h).
static NSString *const kLikedSongsRow = @"18", *const kHideRow = @"7";

static UIAction *titleRowAction(UIControl *button, NSString *title, NSString *symbol, NSString *spotifyRow) {
    UIAction *action = [UIAction actionWithTitle:title image:[UIImage systemImageNamed:symbol] identifier:spotifyRow
                                         handler:^(UIAction *picked) { SGRFireControl(button); }];
    if (!button.enabled) action.attributes = UIMenuElementAttributesDisabled;
    return action;
}

// The add button, named for what its tap does: an unsaved song's saves it (where, Spotify decides), a saved one's
// opens Spotify's Saved in sheet to change where it is saved. Spotify marks a saved song by selecting the button, in
// any playlist, so the selection is not read as Liked Songs (Spotify's Like row in the menu is its own). Its glyph is
// Spotify's plus or circled tick. Left out with Star add button on, the button then on the row itself. Then
// Spotify's X, in Spotify's words, while Spotify shows it. Each fires its button, and stands aside for Spotify's row
// that does the same.
static NSArray<UIMenuElement *> *titleRowItems(void) {
    NSMutableArray<UIMenuElement *> *items = [NSMutableArray array];
    UIControl *add = sg_addButton, *ban = sg_banButton;
    UIView *row = sg_moreButton.superview;
    if (add && !SGRStarAddOn() && shownBySpotify(add, row)) {
        BOOL saved = add.isSelected;
        NSString *title = saved ? SGL(@"player.menu.add.saved", @"Change Where It's Saved") : SGL(@"player.menu.add.save", @"Save to Your Library");
        [items addObject:titleRowAction(add, title, saved ? @"checkmark.circle.fill" : @"plus.circle", kLikedSongsRow)];
    }
    if (ban && shownBySpotify(ban, row) && ban.accessibilityLabel.length)
        [items addObject:titleRowAction(ban, ban.accessibilityLabel, @"xmark.circle", kHideRow)];
    return items;
}

static SGRMenuItems sg_leadItems = ^NSArray<UIMenuElement *> *{ return titleRowItems(); };
static SGRMenuItems sg_playerItems = ^NSArray<UIMenuElement *> *{ return playerItems(); };
static SGRMenuKind sg_kind = ^NSString *{ return sheetKind(); };

void SGRPlayerMenuWatch(UIView *button) {
    sg_spotifyMore = button;
    UIView *host = sg_moreButton.superview;
    if (host) SGRSystemMenuButtonIn(host, button, sg_leadItems, sg_playerItems, sg_kind);
}

// The Music app's ⋯ glyph beside the title, in the title's color.
static const CGFloat kMoreGlyphSize = 20;
// The slot the ⋯ takes in the row's end, where the row has no add button or keeps it for the star: Spotify's add
// button's own size.
static const CGFloat kMoreSlot = 48;
static char kAddKey, kBanKey;

// `button`'s slot in `row`: the arranged view holding it (Spotify's ElementView).
static UIView *slotIn(UIView *button, UIView *row) {
    UIView *slot = button;
    while (slot && slot.superview != row) slot = slot.superview;
    return slot;
}

// The slot, not the button, is put away: Spotify gives the add button its alpha back as it redraws its state (9.2.0
// simulator, 2026-11-18), and leaves the slot's to its hidden flag.
static void hideForMore(UIView *slot) {
    if (slot.alpha != 0) slot.alpha = 0;
    if (!slot.accessibilityElementsHidden) slot.accessibilityElementsHidden = YES;
}

void SGRPlayerMenuInTitleRow(UIView *title) {
    UIView *row = title.superview;
    if (!row) return;
    [row layoutIfNeeded];
    UIView *add = SGRFindByIdentifier(row, @"Components.UI.AddToButton", &kAddKey);
    UIView *ban = SGRFindByIdentifier(row, @"feedback_headunit_right_ban_button_accessibility_identifier", &kBanKey);
    sg_addButton = [add isKindOfClass:UIControl.class] ? (UIControl *)add : nil;
    sg_banButton = [ban isKindOfClass:UIControl.class] ? (UIControl *)ban : nil;
    UIButton *more = SGRSystemMenuButtonIn(row, sg_spotifyMore, sg_leadItems, sg_playerItems, sg_kind);
    if (!more) return;
    if (sg_moreButton != more) {
        sg_moreButton = more;
        UIImageSymbolConfiguration *size = [UIImageSymbolConfiguration configurationWithPointSize:kMoreGlyphSize weight:UIImageSymbolWeightSemibold];
        [more setImage:[UIImage systemImageNamed:@"ellipsis" withConfiguration:size] forState:UIControlStateNormal];
        more.tintColor = SGRPrimary();
        SGLog(@"redesign player: the ⋯ beside the title, %@%@", !sg_addButton ? @"in place of no add button"
              : SGRStarAddOn() ? @"in the row's end after the add button's star" : @"in place of the add button",
              sg_banButton ? @" and Spotify's X" : @"");
    }
    // Star add button keeps the add button's slot as Spotify draws it, the star on Spotify's own button.
    UIView *slot = SGRStarAddOn() ? nil : slotIn(sg_addButton, row), *banSlot = slotIn(sg_banButton, row);
    if (slot) hideForMore(slot);
    if (banSlot) hideForMore(banSlot);
    // In the add button's slot, else the row's trailing one, PlayerTitle.x holding the row's arranged views in before it.
    CGRect frame;
    if (slot && !slot.hidden && slot.bounds.size.width >= 1) {
        frame = slot.frame;
    } else {
        BOOL rtl = row.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
        CGRect bounds = row.bounds;
        frame = CGRectMake(rtl ? CGRectGetMinX(bounds) : CGRectGetMaxX(bounds) - kMoreSlot, CGRectGetMidY(bounds) - kMoreSlot / 2, kMoreSlot, kMoreSlot);
    }
    if (!CGRectEqualToRect(more.frame, frame)) more.frame = frame;
}

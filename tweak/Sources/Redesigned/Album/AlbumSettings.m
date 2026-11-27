// The redesign's Albums page: Apple Music's animated covers on album pages, whether their downloads run in Low
// Data Mode, each track's play count, and what the redesign takes off the page. It leads with a preview of an
// album's page (Kit/SGRPagePreview.h) that follows them.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Redesigned/Kit/SGRPagePreview.h"
#import "Redesigned/Kit/SGRHeaderInfo.h"
#import "Album.h"
#import "AlbumNotes.h"
#import "SGRCoverBeside.h"

// The mock album's cover and its tracks, each with its plays.
static const NSUInteger kCover = 5;
static const NSUInteger kPlays[] = {12, 8, 5, 3};
static const NSUInteger kTracks = sizeof(kPlays) / sizeof(kPlays[0]);
// The album notes: lines of the short note.
static const NSUInteger kNoteLines = 3;

// The sections under an album's tracks, each with its switch and the tiles it is drawn with.
typedef struct {
    __unsafe_unretained NSString *key;   // a literal, never freed
    SGRPreviewTiles tiles;
} SGRAlbumSection;
static const SGRAlbumSection kSections[] = {
    {SGRKeyAlbumHideMoreBy, SGRPreviewTilesSquare},
    {SGRKeyAlbumHideVideos, SGRPreviewTilesWide},
    {SGRKeyAlbumHideConcerts, SGRPreviewTilesWide},
    {SGRKeyAlbumHideMerch, SGRPreviewTilesSquare},
    {SGRKeyAlbumHideYouMightLike, SGRPreviewTilesSquare},
    {SGRKeyAlbumHideOther, SGRPreviewTilesTall},
};
static const NSUInteger kSectionCount = sizeof(kSections) / sizeof(kSections[0]);

// An album as the redesign lays it out, from the top: the cover with its header and controls (a badge on the cover
// while an animated one is asked for), the notes under Play when they go there, the tracks with their plays in the
// row or their artist line when they show, the notes under the tracks when they go there, then the sections under
// the tracks while they are kept, each headed by its switch's name; over them the back button and the ⋯, and the
// track's ⋯ menu with its plays while they go there.
static SGRPagePreview *albumPreview(NSDictionary<NSString *, NSString *> *names) {
    SGRPagePreview *card = [[SGRPagePreview alloc] initWithLabel:SGL(@"settings.album.preview.a11y", @"Preview of an album")];
    SGRPreviewHeader *header = SGRPreviewAddHeader(card, kCover, @"livephoto", @"plus");
    UIView *notesUnderPlay = SGRPreviewAddParagraph(card, kNoteLines);
    SGRPreviewTracks *tracks = SGRPreviewAddTracks(card, kTracks, NO, 0);
    UIView *notesUnderTracks = SGRPreviewAddParagraph(card, kNoteLines);
    notesUnderPlay.accessibilityLabel = notesUnderTracks.accessibilityLabel = names[SGRKeyAlbumNotesPlace];
    NSMutableArray<UIView *> *sections = [NSMutableArray array];
    for (NSUInteger i = 0; i < kSectionCount; i++) {
        NSString *name = names[kSections[i].key];
        UIView *section = SGRPreviewAddShelf(card, name, kCover + 1 + i, kSections[i].tiles);
        section.accessibilityLabel = name;
        [sections addObject:section];
    }
    SGRPreviewAddTopBar(card);
    NSMutableArray<NSString *> *plays = [NSMutableArray array];
    for (NSUInteger i = 0; i < kTracks; i++) [plays addObject:SGRAlbumPlaysText(kPlays[i])];
    SGRPreviewMenu *menu = SGRPreviewAddMenu(card, @[@"chart.bar", @"plus.circle", @"square.and.arrow.up"], @[plays.firstObject]);
    menu.overlay.accessibilityLabel = names[SGRKeyAlbumPlayCountsPlace];

    card.state = ^id<NSObject> {
        NSMutableDictionary *state = [NSMutableDictionary dictionary];
        // As AlbumHeader.x asks: the switch, and Apple Music among the animated artwork's sources.
        state[SGRKeyAlbumMotion] = @(SGEnabled(SGRKeyAlbumMotion) && SGMotionAppleMusicOn());
        state[SGRKeyAlbumFullCover] = @(SGRPageFullCover(SGRKeyAlbumFullCover));
        state[SGRKeyAlbumNotesPlace] = @(SGRAlbumNotesWhere());
        state[SGRKeyAlbumPlayCountsPlace] = @(SGRAlbumPlayCountsWhere());
        state[SGRKeyAlbumPlayCountsSource] = @(SGRAlbumUsesSpotifyCounts());
        state[SGRKeyAlbumHideTrackArtists] = @(SGEnabled(SGRKeyAlbumHideTrackArtists));
        for (NSUInteger i = 0; i < kSectionCount; i++) state[kSections[i].key] = @(SGEnabled(kSections[i].key));
        return state;
    };
    card.apply = ^(SGRPagePreview *preview, NSDictionary *state) {
        BOOL motion = [state[SGRKeyAlbumMotion] boolValue];
        BOOL fullCover = [state[SGRKeyAlbumFullCover] boolValue];
        if (header.fullCover != fullCover) [preview revealPart:header.part];
        header.fullCover = fullCover;
        if (header.badge.alpha != motion) [preview revealPart:header.part];
        header.badge.alpha = motion;
        header.part.accessibilityLabel = motion ? names[SGRKeyAlbumMotion] : nil;
        SGRAlbumNotesPlace notes = [state[SGRKeyAlbumNotesPlace] integerValue];
        [preview setPart:notesUnderPlay shown:notes == SGRAlbumNotesUnderPlay];
        [preview setPart:notesUnderTracks shown:notes == SGRAlbumNotesUnderTracks];
        SGRAlbumPlayCountsPlace counts = [state[SGRKeyAlbumPlayCountsPlace] integerValue];
        BOOL artists = ![state[SGRKeyAlbumHideTrackArtists] boolValue];
        if ((tracks.trailing != nil) != (counts == SGRAlbumPlayCountsInRow) || tracks.showsArtists != artists) [preview revealPart:tracks.part];
        NSMutableArray *shownPlays = [NSMutableArray array];
        for (NSUInteger i = 0; i < kTracks; i++) [shownPlays addObject:[state[SGRKeyAlbumPlayCountsSource] boolValue]
            ? SGRAlbumSpotifyPlaysText(@(kPlays[i])) : SGRAlbumPlaysText(kPlays[i])];
        tracks.trailing = counts == SGRAlbumPlayCountsInRow ? shownPlays : nil;
        [menu setRow:0 word:shownPlays.firstObject];
        tracks.showsArtists = artists;
        tracks.part.accessibilityLabel = counts == SGRAlbumPlayCountsInRow ? names[SGRKeyAlbumPlayCountsPlace] : nil;
        [preview setPart:menu.overlay shown:counts == SGRAlbumPlayCountsInMenu];
        [sections enumerateObjectsUsingBlock:^(UIView *section, NSUInteger i, BOOL *stop) {
            [preview setPart:section shown:![state[kSections[i].key] boolValue]];
        }];
    };
    return card;
}

UIViewController *SGRAlbumSettingsPage(void) {
    SGModRow *cover = SGChoiceRow(SGL(@"settings.album.cover_layout", @"Cover layout"), nil, SGRKeyAlbumFullCover,
        @[SGL(@"settings.cover_layout.card", @"Card"), SGL(@"settings.cover_layout.full_screen", @"Full screen")],
        SGRPageFullCover(SGRKeyAlbumFullCover));
    // Only the Full screen cover has a picture to read for the page and to keep sharp under the title. In a section of
    // its own, so its footer goes with it.
    SGModRow *adaptive = SGOptionRow(SGL(@"settings.album.adaptive_cover.title", @"Picture-aware cover"), nil, SGRKeyAlbumAdaptiveCover);
    adaptive.visible = ^BOOL { return SGRPageFullCover(SGRKeyAlbumFullCover); };
    // Read on every pass of the header, so unlike the page's other switches it applies to the albums open.
    SGModRow *artistPicture = SGSwitchRow(SGL(@"settings.album.artist_picture.title", @"Artist picture"),
                                          SGL(@"settings.album.artist_picture.subtitle", @"Shows the artists' pictures beside their names."),
                                          SGRKeyAlbumArtistPicture);
    SGModRow *motion = SGSwitchRow(SGL(@"settings.album.animated_covers.title", @"Animated covers"), SGL(@"settings.album.animated_covers.subtitle", @"At the top of an album that has one, about 5 MB each"), SGRKeyAlbumMotion);
    SGModRow *notes = SGChoiceRow(SGL(@"settings.album.notes.title", @"Album notes"), nil, SGRKeyAlbumNotesPlace,
        @[SGL(@"settings.album.notes.under_play", @"Under Play"), SGL(@"settings.album.notes.under_tracks", @"Under tracks"),
          SGL(@"settings.album.notes.off", @"Off")], SGRAlbumNotesWhere());
    SGModRow *source = SGChoiceRow(SGL(@"settings.album.play_counts.source", @"Count source"), nil, SGRKeyAlbumPlayCountsSource,
        @[SGL(@"settings.album.play_counts.your_plays", @"Your plays"), SGL(@"settings.album.play_counts.spotify_plays", @"Spotify plays")],
        SGRAlbumUsesSpotifyCounts());
    source.visible = ^BOOL { return SGRAlbumPlayCountsWhere() != SGRAlbumPlayCountsOff; };
    SGModRow *plays = SGChoiceRow(SGL(@"settings.album.play_counts.title", @"Play counts"), nil, SGRKeyAlbumPlayCountsPlace,
                                  @[SGL(@"settings.album.play_counts.choice.off", @"Off"), SGL(@"settings.album.play_counts.choice.in_row", @"In the row"),
                                    SGL(@"settings.album.play_counts.choice.in_menu", @"In menu")], SGRAlbumPlayCountsWhere());
    SGModRow *trackArtists = SGSwitchRow(SGL(@"settings.album.hide_track_artists.title", @"Repeated track artists"), SGL(@"settings.album.hide_track_artists.subtitle", @"The artist under a track when it is the album's own"), SGRKeyAlbumHideTrackArtists);
    NSArray<SGModRow *> *underTracks = @[
        SGSwitchRow(SGL(@"settings.album.hide.more_by_artist.title", @"More by the artist"), nil, SGRKeyAlbumHideMoreBy),
        SGSwitchRow(SGL(@"settings.album.hide.related_videos.title", @"Related music videos"), nil, SGRKeyAlbumHideVideos),
        SGSwitchRow(SGL(@"settings.album.hide.concerts.title", @"Concerts"), nil, SGRKeyAlbumHideConcerts),
        SGSwitchRow(SGL(@"settings.album.hide.merch.title", @"Merch"), nil, SGRKeyAlbumHideMerch),
        SGSwitchRow(SGL(@"settings.album.hide.you_might_like.title", @"You might also like"), nil, SGRKeyAlbumHideYouMightLike),
        SGSwitchRow(SGL(@"settings.album.hide.everything_else.title", @"Everything else"), SGL(@"settings.album.hide.everything_else.subtitle", @"Any other section Spotify sends"), SGRKeyAlbumHideOther),
    ];
    // The card names what it shows by the rows' own titles, by their keys; a choice row keeps no key of its own.
    NSMutableDictionary<NSString *, NSString *> *names = [NSMutableDictionary dictionary];
    for (SGModRow *row in [@[motion, trackArtists] arrayByAddingObjectsFromArray:underTracks]) names[row.key] = row.title;
    names[SGRKeyAlbumNotesPlace] = notes.title;
    names[SGRKeyAlbumPlayCountsPlace] = plays.title;

    return SGRPagePreviewPage(SGL(@"settings.album.title", @"Albums"), albumPreview(names), SGRestartNote, @[
        SGSection(SGL(@"settings.album.cover.header", @"Cover"), @[cover]),
        SGNotedSection(nil, @[adaptive], SGL(@"settings.album.adaptive_cover.footer",
                                             @"Picks the page colour from the cover and keeps it sharp under the title.")),
        SGSection(nil, @[artistPicture]),
        SGNotedSection(SGL(@"settings.album.apple_music.header", @"Apple Music"), @[
            motion,
            notes,
        ], SGL(@"settings.album.apple_music.note", @"Only the album's name is sent to Apple Music. A cover stays still in Low Power Mode.")),
        SGNotedSection(SGL(@"settings.album.tracks.header", @"Tracks"), @[
            SGOptionRow(SGL(@"settings.album.track_numbers", @"Track numbers"), nil, SGRKeyAlbumTrackNumbers), plays, source],
                       SGL(@"settings.album.play_counts.sources_note", @"Your plays uses Listening stats on this phone, matched by album and track names. Spotify plays uses Spotify's track metadata and may be unavailable.")),
        SGSection(SGL(@"settings.album.hide_on_page.header", @"Hide on an album's page"), @[trackArtists]),
        SGNotedSection(SGL(@"settings.album.hide_under_tracks.header", @"Hide under an album's tracks"), underTracks,
                       SGL(@"settings.album.hide_under_tracks.note", @"Sections are told apart by their English names. With Spotify in another language, Everything else "
                           @"covers them all.")),
    ]);
}

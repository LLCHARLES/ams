#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Home.h"
#import "Native/Playlist/Playlist.h"
#import "Native/Artist/Artist.h"
#import "Native/Album/Album.h"

static SGModRow *choiceRow(NSString *title, NSString *subtitle, SGHomeChoice choice) {
    return SGChoiceRow(title, subtitle, SGHomeChoiceKey(choice), SGHomeChoiceNames(choice),
                       SGHomeChoiceDefault(choice));
}

UIViewController *SGHomeGradientPage(void) {
    return [[SGModPage alloc] initWithTitle:SGL(@"settings.home.gradient.title", @"Gradient")
                                      intro:SGL(@"settings.home.gradient.intro", @"Turning it on or off applies after you restart Spotify.")
                                   sections:@[
        SGSection(SGL(@"settings.home.gradient.title", @"Gradient"), @[
            SGOptionRow(SGL(@"settings.home.gradient.show.title", @"Show"), nil, SGKeyHomeGradient),
            choiceRow(SGL(@"settings.home.gradient.color.title", @"Color"), nil, SGHomeChoiceTint),
            choiceRow(SGL(@"settings.vibrations.strength.title", @"Strength"), nil, SGHomeChoiceStrength),
            choiceRow(SGL(@"settings.home.gradient.height.title", @"Height"), nil, SGHomeChoiceHeight),
        ]),
    ] footer:nil];
}

static UIViewController *libraryPage(void) {
    return [[SGModPage alloc] initWithTitle:SGL(@"settings.library.title", @"Library") intro:nil sections:@[
        SGSection(SGL(@"settings.library.title", @"Library"), @[
            SGFlagRow(SGL(@"settings.home.library.denser_rows.title", @"Denser rows"), @"ios-feature-yourlibaryx.denser_rows_enabled"),
            SGFlagRow(SGL(@"settings.home.library.sort_playlists_recent.title", @"Sort playlists by recently updated"), @"ios-feature-yourlibaryx.recently_updated_playlists_sort_enabled"),
            SGFlagRow(SGL(@"settings.home.library.sort_artists_recent.title", @"Sort artists by recently updated"), @"ios-feature-yourlibaryx.recently_updated_artists_sort_enabled"),
            SGFlagRow(SGL(@"settings.home.library.recents.title", @"Recents"), @"ios-feature-yourlibaryx.recents_enabled"),
            SGFlagRow(SGL(@"settings.home.library.recents_sort_order.title", @"Recents sort order"), @"ios-feature-yourlibaryx.recents_sort_order_enabled"),
            SGFlagRow(SGL(@"settings.home.library.library_settings.title", @"Library settings"), @"ios-feature-yourlibaryx.library_settings_enabled"),
            SGFlagRow(SGL(@"settings.home.library.library_pro.title", @"Library Pro"), @"ios-feature-yourlibaryx.your_library_pro_enabled"),
        ]),
    ] footer:nil];
}

UIViewController *SGHomeSettingsPage(void) {
    // The row reads its own state out, so the section says which color is set without being opened.
    SGModRow *gradient = SGPageRow(SGL(@"settings.home.gradient.title", @"Gradient"), ^UIViewController *{ return SGHomeGradientPage(); });
    gradient.value = ^NSString *{
        if (!SGFlag(SGKeyHomeGradient, NO)) return @"Off";
        return SGHomeChoiceNames(SGHomeChoiceTint)[(NSUInteger)SGHomeChoiceValue(SGHomeChoiceTint)];
    };

    NSArray<SGModSection *> *sections = @[
        SGSection(nil, @[
            SGWithSymbol(SGPageRow(SGL(@"settings.playlist.title", @"Playlists"), ^UIViewController *{ return SGPlaylistSettingsPage(); }), @"music.note.list"),
            SGWithSymbol(SGPageRow(SGL(@"settings.library.title", @"Library"), ^UIViewController *{ return libraryPage(); }), @"books.vertical"),
            SGWithSymbol(SGPageRow(SGL(@"settings.album.native.title", @"Album"), ^UIViewController *{ return SGAlbumSettingsPage(); }), @"square.stack"),
            SGWithSymbol(SGPageRow(SGL(@"settings.artist.native.title", @"Artist"), ^UIViewController *{ return SGArtistSettingsPage(); }), @"music.mic"),
        ]),
        SGSection(SGL(@"settings.home.title", @"Home"), @[
            SGWithSymbol(gradient, @"rectangle.tophalf.inset.filled"),
            SGFlagRow(SGL(@"settings.home.pull_to_refresh.title", @"Pull to refresh"), @"ios-home-evopage-impl.pull_to_refresh_enabled"),
        ]),
        SGSection(SGL(@"settings.home.hide.header", @"Hide on Home"), @[
            SGHideRow(SGL(@"settings.home.hide.pills.title", @"Filter pills"), nil, SGHideHomePills),
            SGHideRow(SGL(@"settings.home.hide.shortcuts.title", @"Shortcuts grid"), nil, SGHideHomeShortcuts),
            SGHideRow(SGL(@"settings.home.hide.promo.title", @"Promo cards"), nil, SGHideHomePromo),
            SGHideRow(SGL(@"settings.home.hide.previews.title", @"Preview cards"), nil, SGHideHomePreviews),
            SGHideRow(SGL(@"settings.home.hide.dj_card.title", @"DJ card"), nil, SGHideHomeDJ),
            SGKillRow(SGL(@"settings.home.hide.dj_button.title", @"DJ button"), @"ios-home-evopage-impl.idj_show_dj_button"),
            SGKillRow(SGL(@"settings.home.hide.dj_beta_badge.title", @"DJ beta badge"), @"ios-home-evopage-impl.dj_mdc_beta_badge_enabled"),
        ]),
    ];
    return [[SGModPage alloc] initWithTitle:SGL(@"settings.main.home_library.title", @"Home & Library") intro:nil sections:sections footer:nil];
}

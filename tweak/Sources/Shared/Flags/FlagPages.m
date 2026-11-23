// Labs: Spotify's flags for features it built and did not ship; every row forces one flag.
#import "Settings/SGModPage.h"
#import "Flags.h"

static int compareKey(const void *key, const void *def) {
    return strcmp(key, ((const SGFlagDef *)def)->key);
}

// Only the rows for flags this Spotify has: the table comes from the IPA the build is for, and a flag
// it lacks would force nothing. A section left empty goes too.
static NSArray<SGModSection *> *known(NSArray<SGModSection *> *sections) {
    NSMutableArray<SGModSection *> *kept = [NSMutableArray array];
    for (SGModSection *section in sections) {
        NSIndexSet *rows = [section.rows indexesOfObjectsPassingTest:^BOOL(SGModRow *row, NSUInteger i, BOOL *stop) {
            return !row.flag || bsearch(row.key.UTF8String, SGFlagTable, SGFlagCount, sizeof *SGFlagTable, compareKey);
        }];
        if (!rows.count) continue;
        section.rows = [section.rows objectsAtIndexes:rows];
        [kept addObject:section];
    }
    return kept;
}

static UIViewController *martiniPage(void) {
    return [[SGModPage alloc] initWithTitle:SGL(@"settings.labs.martini.title", @"AI Chat (Martini)") intro:SGRestartNote sections:known(@[
        SGSection(SGL(@"settings.home.on_home.header", @"On Home"), @[
            SGFlagRow(SGL(@"settings.labs.martini.entry_point.title", @"Chat entry point"), @"ios-home-evopage-impl.interactive_entrypoint_enabled"),
            SGFlagRow(SGL(@"settings.labs.martini.backend.title", @"Martini behind it"), @"ios-home-evopage-impl.interactive_entrypoint_martini_enabled"),
            SGFlagRow(SGL(@"settings.labs.martini.floating.title", @"Floating chat"), @"ios-home-evopage-impl.interactive_entrypoint_floating_chat_enabled"),
            SGFlagRow(SGL(@"settings.labs.martini.mic.title", @"Microphone"), @"ios-home-evopage-impl.interactive_entrypoint_mic_enabled"),
            SGFlagRow(SGL(@"settings.labs.martini.glowing_pill.title", @"Glowing pill"), @"ios-home-evopage-impl.interactive_entrypoint_pill_glow_enabled"),
        ]),
        SGSection(SGL(@"settings.labs.martini.chat_section.header", @"The chat"), @[
            SGFlagRow(SGL(@"settings.labs.martini.intent_pills.title", @"Intent pills"), @"ios-martini-floatingchat-impl.intent_pills_enabled"),
            SGFlagRow(SGL(@"settings.labs.martini.thinking_states.title", @"Thinking states"), @"ios-martini-floatingchat-impl.thinking_states_enabled"),
            SGFlagRow(SGL(@"settings.labs.martini.voice_recording.title", @"Voice recording"), @"ios-martini-floatingchat-impl.voice_recording_enabled"),
        ]),
        SGSection(SGL(@"settings.lyricslook.place.player", @"In the player"), @[
            SGFlagRow(SGL(@"settings.labs.martini.entry_point.title", @"Chat entry point"), @"ios-martini-npvcardprovider-impl.floating_chat_entry_point_enabled"),
            SGFlagRow(SGL(@"settings.labs.martini.agent_button.title", @"Agent button"), @"ios-martini-npvcardprovider-impl.npv_agent_button_enabled"),
        ]),
    ]) footer:nil];
}

UIViewController *SGLabsPage(void) {
    return [[SGModPage alloc] initWithTitle:SGL(@"settings.labs.title", @"Labs") intro:SGL(@"ui.unreleased.features.some.do.b88f04", @"Unreleased features; some do nothing on your version. Changes apply after you restart Spotify.") sections:known(@[
        SGSection(nil, @[
            SGWithSymbol(SGPageRow(SGL(@"settings.labs.martini.title", @"AI Chat (Martini)"), ^UIViewController *{ return martiniPage(); }), @"bubble.left.and.bubble.right"),
        ]),
        SGSection(SGL(@"settings.library.title", @"Library"), @[
            SGFlagRow(SGL(@"settings.labs.local_files.title", @"Local files from the Files app"), @"ios-feature-localfiles.documents_enabled"),
        ]),
        SGSection(SGL(@"settings.labs.widget.header", @"Home screen widget"), @[
            SGFlagRow(SGL(@"settings.labs.progress_bar.title", @"Progress bar"), @"ios-widgets-widgetremoteconfig-impl.progress_bar_enabled"),
        ]),
        SGNotedSection(SGL(@"settings.labs.sleep_timer.header", @"Sleep timer"), @[
            SGFlagRow(SGL(@"settings.labs.sleep_fade_out.title", @"Fade out"), @"ios-feature-sleeptimer.enable_fade_out"),
            SGFlagRow(SGL(@"settings.labs.sleep_one_minute.title", @"One minute option"), @"ios-feature-sleeptimer.enable_one_minute_option"),
            SGFlagRow(SGL(@"settings.labs.sleep_options_sheet.title", @"Options sheet"), @"ios-feature-sleeptimer.use_options_sheet"),
        ], @"Options sheet is always on in Redesigned UI."),
        SGSection(SGL(@"settings.home.dj.title", @"DJ"), @[
            SGFlagRow(SGL(@"settings.labs.dj_auto_mix.title", @"Auto mix"), @"ios-playlistcuration-mats.auto_mix_enabled_for_dj"),
            SGFlagRow(SGL(@"settings.labs.dj_auto_mix_menu.title", @"Auto mix in the context menu"), @"ios-playlistcuration-mats.dj_auto_mix_context_menu_enabled"),
        ]),
        SGSection(SGL(@"settings.player.title", @"Player"), @[
            SGFlagRow(SGL(@"settings.labs.snake_cover.title", @"Snake on the cover art"), @"ios-feature-cover-art-snake.enabled"),
        ]),
        SGSection(SGL(@"settings.labs.podcast_comments.header", @"Podcast comments"), @[
            SGFlagRow(SGL(@"settings.labs.comments_card.title", @"Comments card"), @"ios-feature-comments.enable_comments_card"),
            SGFlagRow(SGL(@"settings.labs.pinned_comments.title", @"Pinned comments"), @"ios-feature-comments.enable_pinned_comments"),
            SGFlagRow(SGL(@"settings.labs.multi_reactions.title", @"Several reactions"), @"ios-feature-comments.enable_multi_reactions"),
        ]),
    ]) footer:nil];
}

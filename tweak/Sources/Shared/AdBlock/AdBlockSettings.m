#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "AdBlock.h"
#import "Shared/Privacy/Privacy.h"
#import "Shared/SponsorBlock/SponsorBlock.h"
#import "Shared/Flags/Flags.h"

NSString *SGFakePremiumWarningText(void) {
    return SGL(@"settings.privacy.spoof_premium.warning", @"This is the part of EeveeSpotify Spotify's takedown went after, and it has not been tested here. It can end in a forced logout or worse for the account. A Premium account gains nothing from it.");
}

// Every switch here forces a flag Spotify ships on to off, so the titles name the blocking: on stops
// the thing, off is Spotify's own value. Hide ads and Hide upsells already force the first two
// sections off, which locks those rows.
static UIViewController *adFlagsPage(void) {
    NSMutableArray<SGModRow *> *upsells = [NSMutableArray array];
    NSString *shuffleKey = @"ios-feature-shuffletoggleupsell.is_enabled_pt2";
    for (NSUInteger i = 0; i < SGFlagCount; i++) {
        if (strcmp(SGFlagTable[i].key, shuffleKey.UTF8String) == 0) {
            [upsells addObject:SGKillRow(SGL(@"settings.privacy.hide_shuffle_upsell.title", @"Hide the shuffle toggle upsell"), shuffleKey)];
            break;
        }
    }
    [upsells addObject:SGKillRow(SGL(@"settings.privacy.hide_video_shuffle_upsell.title", @"Hide the shuffle upsell in the video player"), @"ios-feature-nowplaying-modes.video_first_shuffle_upsell_enabled")];
    return [[SGModPage alloc] initWithTitle:SGL(@"settings.privacy.ad_flags.title", @"Ad and upsell flags") intro:SGRestartNote sections:@[
        SGNotedSection(SGL(@"settings.privacy.ads.header", @"Ads"), @[
            SGKillRow(SGL(@"settings.privacy.block_open_ad.title", @"Block the ad when the app opens"), @"ios-feature-adonappopen.enabled"),
            SGKillRow(SGL(@"settings.privacy.block_cta_card.title", @"Block its CTA card"), @"ios-feature-adonappopen.cta_card_enabled"),
        ], SGL(@"settings.privacy.ads.footer", @"Locked while Hide ads is on.")),
        SGNotedSection(SGL(@"settings.privacy.upsells.header", @"Upsells"), upsells, SGL(@"settings.privacy.upsells.footer", @"Locked while Hide upsells is on.")),
        SGSection(SGL(@"settings.privacy.interventions.header", @"Reduce interventions"), @[
            SGFlagRow(SGL(@"settings.privacy.reduce_interventions.title", @"Reduce interventions"), @"ios-messaging-reduceinterventions-impl.enabled"),
        ]),
        SGSection(SGL(@"settings.privacy.tooltips.header", @"Tooltips"), @[
            SGKillRow(SGL(@"settings.privacy.hide_smart_shuffle_tip.title", @"Hide the smart shuffle helper"), @"ios-messaging-reduceinterventions-impl.enable_message_smart_shuffle_helper_tooltip"),
            SGKillRow(SGL(@"settings.privacy.hide_data_saver_tip.title", @"Hide the data saver tip"), @"ios-feature-nowplayingbar.data_saver_tooltip"),
            SGKillRow(SGL(@"settings.privacy.hide_suggestions_upsell.title", @"Hide the player suggestions upsell"), @"ios-messaging-reduceinterventions-impl.enable_message_reinvent_free_n_p_v_suggestions_upsell"),
            SGKillRow(SGL(@"settings.privacy.hide_ai_playlist_tip.title", @"Hide the AI playlist creation tip"), @"ios-messaging-reduceinterventions-impl.enable_message_your_library_ai_playlist_creation_tooltip"),
            SGKillRow(SGL(@"settings.privacy.hide_watch_feed_tip.title", @"Hide the watch feed explorer tip"), @"ios-messaging-reduceinterventions-impl.enable_message_watch_feed_entity_explorer_tooltip"),
            SGKillRow(SGL(@"settings.privacy.hide_account_switch_tip.title", @"Hide the account switching tip"), @"ios-messaging-reduceinterventions-impl.enable_message_account_switching_tooltip"),
            SGKillRow(SGL(@"settings.privacy.hide_concert_notif_tip.title", @"Hide the concert notifications tip"), @"ios-messaging-reduceinterventions-impl.enable_message_live_events_concert_notifications_tooltip"),
            SGKillRow(SGL(@"settings.privacy.hide_live_event_tip.title", @"Hide the live event tip"), @"ios-messaging-reduceinterventions-impl.enable_message_live_events_event_entity_safe_tooltip"),
            SGKillRow(SGL(@"settings.privacy.hide_venue_tip.title", @"Hide the live event venue tip"), @"ios-messaging-reduceinterventions-impl.enable_message_live_events_event_entity_venuename_header_tooltip"),
            SGKillRow(SGL(@"settings.privacy.hide_puffin_nudge.title", @"Hide the Puffin nudge"), @"ios-messaging-reduceinterventions-impl.enable_message_puffin_nudge_end_optimization"),
        ]),
    ] footer:nil];
}

// The switches first and what they have stopped last, so the counters bury no setting.
// The counters are stored under their English labels (AdBlock.m); only the rows read them translated.
static NSString *counterTitle(NSString *label) {
    NSDictionary<NSString *, NSString *> *titles = @{
        @"Ad services": SGL(@"settings.privacy.counter.ad_services", @"Ad services"),
        @"Upsell services": SGL(@"settings.privacy.counter.upsell_services", @"Upsell services"),
        @"Popups": SGL(@"settings.privacy.counter.popups", @"Popups"),
        @"Page components": SGL(@"settings.privacy.counter.page_components", @"Page components"),
        @"Feed sections": SGL(@"settings.privacy.counter.feed_sections", @"Feed sections"),
        @"Requests": SGL(@"settings.privacy.counter.requests", @"Requests"),
        @"Config rewrites": SGL(@"settings.privacy.counter.config_rewrites", @"Config rewrites"),
    };
    return titles[label] ?: label;
}

UIViewController *SGAdsSettingsPage(void) {
    NSMutableArray<SGModRow *> *counts = [NSMutableArray array];
    for (NSString *label in SGAdBlockLabels()) {
        [counts addObject:SGStatRow(counterTitle(label), ^NSString *{
            NSUInteger checked = SGAdBlockChecked(label);
            return checked == NSNotFound ? @(SGAdBlockCount(label)).stringValue
                : [NSString stringWithFormat:SGL(@"settings.privacy.count.format", @"%lu of %lu"), (unsigned long)SGAdBlockCount(label), (unsigned long)checked];
        })];
    }
    [counts addObject:SGStatRow(SGL(@"settings.privacy.total.title", @"Total"), ^NSString *{
        return @(SGAdBlockCount(nil)).stringValue;
    })];
    [counts addObject:SGActionRow(SGL(@"settings.privacy.reset_counters.action", @"Reset the counters"), nil, ^{ SGResetAdBlock(); })];

    SGModRow *fakePremium = SGOptionRow(SGL(@"settings.privacy.spoof_premium.title", @"Spoof Premium"), nil, SGKeyFakePremium);
    fakePremium.warning = SGFakePremiumWarning;

    NSMutableArray<SGModRow *> *ads = [NSMutableArray arrayWithObjects:
        SGWithSymbol(SGOptionRow(SGL(@"settings.privacy.hide_ads.title", @"Hide ads"), nil, SGKeyHideAds), @"speaker.slash"),
        SGWithSymbol(SGOptionRow(SGL(@"settings.privacy.hide_upsells.title", @"Hide upsells"), nil, SGKeyHideUpsells), @"hand.raised"), nil];
    [ads addObject:SGWithSymbol(SGPageRow(SGL(@"settings.privacy.ad_flags.row.title", @"Ad and upsell flags"), ^UIViewController *{ return adFlagsPage(); }), @"flag")];

    return [[SGModPage alloc] initWithTitle:SGL(@"settings.privacy.title", @"Premium, ads & privacy") intro:SGRestartNote sections:@[
        SGNotedSection(SGL(@"settings.privacy.ads_section.header", @"Ads"), ads, SGL(@"settings.privacy.ads.footer_note", @"Audio ads between songs need Spoof Premium.")),
        SGNotedSection(SGL(@"settings.privacy.premium.header", @"Premium"), @[
            SGWithSymbol(fakePremium, @"crown"),
        ], SGL(@"settings.privacy.premium.footer", @"Free accounts only.")),
        SGSponsorBlockSettingsSection(),
        SGPrivacySection(),
        SGNotedSection(SGL(@"settings.privacy.blocked_stats.header", @"Ads blocked so far"), counts,
                       SGL(@"settings.privacy.blocked_stats.footer", @"\"3 of 214\" is 3 stopped of 214 checked. 0 of 0 means Spotify never asked, so that part does nothing on this version.")),
        SGPrivacyCountersSection(),
    ] footer:nil];
}

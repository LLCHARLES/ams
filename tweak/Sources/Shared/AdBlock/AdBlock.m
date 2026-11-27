#import "Core/SGCore.h"
#import "Core/SGCounterStore.h"
#import "AdBlock.h"

#pragma mark - flags

// Both lists are EeveeSpotify's, kept to the flags this Spotify has.
static NSString *const adFlags[] = {
    @"ios-feature-adonappopen.enabled",
    @"ios-feature-adonappopen.cta_card_enabled",
    @"ios-nowplaying-scroll-impl.unified_leavebehind_npv_scroll_music_enabled",
    @"ios-nowplaying-scroll-impl.unified_leavebehind_npv_scroll_podcast_enabled",
    @"ios-feature-embeddedplaylist.use_unified_leavebehind_fetch",
    @"ios-adsnowplaying-embeddednpv-impl.foreground_enabled",
    @"ios-adsnowplaying-embeddednpv-impl.music_track_change_enabled",
    @"ios-adsnowplaying-embeddednpv-impl.enable_ads_on_podcast",
    @"ios-feature-adsbase.enable_ads_connect_state_observer",
    @"ios-feature-adsbase.enable_minimal_preroll_management",
    @"ios-feature-adsnowplayingui.embedded_npv_video_show_with_canvas",
    @"ios-feature-nowplaying.keep_fullscreen_during_video_ads",   // 9.1.94's
};

static NSString *const upsellFlags[] = {
    @"ios-feature-shuffletoggleupsell.is_enabled_pt2",
    @"ios-feature-shuffletoggleupsell.linear_upsell_new_style_experiment_enabled",
    @"ios-feature-shuffletoggleupsell.play_modes_upsell_new_style_experiment_enabled",
    @"ios-feature-nowplaying-modes.video_first_shuffle_upsell_enabled",
    @"ios-jam-freeusershuffleupsellsheetpage-impl.free_user_shuffle_upsell_sheet_enabled",
    @"ios-jam-freeuserskipupsellpage-impl.free_user_skip_upsell_sheet_enabled",
    @"ios-jam-freehostedjamsupsell-impl.free_hosted_jams_upsell_enabled",
    @"ios-reinventfree-contextualupsellpremiumpromo-impl.is_promo_cta_enabled",
    @"ios-reinventfree-controllerui-impl.enable_video_time_cap_upsell",
    @"ios-reinventfree-controllerui-impl.enable_video_time_cap_upsell_on_search",
    @"ios-reinventfree-timecappivot-impl.music_video_upsell_enabled",
    @"ios-settings-mediaqualitypageplugin-impl.is_gbb_upsell_enabled",
    @"ios-settings-mediaqualitypageplugin-impl.should_show_pigeon_upsell",
    @"ios-system-listeningparties.preview_ended_upsell_enabled",
    // Ours, checked against 9.1.78, 9.1.88 and 9.1.90.
    @"ios-feature-nowplaying-modes.video_first_skip_limit_upsell",
    @"ios-feature-premium-destination-badge.badge_enabled",
    @"ios-account-common.premium_plans_entry_point_row_enabled",
    @"ios-account-common.premium_referrals_settings_item_enabled",
    // 9.1.94's, all off by default.
    @"ios-reinventfree-contextualupsellpremiumpromo-impl.is_promo_checkout_link_enabled",
    @"ios-reinventfree-controllerui-impl.route_search_upsell_to_track_selected",
    @"ios-reinventfree-timecapupsellpage-impl.track_selected_artwork_enabled",
    @"ios-nowplaying-scroll-impl.membership_upsell_banner_in_about_card_enabled",
    @"ios-settings-rootpage-impl.use_compact_upsell",
    @"ios-premiumvalue.enable_premium_value",
};

// More of what Hide ads sets, by value: the ad features off, their guards and Skip buttons pinned on, and the
// ad cards' timings pushed past use. Each key, type and value was checked against 9.1.88's and 9.1.90's flag
// tables. canvas_skeleton_enabled and podcast_like_check_enabled are 9.1.90's. Enums are left alone: the table
// does not name their values.
static NSDictionary<NSString *, NSNumber *> *adValues(void) {
    static NSDictionary *values;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        values = @{
            @"ios-adsnowplaying-embeddednpv-impl.embedded_ad_html_element_enabled": @NO,
            @"ios-adsnowplaying-embeddednpv-impl.reopen_refresh_enabled": @NO,
            @"ios-adsnowplaying-embeddednpv-impl.canvas_skeleton_enabled": @NO,
            @"ios-feature-adonappopen.core_fetch_enabled": @NO,
            @"ios-home-evopage-impl.video_brand_ads_tagline_and_logo_enabled": @NO,
            @"ios-jam-adsdisclaimersheetpage-impl.ads_disclaimer_sheet_enabled": @NO,
            @"ios-reinventfree-adunlockeligibility-impl.ad_unlocked_on_demand_enabled": @NO,
            @"ios-adsplatform-elementimpl.display_ad_prevent_dismiss_on_iawb_present": @NO,
            @"ios-adsnowplaying-embeddednpv-impl.car_connection_check_enabled": @YES,
            @"ios-adsnowplaying-embeddednpv-impl.podcast_like_check_enabled": @YES,
            @"ios-adsnowplaying-embeddednpv-impl.prevent_duplicate_element_setup": @YES,
            @"ios-feature-adonappopen.skip_button_enabled": @YES,
            @"ios-feature-nowplayingbar.show_skip_button_during_skippable_ads": @YES,
            // The table's largest delay: a card waits nearly three hours to show.
            @"ios-adsnowplaying-embeddednpv-impl.render_delay_ms": @9999999,
            @"ios-adsnowplaying-embeddednpv-impl.canvas_render_delay_ms": @9999999,
            @"ios-feature-adonappopen.skippable_ad_delay_ms": @0,
            @"ios-feature-adonappopen.cached_ad_expiration_period_seconds": @0,
            @"ios-feature-adonappopen.background_refresh_frequency_seconds": @INT32_MAX,
        };
    });
    return values;
}

static BOOL listed(NSString *key, NSString *const list[], size_t count) {
    for (size_t i = 0; i < count; i++) {
        if ([key isEqualToString:list[i]]) return YES;
    }
    return NO;
}

// The switches that force flags off, one bit each, so the forcer below can read them once.
enum { kAds = 1, kVideos = 2, kUpsells = 4 };

static unsigned switchesNow(void) {
    return (SGHidden(SGKeyHideAds) ? kAds : 0) | (SGHidden(SGKeyHideSearchVideos) ? kVideos : 0)
         | (SGHidden(SGKeyHideUpsells) ? kUpsells : 0);
}

static NSNumber *forcedValue(NSString *key, unsigned on) {
    if (on & kAds) {
        if (listed(key, adFlags, sizeof(adFlags) / sizeof(adFlags[0]))) return @NO;
        NSNumber *value = adValues()[key];
        if (value) return value;
    }
    if ((on & kVideos) && [key isEqualToString:@"ios-feature-search.video_carousel_section_enabled"]) return @NO;
    return (on & kUpsells) && listed(key, upsellFlags, sizeof(upsellFlags) / sizeof(upsellFlags[0])) ? @NO : nil;
}

NSNumber *SGAdBlockForcedFlag(NSString *key) {
    return forcedValue(key, switchesNow());
}

// After an override from the All flags page, and locking the rows that would turn the same flag off.
// Spotify asks for every flag it has as it starts, so the running app's answer reads the switches once
// rather than four defaults lookups a flag (harness/launch); the rows read them as they are stored now.
__attribute__((constructor)) static void registerForcer(void) {
    SGRegisterFlagForcer(NO, ^id(NSString *key) {
        static unsigned atLaunch;
        static dispatch_once_t once;
        dispatch_once(&once, ^{ atLaunch = switchesNow(); });
        return atLaunch ? forcedValue(key, atLaunch) : nil;
    }, ^id(NSString *key) { return SGAdBlockForcedFlag(key); });
}

#pragma mark - counters

static NSString *const kCounts = @"spotifyglass.adblock.counts";
static NSString *const labels[] = {
    @"Ad services", @"Upsell services", @"Popups", @"Page components", @"Feed sections", @"Requests", @"Config rewrites",
};
// Made once per label: the hooks count on every request and page component.
static NSString *checkedKey(NSString *label) {
    static NSDictionary<NSString *, NSString *> *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary<NSString *, NSString *> *made = [NSMutableDictionary dictionary];
        for (NSString *each in SGAdBlockLabels()) made[each] = [each stringByAppendingString:@" checked"];
        keys = made;
    });
    return keys[label];
}

// The kinds whose hooks count what they look at. The services are stubs Spotify loads, with nothing to look at.
static NSString *const checkedLabels[] = {@"Popups", @"Page components", @"Feed sections", @"Requests", @"Config rewrites"};

static BOOL countsChecks(NSString *label) {
    return listed(label, checkedLabels, sizeof(checkedLabels) / sizeof(checkedLabels[0]));
}

static SGCounterStore *counter(void) {
    static SGCounterStore *store;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        store = [[SGCounterStore alloc] initWithKey:kCounts prepare:^BOOL(NSMutableDictionary *counts) {
        // Counts kept before checks were counted start again, so "stopped of checked" counts both from one moment.
            if (!counts.count || counts[checkedKey(@"Requests")]) return NO;
            [counts removeAllObjects];
            counts[checkedKey(@"Requests")] = @0;
            return YES;
        }];
    });
    return store;
}

void SGAdBlockCountOne(NSString *label) {
    [counter() increment:label];
}

void SGAdBlockSawOne(NSString *label) {
    [counter() increment:checkedKey(label)];
}

NSUInteger SGAdBlockChecked(NSString *label) {
    return countsChecks(label) ? counter().counts[checkedKey(label)].unsignedIntegerValue : NSNotFound;
}

// Spotify leaving the screen writes what was counted since the last write.
__attribute__((constructor)) static void saveChecksOnLeaving(void) {
    for (NSNotificationName name in @[UIApplicationWillResignActiveNotification, UIApplicationWillTerminateNotification])
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
            [counter() flush];
        }];
}

NSArray<NSString *> *SGAdBlockLabels(void) {
    return [NSArray arrayWithObjects:labels count:sizeof(labels) / sizeof(labels[0])];
}

NSUInteger SGAdBlockCount(NSString *label) {
    NSDictionary<NSString *, NSNumber *> *counts = counter().counts;
    if (label) return counts[label].unsignedIntegerValue;
    NSUInteger total = 0;
    for (NSString *each in SGAdBlockLabels()) total += counts[each].unsignedIntegerValue;
    return total;
}

void SGResetAdBlock(void) {
    [counter() reset];
}

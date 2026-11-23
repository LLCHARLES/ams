#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Privacy.h"

SGModSection *SGPrivacySection(void) {
    return SGSection(SGL(@"settings.privacy.section.header", @"Privacy"), @[
        SGWithSymbol(SGSwitchRow(SGL(@"settings.privacy.block_telemetry.title", @"Block telemetry"), SGL(@"settings.privacy.block_telemetry.subtitle", @"Spotify's own events still go out, since Recents is built from them"), SGKeyBlockTelemetry), @"antenna.radiowaves.left.and.right.slash"),
        SGWithSymbol(SGSwitchRow(SGL(@"settings.privacy.clean_links.title", @"Clean shared links"), SGL(@"settings.privacy.clean_links.subtitle", @"Takes the tracking (si, utm) off the links you copy or share"), SGKeyCleanLinks), @"link"),
    ]);
}

SGModSection *SGPrivacyCountersSection(void) {
    NSMutableArray<SGModRow *> *counts = [NSMutableArray array];
    for (NSString *label in SGBlockedLabels()) {
        [counts addObject:SGStatRow(label, ^NSString *{
            return @(SGBlockedCount(label)).stringValue;
        })];
    }
    [counts addObject:SGStatRow(SGL(@"settings.privacy.total.title", @"Total"), ^NSString *{
        return @(SGBlockedCount(nil)).stringValue;
    })];
    [counts addObject:SGActionRow(SGL(@"settings.privacy.reset_telemetry.action", @"Reset the telemetry counters"), nil, ^{ SGResetBlocked(); })];
    return SGSection(SGL(@"settings.privacy.telemetry_stats.header", @"Telemetry blocked so far"), counts);
}

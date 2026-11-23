#import <UIKit/UIKit.h>
#import "Core/SGPrefs.h"
#import "Core/SGLocalize.h"
#import "Settings/SGModPage.h"
#import "Shared/AdBlock/AdBlock.h"
#import "Shared/SponsorBlock/SponsorBlock.h"
#import "../harness-fail.h"

static NSArray<UIView *> *descendants(UIView *view) {
    NSMutableArray *views = [NSMutableArray arrayWithObject:view];
    for (NSUInteger i = 0; i < views.count; i++) [views addObjectsFromArray:((UIView *)views[i]).subviews];
    return views;
}

static void checkLayout(UIView *container) {
    NSMutableArray<NSValue *> *occupied = [NSMutableArray array];
    for (UIView *view in descendants(container)) {
        if (view.hidden || CGRectIsEmpty(view.bounds)) continue;
        if (!([view isKindOfClass:UILabel.class] && ((UILabel *)view).text.length) &&
            ![view isKindOfClass:UISwitch.class] && ![view isKindOfClass:UISlider.class]) continue;
        CGRect frame = [view convertRect:view.bounds toView:container];
        for (NSValue *other in occupied) HARNESS_CHECK(!CGRectIntersectsRect(frame, other.CGRectValue));
        [occupied addObject:[NSValue valueWithCGRect:frame]];
    }
    HARNESS_CHECK(occupied.count > 0);
}

static void renderPage(UIWindow *window, SGModPage *page) {
    window.rootViewController = [[UINavigationController alloc] initWithRootViewController:page];
    [window layoutIfNeeded];
    UITableView *table = page.tableView;
    for (NSInteger s = 0; s < table.numberOfSections; s++) {
        for (NSInteger r = 0; r < [table numberOfRowsInSection:s]; r++) {
            NSIndexPath *path = [NSIndexPath indexPathForRow:r inSection:s];
            [table scrollToRowAtIndexPath:path atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
            [table layoutIfNeeded];
            UITableViewCell *cell = [table cellForRowAtIndexPath:path];
            HARNESS_CHECK(cell != nil);
            checkLayout(cell);
        }
    }
}

void CheckSponsorBlockScreens(UIWindow *window) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    [store removeObjectForKey:SGKeySponsorBlock]; SGPrefsChanged();
    SGModRow *entry = SGSponsorBlockSettingsSection().rows.firstObject;
    HARNESS_CHECK(entry.page && entry.searchIdentifier);
    SGModPage *settings = (SGModPage *)entry.page();
    renderPage(window, settings);
    SGModRow *categoryLink = nil;
    for (SGModSection *section in settings.sections) for (SGModRow *row in section.rows)
        if ([row.searchIdentifier isEqual:@"page.sponsorblock.categories"]) categoryLink = row;
    HARNESS_CHECK(categoryLink.page != nil);
    SGModPage *categories = (SGModPage *)categoryLink.page();
    renderPage(window, categories);
    HARNESS_CHECK(categories.sections.firstObject.rows.count == 9);

    UIViewController *tour = [NSClassFromString(@"SGOnboardingController") new];
    window.rootViewController = tour;
    [window layoutIfNeeded];
    UIControl *card = nil;
    UIButton *finish = nil;
    for (UIView *v in descendants(tour.view)) {
        if ([v isKindOfClass:UIControl.class] && [v.accessibilityLabel isEqual:@"SponsorBlock"]) card = (UIControl *)v;
        if ([v isKindOfClass:UIButton.class] && [[((UIButton *)v) actionsForTarget:tour forControlEvent:UIControlEventTouchUpInside]
            containsObject:@"finish"]) finish = (UIButton *)v;
    }
    HARNESS_CHECK(card && finish && [card.accessibilityValue isEqual:SGL(@"common.off", @"Off")]);
    checkLayout(card);
    HARNESS_CHECK([finish.configuration.attributedTitle.string isEqual:SGL(@"settings.onboarding.start", @"Start listening")]);
    [card sendActionsForControlEvents:UIControlEventTouchUpInside];
    HARNESS_CHECK([card.accessibilityValue isEqual:SGL(@"common.on", @"On")] && !SGHidden(SGKeySponsorBlock));
    HARNESS_CHECK([finish.configuration.attributedTitle.string isEqual:SGL(@"settings.onboarding.restart", @"Restart Spotify")]);
    [NSNotificationCenter.defaultCenter addObserverForName:SGWillRestartNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        HARNESS_CHECK(SGHidden(SGKeySponsorBlock) && !SGHidden(SGKeyFakePremium));
        NSLog(@"PASS SponsorBlock settings layout and tour opt-in");
    }];
    [finish sendActionsForControlEvents:UIControlEventTouchUpInside];
}

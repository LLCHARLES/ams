// The Library page of Mod Settings (Redesigned/Library/LibrarySettings.m) as its builder makes it, on real UIKit: its
// preview card reads the filter chips while Compact library is off and the menu once it is on, the switch on the page
// stores the key, and the card grows with the text.
#import <UIKit/UIKit.h>
#import "../harness-fail.h"
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Redesigned/Kit/SGRPagePreview.h"
#import "Library.h"

static void settle(NSTimeInterval seconds) {
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

static SGRPagePreview *cardIn(UIView *view) {
    if ([view isKindOfClass:SGRPagePreview.class]) return (SGRPagePreview *)view;
    for (UIView *sub in view.subviews) {
        SGRPagePreview *card = cardIn(sub);
        if (card) return card;
    }
    return nil;
}

static UISwitch *switchBeside(UIView *root, NSString *title) {
    __block UISwitch *found = nil;
    for (UITableViewCell *cell in ((UITableView *)root).visibleCells) {
        __block BOOL named = NO;
        SGForEachView(cell, ^(UIView *view) {
            if ([view isKindOfClass:UILabel.class] && [((UILabel *)view).text isEqualToString:title]) named = YES;
        });
        if (!named) continue;
        SGForEachView(cell, ^(UIView *view) {
            if (!found && [view isKindOfClass:UISwitch.class]) found = (UISwitch *)view;
        });
    }
    return found;
}

static void expectReads(SGRPagePreview *card, BOOL compact, NSString *moment) {
    NSString *value = card.accessibilityValue;
    BOOL chips = [value containsString:@"Filter chips"], menu = [value containsString:@"Sort and view menu"];
    if (chips == compact || menu != compact) HARNESS_FAIL(@"%@: VoiceOver reads \"%@\"", moment, value);
    printf("PASS %s: the card reads \"%s\"\n", moment.UTF8String, value.UTF8String);
}

static UIView *partNamed(UIView *card, NSString *name) {
    __block UIView *found = nil;
    SGForEachView(card, ^(UIView *view) {
        if (!found && [view.accessibilityLabel isEqualToString:name]) found = view;
    });
    if (!found) HARNESS_FAIL(@"no part named %@ in the card", name);
    return found;
}

// The mock's title row in reading order from the leading edge -- the title, the menu's glyph, the avatar -- and the
// sort row's glyph before the view's, mirrored right to left (`rtl` on the launch line).
static void expectReadingOrder(SGRPagePreview *card) {
    BOOL rtl = card.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    if (rtl != [NSProcessInfo.processInfo.arguments containsObject:@"rtl"]) HARNESS_FAIL(@"the card reads %@", rtl ? @"right to left" : @"left to right");
    UIView *titlePart = partNamed(card, @"Your Library"), *menu = partNamed(card, @"Sort and view menu"), *sortPart = partNamed(card, @"Sort order and view");
    UIView *label = nil, *avatar = nil;
    for (UIView *sub in titlePart.subviews) {
        if ([sub isKindOfClass:UILabel.class]) label = sub;
        else avatar = sub;
    }
    NSArray<UIView *> *row = @[label, menu, avatar];
    NSArray<UIView *> *sortRow = @[sortPart.subviews.firstObject, sortPart.subviews.lastObject];
    for (NSArray<UIView *> *views in @[row, sortRow]) {
        for (NSUInteger i = 1; i < views.count; i++) {
            CGRect before = [views[i - 1] convertRect:views[i - 1].bounds toView:card], next = [views[i] convertRect:views[i].bounds toView:card];
            BOOL follows = rtl ? CGRectGetMaxX(next) <= CGRectGetMinX(before) + 0.5 : CGRectGetMinX(next) >= CGRectGetMaxX(before) - 0.5;
            if (!follows) HARNESS_FAIL(@"%@ %@ does not follow %@ %@ %@", views[i].class, NSStringFromCGRect(next), views[i - 1].class,
                                       NSStringFromCGRect(before), rtl ? @"right to left" : @"left to right");
        }
    }
    printf("PASS the card's title row and sort row read %s\n", rtl ? "right to left" : "left to right");
}

void SGRRunSettingsChecks(UIWindow *window) {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:
        SGRPagePreviewPage(@"Library", SGRLibraryPreview(), SGRestartNote, @[SGRLibrarySection()])];
    window.rootViewController = nav;
    [nav.view layoutIfNeeded];
    settle(0.5);
    UITableView *table = ((UITableViewController *)nav.topViewController).tableView;
    SGRPagePreview *card = cardIn(table.tableHeaderView);
    if (!card || card.bounds.size.height < 1) HARNESS_FAIL(@"no preview card on the Library page");
    expectReads(card, NO, @"off");

    UISwitch *toggle = switchBeside(table, @"Compact library");
    if (!toggle || toggle.on) HARNESS_FAIL(@"the Compact library switch %@", toggle ? @"is on by default" : @"is missing");
    toggle.on = YES;
    [toggle sendActionsForControlEvents:UIControlEventValueChanged];
    settle(1.0);
    if (![NSUserDefaults.standardUserDefaults boolForKey:SGRKeyLibraryHideChips]) HARNESS_FAIL(@"the switch did not store %@", SGRKeyLibraryHideChips);
    expectReads(card, YES, @"on");
    expectReadingOrder(card);

    CGFloat height = card.bounds.size.height;
    window.traitOverrides.preferredContentSizeCategory = UIContentSizeCategoryAccessibilityExtraLarge;
    settle(0.5);
    [nav.view layoutIfNeeded];
    settle(0.3);
    if (card.bounds.size.height <= height) HARNESS_FAIL(@"the card did not grow with the text (%.0f to %.0f)", height, card.bounds.size.height);
    printf("PASS the card grows with the text (%.0f to %.0f pt)\n", height, card.bounds.size.height);
    printf("PASS all settings\n");
    exit(0);
}

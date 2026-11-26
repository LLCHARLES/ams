#import <UIKit/UIKit.h>
#import "Core/SGCore.h"
#import "App/Pages.h"
#import "Settings/SGModPage.h"
#import "Shared/LyricsTranslation/LyricsTranslation.h"
#import "../harness-fail.h"

static UIView *promptView(UIView *root, Class type) {
    if ([root isKindOfClass:type]) return root;
    for (UIView *view in root.subviews) {
        UIView *found = promptView(view, type);
        if (found) return found;
    }
    return nil;
}
static SGModRow *promptRow(SGModPage *page, NSString *identifier) {
    for (SGModSection *section in page.sections)
        for (SGModRow *row in section.rows)
            if ([row.searchIdentifier isEqual:identifier]) return row;
    return nil;
}
static void promptShot(UIWindow *window, NSString *name) {
    [window layoutIfNeeded];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:window.bounds];
    NSData *data = [renderer PNGDataWithActions:^(UIGraphicsImageRendererContext *context) {
        [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES];
    }];
    NSURL *directory = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    HARNESS_CHECK([data writeToURL:[directory URLByAppendingPathComponent:name] atomically:YES]);
}
static void promptBar(UIViewController *editor, NSString *title) {
    UIBarButtonItem *button = nil;
    for (UIBarButtonItem *item in editor.navigationItem.rightBarButtonItems)
        if ([(item.accessibilityLabel ?: item.title) isEqual:title]) button = item;
    HARNESS_CHECK(button);
    HARNESS_CHECK(button.enabled);
    HARNESS_CHECK([UIApplication.sharedApplication sendAction:button.action to:button.target from:button forEvent:nil]);
}
static void promptAfterTransition(UIViewController *controller, void (^done)(void)) {
    id<UIViewControllerTransitionCoordinator> transition = controller.transitionCoordinator;
    if (transition) [transition animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) { done(); }];
    else dispatch_async(dispatch_get_main_queue(), done);
}
static NSIndexPath *promptPath(SGModPage *page, NSString *title) {
    for (NSInteger section = 0; section < page.tableView.numberOfSections; section++) {
        for (NSInteger row = 0; row < [page.tableView numberOfRowsInSection:section]; row++) {
            NSIndexPath *path = [NSIndexPath indexPathForRow:row inSection:section];
            UITableViewCell *cell = [page.tableView.dataSource tableView:page.tableView cellForRowAtIndexPath:path];
            UIListContentConfiguration *content = (id)cell.contentConfiguration;
            if ([content.text isEqual:title]) return path;
        }
    }
    HARNESS_FAIL(@"prompt row was not rendered");
}
static void promptValue(SGModPage *page, SGModRow *row, NSString *expected) {
    NSIndexPath *path = promptPath(page, row.title);
    [page.tableView scrollToRowAtIndexPath:path atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
    [page.tableView layoutIfNeeded];
    UITableViewCell *cell = [page.tableView cellForRowAtIndexPath:path];
    HARNESS_CHECK(cell);
    UILabel *value = (id)promptView(cell.accessoryView, UILabel.class);
    UIImageView *chevron = (id)promptView(cell.accessoryView, UIImageView.class);
    HARNESS_CHECK([value.text isEqual:expected] && chevron.image);
}
static void promptOpen(SGModRow *row, UINavigationController *host, void (^done)(UIViewController *, UITextView *)) {
    SGModPage *page = (id)host.topViewController;
    NSUInteger depth = host.viewControllers.count;
    [page.tableView.delegate tableView:page.tableView didSelectRowAtIndexPath:promptPath(page, row.title)];
    promptAfterTransition(host, ^{
        HARNESS_CHECK(host.viewControllers.count == depth + 1 && !host.presentedViewController);
        UIViewController *editor = host.topViewController;
        UITextView *text = (id)promptView(editor.view, UITextView.class);
        HARNESS_CHECK(text && text.accessibilityLabel.length && text.adjustsFontForContentSizeCategory);
        HARNESS_CHECK(editor.overrideUserInterfaceStyle == UIUserInterfaceStyleDark);
        HARNESS_CHECK([editor conformsToProtocol:NSProtocolFromString(@"SPTPageController")]);
        HARNESS_CHECK(!editor.navigationItem.hidesBackButton && !editor.navigationItem.leftBarButtonItem);
        HARNESS_CHECK(host.interactivePopGestureRecognizer.enabled);
        done(editor, text);
    });
}

static void promptFinish(SGModRow *row, SGModPage *page, UINavigationController *nav, BOOL korean) {
    promptOpen(row, nav, ^(UIViewController *last, UITextView *input) {
        input.text = [@"x" stringByPaddingToLength:4001 withString:@"x" startingAtIndex:0];
        [input.delegate textViewDidChange:input];
        HARNESS_CHECK(!last.navigationItem.rightBarButtonItem.enabled);
        UIButton *restore = (id)promptView(last.view, UIButton.class);
        [restore sendActionsForControlEvents:UIControlEventTouchUpInside];
        HARNESS_CHECK(last.navigationItem.rightBarButtonItem.enabled);
        __block id observer;
        observer = [NSNotificationCenter.defaultCenter addObserverForName:UIKeyboardDidShowNotification object:nil queue:nil usingBlock:^(NSNotification *notification) {
            [NSNotificationCenter.defaultCenter removeObserver:observer];
            dispatch_async(dispatch_get_main_queue(), ^{
                [last.view layoutIfNeeded];
                CGRect keyboard = [last.view convertRect:[notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue] fromView:nil];
                CGRect frame = [input convertRect:input.bounds toView:last.view];
                HARNESS_CHECK(CGRectGetMaxY(frame) <= CGRectGetMinY(keyboard) + 1);
                promptShot(nav.view.window, @"prompt-editor.png");
                [nav setOverrideTraitCollection:[UITraitCollection traitCollectionWithPreferredContentSizeCategory:UIContentSizeCategoryAccessibilityExtraExtraExtraLarge] forChildViewController:last];
                [last.view layoutIfNeeded];
                HARNESS_CHECK(input.window && input.bounds.size.height >= 160);
                HARNESS_CHECK(!input.hasAmbiguousLayout);
                promptBar(last, korean ? @"저장" : @"Save");
                promptAfterTransition(nav, ^{
                    HARNESS_CHECK(nav.topViewController == page);
                    promptValue(page, row, korean ? @"기본값" : @"Default");
                    HARNESS_CHECK(![NSUserDefaults.standardUserDefaults objectForKey:SGKeyLyricsTranslationPrompt]);
                    NSLog(@"[harness] prompt UI PASS: value plus chevron, push/pop, save refresh, back discard, back gesture enabled, protocol, limits, keyboard, Dynamic Type, dark mode, accessibility labels");
                    exit(0);
                });
            });
        }];
        HARNESS_CHECK([input becomeFirstResponder]);
    });
}

void SGCheckTranslationPromptUI(UINavigationController *nav) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        HARNESS_FAIL(@"prompt UI did not finish");
    });
    SGSetRedesignedUI(YES);
    HARNESS_CHECK(SGLyricsTranslationSetPrompt(@""));
    SGModPage *lyrics = (id)SGLyricsSettingsPage();
    SGModRow *translation = promptRow(lyrics, @"page.lyrics.translation");
    HARNESS_CHECK(translation.page);
    [nav pushViewController:lyrics animated:NO];
    SGModPage *page = (id)translation.page();
    [nav pushViewController:page animated:NO];
    SGModRow *row = promptRow(page, SGKeyLyricsTranslationPrompt);
    HARNESS_CHECK(row && (!row.visible || row.visible()));
    BOOL korean = [SGLanguage() isEqualToString:@"ko"];
    HARNESS_CHECK([row.title isEqual:korean ? @"번역 프롬프트" : @"Translation prompt"]);
    HARNESS_CHECK([row.value() isEqual:korean ? @"기본값" : @"Default"]);
    promptValue(page, row, korean ? @"기본값" : @"Default");
    promptShot(nav.view.window, @"prompt-row.png");
    promptOpen(row, nav, ^(UIViewController *editor, UITextView *text) {
        HARNESS_CHECK([text.text isEqual:SGLyricsTranslationDefaultPrompt()]);
        text.text = @"Use playful {language}.";
        [text.delegate textViewDidChange:text];
        promptBar(editor, korean ? @"저장" : @"Save");
        promptAfterTransition(nav, ^{
            HARNESS_CHECK(nav.topViewController == page);
            promptValue(page, row, korean ? @"수정됨" : @"Edited");
            promptOpen(row, nav, ^(UIViewController *edited, UITextView *field) {
                HARNESS_CHECK([field.text isEqual:@"Use playful {language}."]);
                // Restore edits the draft only: Back must preserve the saved prompt.
                UIButton *restore = (id)promptView(edited.view, UIButton.class);
                HARNESS_CHECK(restore);
                [restore sendActionsForControlEvents:UIControlEventTouchUpInside];
                HARNESS_CHECK([field.text isEqual:SGLyricsTranslationDefaultPrompt()]);
                HARNESS_CHECK([nav popViewControllerAnimated:YES] == edited);
                promptAfterTransition(nav, ^{
                    HARNESS_CHECK(nav.topViewController == page);
                    HARNESS_CHECK([SGLyricsTranslationPromptTemplate() isEqual:@"Use playful {language}."]);
                    promptValue(page, row, korean ? @"수정됨" : @"Edited");
                    promptFinish(row, page, nav, korean);
                });
            });
        });
    });
}

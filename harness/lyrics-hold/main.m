// Holding a line in the redesign's lyrics (Redesigned/Lyrics/SGRKaraokeView.m): the menu it opens, what Copy puts
// on the pasteboard, what Share says, VoiceOver's actions, and the menu's anchor and dismissal through the press,
// through a menu replacing another one, and through each way a line's view can go. The real view, with
// ../lyrics/stubs.m for the player.
//
// The press is reported to the view's own -held: one recognizer state at a time (Began, Changed, Ended), the edit menu
// interaction's presentation is recorded instead of shown, and the delegate's three answers (items, anchor, dismissal)
// are called with a configuration by hand: recognition itself (the long press against the page's tap and scroll),
// UIKit presenting the menu and the pasteboard, and a finger on the share sheet or the mic are the phone's, listed in
// README.md.
//
//     ./build.sh
//     xcrun simctl install <udid> build/LyricsHoldHarness.app
//     xcrun simctl launch --console <udid> com.vojta.lyricsholdharness -check 1
//
// -check 1 prints PASS and FAIL lines and exits with the number of failures.
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "Redesigned/Lyrics/SGRKaraokeView.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsMeanings/Meanings.h"
#import "../harness-fail.h"

extern NSString *SGHarnessPlayingTrack;

static int failures;

static void check(BOOL ok, NSString *what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", what.UTF8String);
    fflush(stdout);
    if (!ok) failures++;
}

static void after(double seconds, dispatch_block_t block) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

static SGKaraokeLine *sungLine(NSInteger start, NSString *text) {
    NSMutableArray<SGKaraokeWord *> *words = [NSMutableArray array];
    NSInteger at = start;
    for (NSString *piece in [text componentsSeparatedByString:@" "]) {
        SGKaraokeWord *word = [SGKaraokeWord new];
        word.text = piece;
        word.start = at;
        word.end = at + 450;
        at += 500;
        [words addObject:word];
    }
    SGKaraokeLine *made = [SGKaraokeLine new];
    made.words = words;
    made.start = start;
    made.end = at;
    return made;
}

// A press reported where it is asked for, in whatever state the check puts it in.
@interface SGHold : UILongPressGestureRecognizer
@property (nonatomic) CGPoint point;
@property (nonatomic) UIGestureRecognizerState forced;
@end

@implementation SGHold
- (UIGestureRecognizerState)state { return self.forced; }
- (CGPoint)locationInView:(UIView *)view { return [view convertPoint:self.point fromView:nil]; }
@end

// The press as the view's own recognizer reports it, one state at a time: Began opens the menu, and Changed and
// Ended follow on the same line. (The recognizer's own arbitration with the page's tap and scroll is a finger's
// work, done on the phone.)
static void hold(SGRKaraokeView *view, CGPoint inWindow, UIGestureRecognizerState state) {
    SGHold *press = [SGHold new];
    press.point = inWindow;
    press.forced = state;
    ((void (*)(id, SEL, id))objc_msgSend)(view, NSSelectorFromString(@"held:"), press);
}

static CGPoint middleOf(UIView *line) {
    return [line convertPoint:CGPointMake(CGRectGetMidX(line.bounds), CGRectGetMidY(line.bounds)) toView:nil];
}

static void pressLine(SGRKaraokeView *view, UIView *line) {
    hold(view, middleOf(line), UIGestureRecognizerStateBegan);
}

// The configuration the page last asked to present: the interaction's own -presentEditMenuWithConfiguration: is
// taken over here, since there is no UIKit presentation in this check, and the delegate is asked about it by hand.
static UIEditMenuConfiguration *sg_presented;
static UIEditMenuInteraction *sg_presenter;

static void recordPresented(id self, SEL _cmd, UIEditMenuConfiguration *configuration) {
    sg_presenter = self;
    sg_presented = configuration;
}

// The delegate's two answers the check asks for, for `configuration`: the menu's items, and the rectangle its arrow
// points at.
static UIMenu *menuFor(SGRKaraokeView *view, UIEditMenuConfiguration *configuration) {
    return ((UIMenu *(*)(id, SEL, id, id, id))objc_msgSend)(view,
        NSSelectorFromString(@"editMenuInteraction:menuForConfiguration:suggestedActions:"), nil, configuration, @[]);
}

static CGRect targetOf(SGRKaraokeView *view, UIEditMenuConfiguration *configuration) {
    return [(id<UIEditMenuInteractionDelegate>)view editMenuInteraction:sg_presenter
                                             targetRectForConfiguration:configuration];
}

// A menu going away, as UIKit tells the delegate it is.
static void dismissMenu(SGRKaraokeView *view, UIEditMenuConfiguration *configuration) {
    ((void (*)(id, SEL, id, id, id))objc_msgSend)(view,
        NSSelectorFromString(@"editMenuInteraction:willDismissMenuForConfiguration:animator:"), nil, configuration, nil);
}

// What the page still holds for the menu: whether a line is held at all, which only its own menu's dismissal or its
// view's going clears. The anchor alone cannot say, since a detached view's anchor is nothing too.
static BOOL holding(SGRKaraokeView *view) {
    return [view valueForKey:@"heldLine"] != nil;
}

static NSArray<NSString *> *titlesOf(UIMenu *menu) {
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    for (UIMenuElement *item in menu.children) [titles addObject:item.title];
    return titles;
}

static void tapAction(UIMenuElement *item) {
    if (![item isKindOfClass:UIAction.class]) return;
    ((UIActionHandler)[item valueForKey:@"handler"])((UIAction *)item);
}

static UIView *lineViewAt(SGRKaraokeView *view, NSInteger index) {
    return [view valueForKey:@"shown"][@(index)];
}

// The points a rectangle covers, as "x,y w×h", for the check's own lines.
static NSString *rectText(CGRect rect) {
    return CGRectIsNull(rect) ? @"nothing" : [NSString stringWithFormat:@"%.0f,%.0f %.0f×%.0f",
                                              rect.origin.x, rect.origin.y, rect.size.width, rect.size.height];
}

// The meaning Genius would have handed over for a line, set as askMeanings: does once it lands: the view's own
// dictionary, and each line's view marked with its line's, which files the VoiceOver actions.
static void giveMeanings(SGRKaraokeView *view, NSDictionary<NSNumber *, NSArray<SGLyricsMeaning *> *> *meanings) {
    [view setValue:meanings forKey:@"meanings"];
    NSDictionary<NSNumber *, UIView *> *shown = [view valueForKey:@"shown"];
    for (NSNumber *index in shown) {
        if (!meanings[index]) continue;
        ((void (*)(id, SEL, id))objc_msgSend)(shown[index], NSSelectorFromString(@"markMeaning:"), meanings[index]);
    }
}

static void runActionChecks(SGRKaraokeView *view, NSArray<SGKaraokeLine *> *lines);

static void runChecks(SGRKaraokeView *view) {
    NSArray<SGKaraokeLine *> *lines = [view valueForKey:@"lines"];
    // Lines: 0 a plain line, 1 the one with a meaning, 2 an empty line, 3 an instrumental break's mark, 4 another.
    if (lines.count != 5 || !lineViewAt(view, 0) || !lineViewAt(view, 1)) {
        check(NO, [NSString stringWithFormat:@"the view shows the song's five lines and makes their views (%lu)", (unsigned long)lines.count]);
        printf("%d failed\n", failures);
        fflush(stdout);
        HARNESS_FAIL(@"%d failed", failures);
    }
    SGLyricsMeaning *meaning = [SGLyricsMeaning new];
    meaning.fragment = SGKaraokeLineText(lines[1]);
    meaning.body = @"What the line means, as the harness has it.";
    meaning.author = SGLyricsMeaningByArtist;
    meaning.url = @"https://genius.com/";
    giveMeanings(view, @{@1: @[meaning]});
    UIView *plain = lineViewAt(view, 0), *meaningful = lineViewAt(view, 1);

    pressLine(view, plain);
    NSArray<NSString *> *titles = titlesOf(menuFor(view, sg_presented));
    check([titles isEqualToArray:@[@"Copy", @"Share", @"Share as Card"]],
          [NSString stringWithFormat:@"a line with no meaning offers Copy, Share and Share as Card (%@)", [titles componentsJoinedByString:@", "]]);

    // The anchor through the press's own life: Began opens it, Changed and Ended leave it where it was, and only the
    // menu's dismissal lets it go.
    UIEditMenuConfiguration *first = sg_presented;
    CGRect anchor = targetOf(view, first);
    hold(view, middleOf(plain), UIGestureRecognizerStateChanged);
    CGRect moved = targetOf(view, first);
    check(!CGRectIsNull(anchor) && CGRectEqualToRect(moved, anchor),
          [NSString stringWithFormat:@"a moved finger keeps the menu's anchor (%@ → %@)", rectText(anchor), rectText(moved)]);
    hold(view, middleOf(plain), UIGestureRecognizerStateEnded);
    CGRect released = targetOf(view, first);
    check(CGRectEqualToRect(released, anchor),
          [NSString stringWithFormat:@"and letting go keeps it too, until the menu goes (%@)", rectText(released)]);
    dismissMenu(view, first);
    check(CGRectIsNull(targetOf(view, first)), @"the menu dismissed, the line is let go");

    // A press on another line while the first menu is up: UIKit presents the new menu after telling the delegate the
    // old one is gone, and that dismissal is not the new line's to answer.
    pressLine(view, plain);
    UIEditMenuConfiguration *replaced = sg_presented;
    pressLine(view, meaningful);
    UIEditMenuConfiguration *replacement = sg_presented;
    dismissMenu(view, replaced);
    UIMenu *menu = menuFor(view, replacement);
    titles = titlesOf(menu);
    check(replacement != replaced && [titles isEqualToArray:@[@"Meaning", @"Copy", @"Share", @"Share as Card"]]
          && CGRectEqualToRect(targetOf(view, replacement), [meaningful convertRect:meaningful.bounds toView:view]),
          [NSString stringWithFormat:@"the menu replacing another keeps its line's items and anchor (%@, %@)",
           [titles componentsJoinedByString:@", "], rectText(targetOf(view, replacement))]);
    UIPasteboard.generalPasteboard.string = @"before";
    if (menu.children.count == 4) tapAction(menu.children[1]);
    check([UIPasteboard.generalPasteboard.string isEqualToString:SGKaraokeLineText(lines[1])],
          [NSString stringWithFormat:@"Copy puts the line and nothing else on the pasteboard (\"%@\")", UIPasteboard.generalPasteboard.string]);
    dismissMenu(view, replacement);
    check(!holding(view) && CGRectIsNull(targetOf(view, replacement)), @"and its own dismissal lets it go");

    // A menu left over from before answers for nothing: the line that replaced it is not its to offer or point at.
    pressLine(view, plain);
    UIEditMenuConfiguration *older = sg_presented;
    pressLine(view, meaningful);
    UIEditMenuConfiguration *current = sg_presented;
    check(older != current && menuFor(view, older).children.count == 0 && CGRectIsNull(targetOf(view, older)),
          @"a menu that has been replaced offers no items and no anchor of its own");
    dismissMenu(view, older);
    check(holding(view) && !CGRectIsNull(targetOf(view, current)),
          @"and its dismissal leaves the menu that replaced it alone");
    dismissMenu(view, current);

    // The views going away take the menu with them, on each of the three paths: a restyle (a translation arriving,
    // which measures off the main thread), a line scrolled out of sight during playback, and the lines dropped.
    pressLine(view, meaningful);
    UIEditMenuConfiguration *held = sg_presented;
    CGRect heldRect = targetOf(view, held);
    ((void (*)(id, SEL))objc_msgSend)(view, NSSelectorFromString(@"restyle"));
    __block void (^runRest)(void);
    after(1.0, ^{
        check(!CGRectIsNull(heldRect) && !holding(view) && CGRectIsNull(targetOf(view, held)),
              @"a restyle removes the line views, and the menu with them");
        UIView *again = lineViewAt(view, 1);
        if (again) {
            pressLine(view, again);
            UIEditMenuConfiguration *dropped = sg_presented;
            CGRect before = targetOf(view, dropped);
            ((void (*)(id, SEL))objc_msgSend)(view, NSSelectorFromString(@"dropLines"));
            check(!CGRectIsNull(before) && !holding(view) && CGRectIsNull(targetOf(view, dropped)),
                  @"and so does the song's lines being dropped");
        } else {
            printf("SKIP the restyled view has no line 1 to hold\n");
        }
        after(1.2, runRest);   // the lines come back on the next frames
    });
    // A line scrolled far off the page is let go of, and its menu with it. The page reads the offset off its
    // scroll's presentation layer, which follows a content offset on the next commit.
    runRest = ^{
        UIView *far = lineViewAt(view, 4);
        if (!far) {
            printf("SKIP there is no distant line view to scroll out of sight\n");
            runActionChecks(view, lines);
            return;
        }
        pressLine(view, far);
        UIEditMenuConfiguration *scrolled = sg_presented;
        CGRect before = targetOf(view, scrolled);
        UIScrollView *scroll = [view valueForKey:@"scroll"];
        [(id<UIScrollViewDelegate>)view scrollViewWillBeginDragging:scroll];
        scroll.contentSize = CGSizeMake(scroll.bounds.size.width, scroll.bounds.size.height * 10);   // five lines are short of a screen
        scroll.contentOffset = CGPointMake(0, scroll.bounds.size.height * 5);
        after(0.2, ^{
            [(id<UIScrollViewDelegate>)view scrollViewDidScroll:scroll];
            check(!CGRectIsNull(before) && !lineViewAt(view, 4) && !holding(view) && CGRectIsNull(targetOf(view, scrolled)),
                  [NSString stringWithFormat:@"a line let go of out of sight lets the menu go too (held %@, line 4 %@, anchor %@)",
                   rectText(before), lineViewAt(view, 4) ? @"still there" : @"gone", rectText(targetOf(view, scrolled))]);
            scroll.contentOffset = CGPointZero;
            scroll.contentSize = scroll.bounds.size;
            [view setValue:@NO forKey:@"browsing"];
            after(0.3, ^{ runActionChecks(view, lines); });
        });
    };
}

// The rest, which needs no press at all.
static void runActionChecks(SGRKaraokeView *view, NSArray<SGKaraokeLine *> *lines) {
    UIView *plain = lineViewAt(view, 0), *meaningful = lineViewAt(view, 1);
    if (!plain || !meaningful) {
        check(NO, @"the lines have views again after the restyle and the drop");
        printf("%d failed\n", failures);
        fflush(stdout);
        HARNESS_FAIL(@"%d failed", failures);
    }
    // The meanings come back with the views, as askMeanings: marks them.
    SGLyricsMeaning *meaning = [SGLyricsMeaning new];
    meaning.fragment = SGKaraokeLineText(lines[1]);
    meaning.body = @"What the line means, as the harness has it.";
    meaning.author = SGLyricsMeaningByArtist;
    meaning.url = @"https://genius.com/";
    giveMeanings(view, @{@1: @[meaning]});
    for (NSNumber *index in @[@2, @3]) {
        UIView *silent = lineViewAt(view, index.integerValue);
        if (!silent) continue;
        pressLine(view, silent);
        check(menuFor(view, sg_presented).children.count == 0,
              [NSString stringWithFormat:@"a line with nothing to say gets no menu (line %@: \"%@\")", index,
               SGKaraokeLineText(lines[index.integerValue])]);
    }
    UIView *box = [view valueForKey:@"extrasBox"];
    if (box && !box.hidden && box.superview) {
        UIView *line = lineViewAt(view, 0) ?: lineViewAt(view, 1);
        pressLine(view, line);   // a menu on a line first, so the press behind the button has one to take away
        UIEditMenuConfiguration *taken = sg_presented;
        hold(view, middleOf(box), UIGestureRecognizerStateBegan);
        check(menuFor(view, taken).children.count == 0 && CGRectIsNull(targetOf(view, taken)),
              @"a press on the lyrics' own button gets no menu of its own, and takes the last one away");
    } else {
        printf("SKIP the lyrics' own button is not in this render\n");
    }

    NSArray<NSString *> *actions = [[meaningful accessibilityCustomActions] valueForKey:@"name"];
    check([actions isEqualToArray:@[@"Meaning", @"Copy line", @"Share line", @"Share as card"]],
          [NSString stringWithFormat:@"VoiceOver's actions on a line with a meaning (%@)", [actions componentsJoinedByString:@", "]]);
    actions = [[plain accessibilityCustomActions] valueForKey:@"name"];
    check([actions isEqualToArray:@[@"Copy line", @"Share line", @"Share as card"]],
          [NSString stringWithFormat:@"and three on one without (%@)", [actions componentsJoinedByString:@", "]]);
    UIPasteboard.generalPasteboard.string = @"before";
    UIAccessibilityCustomAction *copy = plain.accessibilityCustomActions.firstObject;
    BOOL ran = copy.actionHandler && copy.actionHandler(copy);
    check(ran && [UIPasteboard.generalPasteboard.string isEqualToString:SGKaraokeLineText(lines[0])],
          [NSString stringWithFormat:@"Copy line copies it too (\"%@\")", UIPasteboard.generalPasteboard.string]);

    // What Share says, the three cases, off the real thing's own function.
    NSString *said = SGRLyricsShareText(@"a line", @"Title", @"Artist", @"spotify:track:abc123", YES);
    check([said isEqualToString:@"a line\n\u2014 Title \u00B7 Artist\nhttps://open.spotify.com/track/abc123"],
          [NSString stringWithFormat:@"Share says the line, then the song, then its link (%@)",
           [said stringByReplacingOccurrencesOfString:@"\n" withString:@" \u23CE "]]);
    said = SGRLyricsShareText(@"a line", @"Title", @"Artist", @"spotify:local:a:b:Title:200", YES);
    check([said isEqualToString:@"a line\n\u2014 Title \u00B7 Artist"], @"a local file's line shares no link");
    said = SGRLyricsShareText(@"a line", @"Title", @"Artist", @"spotify:track:abc123", NO);
    check([said isEqualToString:@"a line\n\u2014 Title \u00B7 Artist"], @"lyrics that are not the playing song's share no link");

    // The line the page seeks to for a tap, called as the view's own tap calls it. A finger's tap is the phone's.
    UIView *target = lineViewAt(view, 4) ?: lineViewAt(view, 0);
    if (target) {
        ((void (*)(id, SEL, id))objc_msgSend)(view, NSSelectorFromString(@"seekToLine:"), [target valueForKey:@"line"]);
        check([[view valueForKey:@"seekTo"] integerValue] > 0, @"the line a tap names still seeks to it");
    }

    printf("%d failed\n", failures);
    fflush(stdout);
    if (failures) HARNESS_FAIL(@"%d failed", failures);
    exit(0);
}

@interface SGHarnessDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation SGHarnessDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    NSUserDefaults *args = NSUserDefaults.standardUserDefaults;
    SGHarnessPlayingTrack = @"spotify:track:abc123";
    [args setObject:@"Title" forKey:@"title"];
    [args setObject:@"Artist" forKey:@"artist"];

    SGKaraokeLine *empty = [SGKaraokeLine new];
    empty.words = @[];
    empty.start = 6000;
    empty.end = 6500;
    SGKaraokeLine *meaningful = sungLine(3000, @"the line with a meaning");
    SGKaraokeLine *mark = sungLine(9000, @"\u266A");
    NSArray<SGKaraokeLine *> *lines = @[sungLine(1000, @"a plain line"), meaningful, empty, mark, sungLine(12000, @"and one more line")];
    SGKaraokeKeepLines(SGHarnessPlayingTrack, lines);
    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = UIColor.blackColor;
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.window.rootViewController = root;
    [self.window makeKeyAndVisible];
    SGRKaraokeView *view = [[SGRKaraokeView alloc] initWithFrame:root.view.bounds];
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [root.view addSubview:view];
    // The edit menu interaction would present through UIKit, which this check has none of: it records what the page
    // asked it to present instead, so the delegate can be asked about that configuration by hand.
    method_setImplementation(class_getInstanceMethod(UIEditMenuInteraction.class, @selector(presentEditMenuWithConfiguration:)),
                             (IMP)recordPresented);

    if ([args boolForKey:@"check"]) after(3, ^{ runChecks(view); });   // the lines are measured off the main thread
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(SGHarnessDelegate.class));
    }
}

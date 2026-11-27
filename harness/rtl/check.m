// The mod's hand-laid controls in either reading direction: launched left to right and then with the right-to-left
// launch arguments by check.sh, each expectation is the left-to-right one or its mirror.
//   the glowing switch's knob, on, at the trailing end, as UISwitch's (Settings/SGGlowSwitch.m)
//   a slider row's value at the trailing end and its title at the leading one (Settings/SGPageStyle.m)
//   a page row's value followed by its chevron, the chevron at the trailing end, and a row's color swatch before its
//   value, the swatch at the leading side (Settings/SGModPage.m)
//   Sing's card with its level column at the trailing side and play at the leading one (Shared/Sing/SGSingCard.m)
//   the mic's upright slider filled from the bottom whichever the direction (Redesigned/Lyrics/SGRSingButton.m)
//   a recap story bar filling from its leading end, and a tap going back only in the story's leading third
//   (Shared/ListeningStats/RecapStory.m)
//   a title too long for its line starting at the leading edge and gliding toward the trailing side
//   (Settings/SGMarquee.m)
#import <UIKit/UIKit.h>
#import "../reduce-motion-fixture.h"
#import "Settings/SGGlowSwitch.h"
#import "Settings/SGPageStyle.h"
#import "Settings/SGModPage.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/SGLastTrack.h"
#import "Shared/Sing/Sing.h"
#import "Redesigned/Lyrics/SGRSingButton.h"
#import "Settings/SGMarquee.h"
#import "Shared/ListeningStats/SGPlayLog.h"
#import "Shared/ListeningStats/SGRecap.h"
#import "../harness-fail.h"

@interface UIViewController (RecapStory)
- (instancetype)initWithRecap:(SGRecap *)recap;
- (void)tapped:(UITapGestureRecognizer *)tap;
@end

// A tap at a chosen point of the story, as UIKit would report it.
@interface SGFixedTap : UITapGestureRecognizer
@property (nonatomic) CGPoint point;
@end
@implementation SGFixedTap
- (CGPoint)locationInView:(UIView *)view { return self.point; }
@end

UIView *SGSingCardView(void);
UIColor *SGRAccentColor(void) { return nil; }

@implementation SGShownTrack
@end
SPTPlayerState *SGPlayerState(void) { return nil; }
id SGKaraokePlayer(void) { return nil; }
SGShownTrack *SGShownTrackNow(void) { return nil; }
BOOL SGSingReadLevels(float *vocals, float *rest, int count) { return NO; }

static BOOL rtl;

static void findViews(UIView *root, Class kind, NSMutableArray *found) {
    if ([root isKindOfClass:kind]) [found addObject:root];
    for (UIView *sub in root.subviews) findViews(sub, kind, found);
}

static void checkGlowSwitch(UIView *host) {
    SGGlowSwitch *glow = [SGGlowSwitch new];
    glow.on = YES;
    [host addSubview:glow];
    [glow layoutIfNeeded];
    UIView *knob = glow.subviews.firstObject;
    // The switch is 56 pt wide: on is the trailing half.
    CGFloat middle = CGRectGetMidX(knob.frame);
    if (rtl ? middle >= 28 : middle <= 28) HARNESS_FAIL(@"glowing switch on: knob centered at %.1f of 56", middle);
}

static void checkSliderText(UIView *host) {
    UILabel *title = [UILabel new], *value = [UILabel new];
    title.text = @"Darkening";
    value.text = @"35%";
    [host addSubview:title];
    [host addSubview:value];
    SGLayOutSliderText(title, value, nil, 16, 12, 268);
    CGRect t = title.frame, v = value.frame;
    BOOL placed = rtl ? CGRectGetMinX(v) == 16 && CGRectGetMaxX(t) == 284 : CGRectGetMaxX(v) == 284 && CGRectGetMinX(t) == 16;
    if (!placed || CGRectIntersectsRect(t, v)) HARNESS_FAIL(@"slider row: title %@, value %@", NSStringFromCGRect(t), NSStringFromCGRect(v));
}

// A row's value label and the one image beside it (its chevron or its swatch), in the cell's space.
static void valueAndImage(UIView *host, SGModRow *row, NSString *text, CGRect *value, CGRect *image) {
    SGModPage *page = [[SGModPage alloc] initWithTitle:@"Rows" intro:nil sections:@[SGSection(nil, @[row])] footer:nil];
    page.view.frame = host.bounds;
    [host addSubview:page.view];
    [page.tableView layoutIfNeeded];
    UITableViewCell *cell = [page.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    [cell layoutIfNeeded];
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    NSMutableArray<UIImageView *> *images = [NSMutableArray array];
    findViews(cell.accessoryView, UILabel.class, labels);
    findViews(cell.accessoryView, UIImageView.class, images);
    HARNESS_CHECK(labels.count == 1 && images.count == 1 && [labels[0].text isEqual:text]);
    *value = [labels[0] convertRect:labels[0].bounds toView:cell];
    *image = [images[0] convertRect:images[0].bounds toView:cell];
    [page.view removeFromSuperview];
}

static void checkValueRow(UIView *host) {
    SGModRow *row = SGPageRow(@"Lyrics sources", ^UIViewController *{ return [UIViewController new]; });
    row.value = ^NSString *{ return @"Word timing first"; };
    CGRect value, chevron;
    valueAndImage(host, row, @"Word timing first", &value, &chevron);
    BOOL ordered = rtl ? CGRectGetMaxX(chevron) <= CGRectGetMinX(value) : CGRectGetMaxX(value) <= CGRectGetMinX(chevron);
    if (!ordered) HARNESS_FAIL(@"value row: value %@, chevron %@", NSStringFromCGRect(value), NSStringFromCGRect(chevron));
}

static void checkSwatchRow(UIView *host) {
    SGModRow *row = SGStatActionRow(@"Accent color", nil, ^NSString *{ return @"#1ED760"; }, ^{});
    row.swatch = ^UIColor *{ return UIColor.greenColor; };
    CGRect value, swatch;
    valueAndImage(host, row, @"#1ED760", &value, &swatch);
    BOOL ordered = rtl ? CGRectGetMaxX(value) <= CGRectGetMinX(swatch) : CGRectGetMaxX(swatch) <= CGRectGetMinX(value);
    if (!ordered) HARNESS_FAIL(@"swatch row: swatch %@, value %@", NSStringFromCGRect(swatch), NSStringFromCGRect(value));
}

static void checkSingCard(UIView *host) {
    UIView *card = SGSingCardView();
    card.frame = (CGRect){CGPointZero, [card sizeThatFits:CGSizeMake(390, 0)]};
    [host addSubview:card];
    [card layoutIfNeeded];
    NSMutableArray *columns = [NSMutableArray array], *buttons = [NSMutableArray array];
    findViews(card, NSClassFromString(@"SGSingLevelColumn"), columns);
    findViews(card, UIButton.class, buttons);
    HARNESS_CHECK(columns.count == 1 && buttons.count == 1);
    CGFloat column = CGRectGetMidX([columns[0] convertRect:[columns[0] bounds] toView:card]);
    CGFloat play = CGRectGetMidX([buttons[0] convertRect:[buttons[0] bounds] toView:card]);
    if (rtl ? column >= play : column <= play) HARNESS_FAIL(@"Sing card: column at %.0f, play at %.0f", column, play);
}

// The panel's slider drawn on screen: its green fill measured from a render of the host. The panel is shown with an
// animation that the host may not have drawn yet (a slow simulator draws nothing in the first frames), so the render
// is taken again until the fill is there; only its place is the check.
static void measureMicSlider(UIView *host, SGRSingButton *mic, CFTimeInterval deadline, void (^then)(void)) {
    NSMutableArray<UISlider *> *sliders = [NSMutableArray array];
    findViews(mic, UISlider.class, sliders);
    HARNESS_CHECK(sliders.count == 1);
    UISlider *slider = sliders[0];
    {
        slider.minimumTrackTintColor = UIColor.greenColor;
        slider.maximumTrackTintColor = UIColor.redColor;
        [slider layoutIfNeeded];
        CGRect box = [slider convertRect:slider.bounds toView:host];
        UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithSize:host.bounds.size] imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [host drawViewHierarchyInRect:host.bounds afterScreenUpdates:YES];
        }];
        CGImageRef cg = image.CGImage;
        size_t width = CGImageGetWidth(cg), height = CGImageGetHeight(cg);
        NSMutableData *pixels = [NSMutableData dataWithLength:width * height * 4];
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGContextRef bitmap = CGBitmapContextCreate(pixels.mutableBytes, width, height, 8, width * 4, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
        CGContextDrawImage(bitmap, CGRectMake(0, 0, width, height), cg);
        CGContextRelease(bitmap);
        CGColorSpaceRelease(space);
        CGFloat scale = width / host.bounds.size.width;
        // Green rows of the track: the average height they are drawn at, in the slider's upright box.
        const uint8_t *p = pixels.bytes;
        double greenY = 0, greenCount = 0;
        for (size_t y = (size_t)(CGRectGetMinY(box) * scale); y < (size_t)(CGRectGetMaxY(box) * scale) && y < height; y++) {
            for (size_t x = (size_t)(CGRectGetMinX(box) * scale); x < (size_t)(CGRectGetMaxX(box) * scale) && x < width; x++) {
                const uint8_t *px = p + (y * width + x) * 4;
                if (px[1] > 150 && px[0] < 90 && px[2] < 90) { greenY += y; greenCount++; }
            }
        }
        if (greenCount == 0) {
            if (CACurrentMediaTime() >= deadline) HARNESS_FAIL(@"mic slider: no fill drawn in %@", NSStringFromCGRect(box));
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 20), dispatch_get_main_queue(), ^{
                measureMicSlider(host, mic, deadline, then);
            });
            return;
        }
        CGFloat middle = CGRectGetMidY(box) * scale;
        if (greenY / greenCount <= middle) HARNESS_FAIL(@"mic slider: the fill sits above the middle (%.0f over %.0f)", greenY / greenCount, middle);
        then();
    }
}

// The mic's slider at a fifth of its range: its accent fill is the run of track below the thumb.
static void checkMicSlider(UIView *host, void (^then)(void)) {
    SGSetSingLevel(0.4f);
    SGRSingButton *mic = [[SGRSingButton alloc] initWithFrame:CGRectMake(300, 400, 44, 44)];
    [host addSubview:mic];
    [mic layoutIfNeeded];
    [mic performSelector:@selector(showPanel)];
    CFTimeInterval deadline = CACurrentMediaTime() + 60;
    dispatch_async(dispatch_get_main_queue(), ^{ measureMicSlider(host, mic, deadline, then); });
}

static void checkRecapBar(UIView *host) {
    UIView *bar = [NSClassFromString(@"SGStorySegment") new];
    HARNESS_CHECK(bar != nil);
    bar.frame = CGRectMake(0, 0, 100, 3);
    [host addSubview:bar];
    [bar setValue:@0.25 forKey:@"progress"];
    [bar layoutIfNeeded];
    CGRect fill = bar.subviews.firstObject.frame;
    CGFloat start = rtl ? 75 : 0;
    if (CGRectGetMinX(fill) != start || CGRectGetWidth(fill) != 25) HARNESS_FAIL(@"recap bar at a quarter: fill %@", NSStringFromCGRect(fill));
}

// Forty days of one year, enough for a story of every card.
static SGRecap *recapOfLastYear(void) {
    NSCalendar *calendar = NSCalendar.currentCalendar;
    NSDateInterval *year = SGPeriodStep(SGStatsPeriodYear, NSDate.date, -1, calendar);
    NSArray<NSString *> *titles = @[@"Kyoto", @"Nobody", @"Be Sweet", @"Garden Song", @"Sunblind"];
    NSArray<NSString *> *artists = @[@"Phoebe Bridgers", @"Mitski", @"Japanese Breakfast", @"Phoebe Bridgers", @"Fleet Foxes"];
    NSMutableArray<SGPlay *> *plays = [NSMutableArray array];
    for (NSInteger day = 0; day < 40; day++) {
        NSDate *date = [calendar dateByAddingUnit:NSCalendarUnitDay value:60 + day * 3 toDate:year.startDate options:0];
        for (NSUInteger i = 0; i < 3; i++) {
            SGPlay *play = [SGPlay new];
            NSUInteger song = (NSUInteger)(day + (NSInteger)i) % titles.count;
            play.end = (int64_t)[calendar dateBySettingHour:20 minute:(NSInteger)i * 10 second:0 ofDate:date options:0].timeIntervalSince1970;
            play.ms = 210000;
            play.title = titles[song];
            play.artist = artists[song];
            play.album = @"";
            play.uri = @"";
            [plays addObject:play];
        }
    }
    return SGRecapBuild(plays, year.startDate, NSDate.date, calendar);
}

static void checkRecapTaps(UIView *host) {
    UIViewController *story = [[NSClassFromString(@"SGRecapStoryController") alloc] initWithRecap:recapOfLastYear()];
    story.view.frame = host.bounds;
    [host addSubview:story.view];
    [story.view layoutIfNeeded];
    HARNESS_CHECK([[story valueForKey:@"count"] unsignedIntegerValue] >= 3);
    CGFloat width = host.bounds.size.width, y = host.bounds.size.height / 2;
    // The middle and the trailing third move on; the leading third goes back.
    NSArray<NSNumber *> *taps = @[@(width / 2), @(rtl ? width * 0.1 : width * 0.9), @(rtl ? width * 0.9 : width * 0.1)];
    NSArray<NSNumber *> *cards = @[@1, @2, @1];
    for (NSUInteger i = 0; i < taps.count; i++) {
        SGFixedTap *tap = [SGFixedTap new];
        tap.point = CGPointMake(taps[i].doubleValue, y);
        [story tapped:tap];
        NSUInteger card = [[story valueForKey:@"index"] unsignedIntegerValue];
        if (card != cards[i].unsignedIntegerValue) HARNESS_FAIL(@"recap tap at x %.0f: card %lu, not %@", taps[i].doubleValue, (unsigned long)card, cards[i]);
    }
    [story.view removeFromSuperview];
}

static void checkMarquee(UIView *host) {
    harnessMotion = allowMotion;
    SGMarqueeLabel *title = [[SGMarqueeLabel alloc] initWithFrame:CGRectMake(20, 600, 100, 24)];
    title.text = @"And the voice should come out clean, every word of it";
    [host addSubview:title];
    [title layoutIfNeeded];
    UIView *text = title.subviews.firstObject;
    HARNESS_CHECK(text.bounds.size.width > 100);
    // At rest the text's start shows: its leading end against the line's leading edge.
    BOOL starts = rtl ? CGRectGetMaxX(text.frame) == 100 : CGRectGetMinX(text.frame) == 0;
    CAKeyframeAnimation *glide = nil;
    for (NSString *key in text.layer.animationKeys) {
        CAAnimation *animation = [text.layer animationForKey:key];
        if ([animation isKindOfClass:CAKeyframeAnimation.class]) glide = (CAKeyframeAnimation *)animation;
    }
    HARNESS_CHECK(glide != nil);
    CGFloat furthest = 0;
    for (NSNumber *value in glide.values) if (fabs(value.doubleValue) > fabs(furthest)) furthest = value.doubleValue;
    // It moves so its trailing part comes into view: rightward right to left.
    BOOL toward = rtl ? furthest > 0 : furthest < 0;
    if (!starts || !toward) HARNESS_FAIL(@"marquee: text at %@, glides %.0f", NSStringFromCGRect(text.frame), furthest);
    [title removeFromSuperview];
    harnessMotion = useHostMotion;
}

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@end
@implementation AppDelegate
@end

@interface RTLScene : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@property BOOL started;
@end

@implementation RTLScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController = [UIViewController new];
    self.window.rootViewController.view.backgroundColor = UIColor.blackColor;
    [self.window makeKeyAndVisible];
}
- (void)sceneDidBecomeActive:(UIScene *)scene {
    if (self.started) return;
    self.started = YES;
    rtl = [NSProcessInfo.processInfo.arguments containsObject:@"rtl"];
    // The launch arguments are what make the direction; a run that did not get it checks nothing.
    BOOL running = UIApplication.sharedApplication.userInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    if (running != rtl) HARNESS_FAIL(@"asked for %@, running %@", rtl ? @"rtl" : @"ltr", running ? @"rtl" : @"ltr");
    UIView *host = self.window.rootViewController.view;
    dispatch_async(dispatch_get_main_queue(), ^{
        checkGlowSwitch(host);
        checkSliderText(host);
        checkValueRow(host);
        checkSwatchRow(host);
        checkSingCard(host);
        checkRecapBar(host);
        checkRecapTaps(host);
        checkMarquee(host);
        checkMicSlider(host, ^{
            fprintf(stderr, "[harness] PASS %s\n", rtl ? "rtl" : "ltr");
            exit(0);
        });
    });
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        fputs("[harness] RTLCheck entered main\n", stderr);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 180 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            HARNESS_FAIL(@"did not complete scene activation and direction checks");
        });
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class));
    }
}

#import "Redesigned/Kit/SGRDownload.h"

extern void SGHarnessStartClock(double at, double rate, double pauseAt, double holdFor);


static void roundTwoChecks(UIWindow *window) {
    UIViewController *root = [UIViewController new];
    window.rootViewController = root;
    [window makeKeyAndVisible];
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 360, 300)];
    [root.view addSubview:card];
    UILabel *name = [UILabel new];
    name.text = @"Style";
    UIImageView *mark = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.circle.fill"]];
    [card addSubview:name];
    [card addSubview:mark];
    SGRKaraokeView *preview = [[SGRKaraokeView alloc] initWithSampleLines:@[sungLine(0, @"preview")] length:10000];
    [card addSubview:preview];
    ((void (*)(id, SEL, BOOL))objc_msgSend)(preview, NSSelectorFromString(@"setShowing:"), YES);
    check(name.alpha == 1 && mark.alpha == 1, @"showing a style preview preserves its name and selection mark");
    // Exercise the host's repeated synchronization independently of the initial show.
    name.alpha = mark.alpha = 1;
    [preview syncSiblings];
    mark.hidden = YES;
    mark.hidden = NO;
    check(name.alpha == 1 && mark.alpha == 1 && !mark.hidden,
          @"synchronizing a style preview preserves selectable siblings");
    [preview removeFromSuperview];

    SGRKaraokeView *player = [[SGRKaraokeView alloc] initWithFrame:CGRectZero];
    [card addSubview:player];
    ((void (*)(id, SEL, BOOL))objc_msgSend)(player, NSSelectorFromString(@"setShowing:"), YES);
    BOOL hidNative = name.alpha == 0 && mark.alpha == 0;
    ((void (*)(id, SEL, BOOL))objc_msgSend)(player, NSSelectorFromString(@"setShowing:"), NO);
    check(hidNative && name.alpha == 1 && mark.alpha == 1,
          @"ordinary lyrics still hide and restore the native siblings");

    SGHarnessPlayingTrack = @"seek-old";
    SGHarnessStartClock(0, 0, -1, 0);
    ((void (*)(id, SEL))objc_msgSend)(player, NSSelectorFromString(@"tick"));
    ((void (*)(id, SEL, NSInteger))objc_msgSend)(player, NSSelectorFromString(@"glideTo:"), 20000);
    double held = ((double (*)(id, SEL))objc_msgSend)(player, NSSelectorFromString(@"clockMs"));
    SGHarnessPlayingTrack = @"seek-new";
    ((void (*)(id, SEL))objc_msgSend)(player, NSSelectorFromString(@"tick"));
    double next = ((double (*)(id, SEL))objc_msgSend)(player, NSSelectorFromString(@"clockMs"));
    check(held == 20000 && next == 0, @"a new track starts at its position instead of inheriting a pending seek");
    [player removeFromSuperview];

    SGRDownloadGlyph *download = [[SGRDownloadGlyph alloc] initWithFrame:CGRectMake(0, 0, 24, 24)];
    [root.view addSubview:download];
    [download showState:SGRDownloadDownloading progress:0.5 animated:NO];
    extern void HarnessBeginGlyphClose(void), HarnessFinishGlyphClose(void);
    HarnessBeginGlyphClose();
    [download showState:SGRDownloadDownloaded progress:1 animated:YES];
    [download showState:SGRDownloadNone progress:0 animated:YES];
    // Run past the 220 ms ring-closing callback, then repeat the unchanged state as a layout would.
    HarnessFinishGlyphClose();
    [download showState:SGRDownloadNone progress:0 animated:YES];
    NSUInteger visible = 0;
    UIImage *shown = nil;
    for (UIView *child in download.subviews) {
        if (child.hidden || child.alpha == 0) continue;
        visible++;
        if ([child isKindOfClass:UIImageView.class]) shown = ((UIImageView *)child).image;
    }
    check(visible == 1 && shown != nil,
          @"cancelling a completed download during ring closing leaves only the idle symbol visible");
    [download removeFromSuperview];
}

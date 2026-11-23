// A mock of Spotify's playlist page under its own class names and accessibility identifiers, built from
// trees/clean/playlist/01.txt, so Redesigned/Playlist can be laid out and looked at on the Mac.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "../download-mock.h"
#import "Core/SGPrefs.h"
#import "Redesigned/Kit/SGRHeaderInfo.h"
#import "Redesigned/Kit/SGRActionRow.h"
#import "../harness-fail.h"
#import "../album/hero-veil-check.h"
#import "../album/beside-check.h"

// A button's glass is first in its subviews; its glyph is first when it has never made one.
static UIView *glassOf(UIView *button) {
    UIView *glass = button.subviews.firstObject;
    return [glass isKindOfClass:UIImageView.class] ? nil : glass;
}

// The pinned pair on `page`: download by its identifier, ⋯ the other mirror button the page holds.
static void pinnedOn(UIView *page, SGRMirrorButton **download, SGRMirrorButton **more) {
    *download = nil;
    *more = nil;
    for (UIView *v in page.subviews) {
        if (![v isKindOfClass:SGRMirrorButton.class]) continue;
        if ([v.accessibilityIdentifier isEqualToString:@"Retrine.Album.Download"]) *download = (id)v;
        else *more = (id)v;
    }
}

// The page's first frames, while the field holds it under its veil (SGRFieldHoldLimit) and a beat past: on every
// frame drawn the pinned ⋯ is never its glyph alone. Either its own glass shows, or download's capsule is under it
// and covers it, download right under ⋯ in the page so that nothing -- the veil -- is between the two. Read after
// each Core Animation commit. `freeze` stops the main thread for 4 s on the first frame under the veil, so that a
// screenshot catches it. The verdict is logged and kept for verifyMixActions.
static BOOL sg_holdChecked, sg_holdPassed;
static void watchPinnedHold(UIView *page, BOOL freeze) {
    __block NSUInteger frames = 0, veiled = 0, onCapsule = 0;
    __block BOOL failed = NO, frozen = !freeze, done = NO;
    __block CFTimeInterval start = 0;
    CFRunLoopObserverRef observer = CFRunLoopObserverCreateWithHandler(NULL, kCFRunLoopBeforeWaiting | kCFRunLoopExit, true, 2000001,
                                                                       ^(CFRunLoopObserverRef obs, CFRunLoopActivity activity) {
        if (done) return;
        SGRMirrorButton *download, *more;
        pinnedOn(page, &download, &more);
        if (!more || more.hidden || !more.window) return;
        if (!start) start = CACurrentMediaTime();
        UIView *veil = nil;
        for (UIView *v in page.subviews) if ([NSStringFromClass(v.class) isEqualToString:@"SGRFieldVeil"]) veil = v;
        if (!veil && CACurrentMediaTime() - start > 1) {
            done = YES;
            sg_holdChecked = YES;
            sg_holdPassed = !failed && veiled > 0;
            NSLog(@"[harness] %@ pinned hold: %lu frames, %lu under the veil, %lu with ⋯ on download's capsule; ⋯ %@",
                  sg_holdPassed ? @"PASS" : @"FAIL", (unsigned long)frames, (unsigned long)veiled, (unsigned long)onCapsule,
                  failed ? @"was drawn without glass" : @"never without glass");
            return;
        }
        frames++;
        if (veil) veiled++;
        // The veil itself: right under the pinned run (download, when the page has it, then ⋯), over everything else.
        if (veil && !failed) {
            NSUInteger v = [page.subviews indexOfObjectIdenticalTo:veil], lowest = [page.subviews indexOfObjectIdenticalTo:more];
            if (download) lowest = MIN(lowest, [page.subviews indexOfObjectIdenticalTo:download]);
            if (v + 1 != lowest) {
                failed = YES;
                NSLog(@"[harness] FAIL pinned hold: frame %lu, the veil at %lu is not right under the pinned buttons (lowest at %lu)",
                      (unsigned long)frames, (unsigned long)v, (unsigned long)lowest);
            }
        }
        UIView *own = glassOf(more);
        BOOL covered = own && !own.hidden;
        if (!covered && download && !download.hidden) {
            UIView *capsule = glassOf(download);
            NSUInteger d = [page.subviews indexOfObjectIdenticalTo:download], m = [page.subviews indexOfObjectIdenticalTo:more];
            CGRect shape = capsule ? [download convertRect:capsule.frame toView:page] : CGRectNull;
            covered = capsule && !capsule.hidden && d + 1 == m && CGRectContainsRect(CGRectInset(shape, -0.5, -0.5), more.frame);
            if (covered) onCapsule++;
        }
        if (!covered && !failed) {
            failed = YES;
            NSMutableArray *order = [NSMutableArray array];
            for (UIView *v in page.subviews) [order addObject:v == more ? @"more" : v == download ? @"download" : NSStringFromClass(v.class)];
            NSUInteger n = MIN(order.count, (NSUInteger)4);
            NSLog(@"[harness] FAIL pinned hold: frame %lu at %.0f ms, ⋯ drawn without glass; the page's top subviews %@", (unsigned long)frames,
                  (CACurrentMediaTime() - start) * 1000, [[order subarrayWithRange:NSMakeRange(order.count - n, n)] componentsJoinedByString:@" < "]);
        }
        if (!frozen && veil) {
            frozen = YES;
            // The veil's fade, already running in the harness, which reads its cover before the window shows, is
            // paused where it is, so the frame stays the one a held page draws while the main thread waits.
            CALayer *layer = veil.layer;
            layer.timeOffset = [layer convertTime:CACurrentMediaTime() fromLayer:nil];
            layer.speed = 0;
            [CATransaction flush];
            layer.speed = 1;
            layer.timeOffset = 0;
        }
    });
    CFRunLoopAddObserver(CFRunLoopGetMain(), observer, kCFRunLoopCommonModes);
    CFRelease(observer);
}

static void verifyDisabledDownload(SGRMirrorButton *mirror, UIControl *source, NSUInteger *fired);
static void verifyDisabledPlay(SGRPlayCapsule *play);

static void verifyMixActions(UIView *root, BOOL independent) {
    NSMutableArray *pending = [NSMutableArray arrayWithObject:root];
    SGRHeaderInfo *info = nil;
    while (pending.count) {
        UIView *view = pending.lastObject;
        [pending removeLastObject];
        if ([view isKindOfClass:SGRHeaderInfo.class]) { info = (id)view; break; }
        [pending addObjectsFromArray:view.subviews];
    }
    HARNESS_CHECK(info);
    SGRPlayCapsule *play = [info valueForKey:@"play"];
    SGRMirrorButton *trailing = [info valueForKey:@"trailing"];
    // Shuffle, Play and save or download, Play on the middle of the page, whichever row it is.
    HARNESS_CHECK(play.superview == info && fabs(CGRectGetMidX(play.frame) - info.bounds.size.width / 2) < 1);
    // The pinned download, shown only beside a save in the row, and the pinned ⋯: a button outside the header
    // that is its page's top subview.
    SGRMirrorButton *download = nil, *more = nil;
    [pending setArray:@[root]];
    while (pending.count) {
        UIView *view = pending.lastObject;
        [pending removeLastObject];
        if ([view.accessibilityIdentifier isEqualToString:@"Retrine.Album.Download"]) download = (id)view;
        else if ([view isKindOfClass:SGRMirrorButton.class] && view.superview.subviews.lastObject == view
                 && ![view isDescendantOfView:info]) more = (id)view;
        [pending addObjectsFromArray:view.subviews];
    }
    HARNESS_CHECK(more && !more.hidden);
    [more.superview layoutIfNeeded];
    // `rtl`: the page laid out right to left, where the pair is mirrored.
    BOOL rtl = [NSProcessInfo.processInfo.arguments containsObject:@"rtl"];
    UIView *page = more.superview;
    CGFloat W = page.bounds.size.width;
    NSLog(@"[harness] pinned frames %@: download %@, more %@, capsule %@, more's glass %@", rtl ? @"rtl" : @"ltr",
          download && !download.hidden ? NSStringFromCGRect(download.frame) : @"none", NSStringFromCGRect(more.frame),
          download && !download.hidden && glassOf(download) && !glassOf(download).hidden ? NSStringFromCGRect([download convertRect:glassOf(download).frame toView:page]) : @"none",
          glassOf(more) && !glassOf(more).hidden ? NSStringFromCGRect([more convertRect:glassOf(more).frame toView:page]) : @"none");
    HARNESS_CHECK((page.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft) == rtl);
    HARNESS_CHECK(sg_holdChecked && sg_holdPassed);
    // ⋯ 16pt in from the page's right edge, or from its left one right to left.
    HARNESS_CHECK(rtl ? fabs(CGRectGetMinX(more.frame) - 16) < 0.5 : fabs(CGRectGetMaxX(more.frame) - (W - 16)) < 0.5);
    if (independent) {
        HARNESS_CHECK(trailing.source && !trailing.hidden && download.source && !download.hidden && download.source != trailing.source);
        // Download and ⋯ one glass capsule: adjacent, level, one 88x44 shape under both carried by download,
        // ⋯ drawing none, ⋯ outermost; right to left the left-to-right capsule reflected across the page.
        HARNESS_CHECK(download.superview == page && [page.subviews indexOfObject:download] < page.subviews.count - 1);
        HARNESS_CHECK(fabs(rtl ? CGRectGetMinX(download.frame) - CGRectGetMaxX(more.frame) : CGRectGetMinX(more.frame) - CGRectGetMaxX(download.frame)) < 0.5);
        HARNESS_CHECK(fabs(CGRectGetMinY(more.frame) - CGRectGetMinY(download.frame)) < 0.5);
        HARNESS_CHECK(fabs(more.frame.size.height - download.frame.size.height) < 0.5);
        UIView *capsule = glassOf(download);
        HARNESS_CHECK(capsule && !capsule.hidden && (!glassOf(more) || glassOf(more).hidden));
        CGRect shape = [download convertRect:capsule.frame toView:page];
        HARNESS_CHECK(fabs(shape.size.width - 88) < 0.5 && fabs(shape.size.height - 44) < 0.5);
        HARNESS_CHECK(fabs(CGRectGetMinX(shape) - CGRectGetMinX(rtl ? more.frame : download.frame)) < 0.5);
        HARNESS_CHECK(fabs(CGRectGetMaxX(shape) - CGRectGetMaxX(rtl ? download.frame : more.frame)) < 0.5 && fabs(CGRectGetMinY(shape) - CGRectGetMinY(more.frame)) < 0.5);
        CGRect ltr = CGRectMake(W - 16 - 88, CGRectGetMinY(more.frame), 88, 44);
        CGFloat expected = rtl ? W - CGRectGetMaxX(ltr) : ltr.origin.x;
        HARNESS_CHECK(fabs(shape.origin.x - expected) < 0.5);
        HARNESS_CHECK(capsule.layer.cornerRadius == 0 || fabs(capsule.layer.cornerRadius - 22) < 0.5);
        NSLog(@"[harness] PASS pinned capsule %@: 88x44 at %@, 16pt in from the %@ edge%@", rtl ? @"rtl" : @"ltr",
              NSStringFromCGRect(shape), rtl ? @"left" : @"right", rtl ? @", the left-to-right frame mirrored" : @"");
        UIControl *source = (id)download.source;
        __block NSUInteger fired = 0;
        [source addAction:[UIAction actionWithHandler:^(UIAction *action) { fired++; }]
            forControlEvents:UIControlEventTouchUpInside];
        [download sendActionsForControlEvents:UIControlEventTouchUpInside];
        HARNESS_CHECK(fired == 1);
        verifyDisabledDownload(download, source, &fired);
    } else {
        // No download pinned: ⋯ alone, its own 44pt circle.
        HARNESS_CHECK(!download || download.hidden);
        UIView *circle = glassOf(more);
        HARNESS_CHECK(circle && !circle.hidden && fabs(circle.bounds.size.width - 44) < 0.5 && fabs(circle.bounds.size.height - 44) < 0.5);
        HARNESS_CHECK(CGPointEqualToPoint(circle.center, CGPointMake(CGRectGetMidX(more.bounds), CGRectGetMidY(more.bounds))));
    }
    verifyDisabledPlay(play);
    NSDictionary *result = @{@"passed": @YES, @"independent_actions": @(independent), @"native_action_and_layout_verified": @YES};
    NSString *path = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject
        stringByAppendingPathComponent:@"playlist-actions-verification.json"];
    [[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil]
        writeToFile:path atomically:YES];
    NSLog(@"[harness] PASS %@ action row", independent ? @"independent" : @"centered");
}

#pragma mark - Spotify's classes, by name

@interface _TtC35ListUXPlatform_FreeTierPlaylistImpl17FTPViewController : UIViewController
- (void)sgr_creatorFired;
- (void)sgr_pillFired:(UIView *)pill;
@end
@implementation _TtC35ListUXPlatform_FreeTierPlaylistImpl17FTPViewController
- (void)sgr_creatorFired { NSLog(@"[harness] the creator line opened the playlist's owner"); }
- (void)sgr_pillFired:(UIView *)pill { NSLog(@"[harness] the sheet fired Spotify's %@ pill", pill.accessibilityLabel); }
@end

@interface _TtC35ListUXPlatform_FreeTierPlaylistImpl32FTPTouchCancellingCollectionView : UIScrollView @end
@implementation _TtC35ListUXPlatform_FreeTierPlaylistImpl32FTPTouchCancellingCollectionView @end

// The page's view model, as the device showed it (2026-09-18): the header controller's defaultHeaderViewModel.
// `other` on the launch line makes it someone else's playlist, `liked` Liked Songs.
@interface MockViewModel : NSObject
@property (nonatomic, copy) NSString *playlistName, *playlistDescription, *formatListType;
@property (nonatomic) BOOL isOwnedBySelf;
@end
@implementation MockViewModel @end

@interface MockHeaderController : NSObject
@property (nonatomic, strong) MockViewModel *defaultHeaderViewModel;
@end
@implementation MockHeaderController @end

@interface SPTFreeTierPlaylistEncoreHeaderViewController : UIViewController
@property (nonatomic, strong) MockHeaderController *headerController;
- (void)entityHeaderViewController:(id)controller didUpdateVisibleRect:(CGRect)rect;
@end
@implementation SPTFreeTierPlaylistEncoreHeaderViewController
- (MockHeaderController *)headerController {
    if (!_headerController) {
        NSArray *args = NSProcessInfo.processInfo.arguments;
        MockViewModel *model = [MockViewModel new];
        if ([args containsObject:@"liked"]) {
            model.playlistName = @"Liked Songs";
            model.formatListType = @"liked-songs";
        } else if ([args containsObject:@"mix"]) {
            model.playlistName = @"Indie Rock Mix";
        } else if ([args containsObject:@"other"]) {
            model.playlistName = @"Barre Beats";
            model.playlistDescription = @"All music for beat-driven barre classes. Some cool-downs too! I&#x27;m always adding to the list";
            if ([args containsObject:@"cover-beside"])
                model.playlistDescription = @"All music for beat-driven barre classes, with gentle warm-ups and slow cool-downs. "
                    @"A collection of favourite songs for moving together, finding your rhythm and taking a little time for yourself.";
        } else {
            model.playlistName = @"crap.";
            model.isOwnedBySelf = YES;
        }
        _headerController = [MockHeaderController new];
        _headerController.defaultHeaderViewModel = model;
    }
    return _headerController;
}
// Spotify's own is what reports a scroll to the header; here it only gives the hook something to run after.
- (void)entityHeaderViewController:(id)controller didUpdateVisibleRect:(CGRect)rect {}
// Spotify's runs when the page's model changes (a save); here it only gives PlaylistHeader.x's hook a method.
- (void)update {}
@end

@interface _TtC28EncoreConsumerMobile_BaseKit19HeaderContentLayout : UIView @end
@implementation _TtC28EncoreConsumerMobile_BaseKit19HeaderContentLayout @end

// What a mix Spotify makes gets instead of the cover square (trees/continuous/4.txt:1066).
@interface _TtC28EncoreConsumerMobile_BaseKit26HeaderFullbleedCentralView : UIView @end
@implementation _TtC28EncoreConsumerMobile_BaseKit26HeaderFullbleedCentralView @end

@interface _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView : UIView @end
@implementation _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView @end

@interface _TtC19LegacyUI_ECMCoreKit13GradientView : UIView @end
@implementation _TtC19LegacyUI_ECMCoreKit13GradientView @end

@interface _TtC44PlaylistCuration_ExpandableTextElementKit18ExpandableTextView : UITextView @end
@implementation _TtC44PlaylistCuration_ExpandableTextElementKit18ExpandableTextView @end

@interface _TtCE13Encore_FaceKitO16EncoreFoundation6Encore12FacepileView : UIView @end
@implementation _TtCE13Encore_FaceKitO16EncoreFoundation6Encore12FacepileView @end

@interface _TtC28EncoreConsumerMobile_BaseKit14PlayButtonView : UIView @end
@implementation _TtC28EncoreConsumerMobile_BaseKit14PlayButtonView @end

@interface _TtC35ListUXPlatform_FreeTierPlaylistImpl25ElementCollectionViewCell : UICollectionViewCell @end
@implementation _TtC35ListUXPlatform_FreeTierPlaylistImpl25ElementCollectionViewCell @end

@interface _TtGC13Element_UIKit11ElementViewT_P_P__ : UIView @end
@implementation _TtGC13Element_UIKit11ElementViewT_P_P__ @end

// What the element framework wraps a cell's content in, and what the device's tree shows between the
// playlist's Refresh cell and the black it paints (trees/continuous/1.txt:1919). It is a cell of its own,
// the full width of the one around it, so a clear that stops at the first nested cell stops before the paint.
@interface MockElementContentView : UICollectionViewCell @end
@implementation MockElementContentView @end

// A card inside a carousel: a cell too, but its own width, and its own color to keep.
@interface MockCardCell : UICollectionViewCell @end
@implementation MockCardCell @end

// Encore's glyph view and the icon it is built from, which answers its own name: how the curation row tells
// Sort from Edit without reading the word on it.
@interface MockEncoreIcon : NSObject
@property (nonatomic, copy) NSString *name;
@end
@implementation MockEncoreIcon @end

@interface SPTEncoreIconView : UIView {
@public
    id icon;
}
@end
@implementation SPTEncoreIconView @end

@interface _TtC19LegacyUI_ECMCoreKit10ScrollView : UIScrollView @end
@implementation _TtC19LegacyUI_ECMCoreKit10ScrollView @end

// The header view the find-on-page toolbar sits in, which PlaylistHeader.x conceals whole.
@interface _TtCO19LegacyUI_ECMCoreKit5Views10HeaderView : UIView @end
@implementation _TtCO19LegacyUI_ECMCoreKit5Views10HeaderView @end

// Spotify's ⋯ sheet: a table of rows the mod cannot read, whose header is what PlaylistMenu.x sets.
@interface _TtC24ContextMenu_InternalImpl25ContextMenuViewController : UIViewController
@property (nonatomic, strong) UITableView *table;
@end
@implementation _TtC24ContextMenu_InternalImpl25ContextMenuViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1];
    _table = [[UITableView alloc] initWithFrame:CGRectMake(0, 200, self.view.bounds.size.width, 400)];
    _table.backgroundColor = UIColor.clearColor;
    [self.view addSubview:_table];
}
@end

// The plain UIView Liked Songs' shuffle stack sits in: its own pass puts the stack back where Spotify's
// constraints want it, on the right of the row, which is what made the shuffle flash there on the phone.
@interface MockRightHost : UIView @end
@implementation MockRightHost
- (void)layoutSubviews {
    [super layoutSubviews];
    // As Auto Layout does it: center and bounds, never the frame or the transform.
    self.subviews.firstObject.bounds = CGRectMake(0, 0, 48, 48);
    self.subviews.firstObject.center = CGPointMake(76, 24);
}
@end

// Registers no action, as Spotify's Encore controls do: a tap on the redesign's Play reaches it only through accessibility.
static NSUInteger sg_condensedActivated;
@interface MockCondensedButton : UIControl @end
@implementation MockCondensedButton
- (BOOL)accessibilityActivate {
    sg_condensedActivated++;
    return YES;
}
@end

// Spotify enables and disables a button with no layout pass the redesign hears, so a mirror is never disabled as a
// control (it could not hear the source come back): it dims, carries the not-enabled trait, and every tap reads its
// source first. Disabled, the source must not be reached; enabled again with no feed in between, the next tap must
// reach it and clear the dim.
static BOOL dimmedMirror(UIControl *mirror) {
    BOOL trait = mirror.accessibilityTraits & UIAccessibilityTraitNotEnabled;
    return trait && ((UIView *)[mirror valueForKey:@"_glyph"]).alpha < 1 && mirror.enabled;
}
static BOOL undimmedMirror(UIControl *mirror) {
    BOOL trait = mirror.accessibilityTraits & UIAccessibilityTraitNotEnabled;
    return !trait && ((UIView *)[mirror valueForKey:@"_glyph"]).alpha == 1 && mirror.enabled;
}

static void verifyDisabledSource(UIControl *mirror, void (^setSourceEnabled)(BOOL), NSUInteger (^reached)(void), NSString *name) {
    NSUInteger before = reached();
    UIView *source = [mirror valueForKey:@"source"];
    setSourceEnabled(NO);
    [(id)mirror feedFrom:source];
    HARNESS_CHECK(dimmedMirror(mirror));
    [mirror sendActionsForControlEvents:UIControlEventTouchUpInside];
    HARNESS_CHECK(reached() == before && dimmedMirror(mirror));
    // Back on, with no feed: the tap reads the source, fires it and clears the dim.
    setSourceEnabled(YES);
    HARNESS_CHECK(dimmedMirror(mirror));
    [mirror sendActionsForControlEvents:UIControlEventTouchUpInside];
    HARNESS_CHECK(reached() == before + 1 && undimmedMirror(mirror));
    // Off again with no feed: the tap is refused and the mirror dims.
    setSourceEnabled(NO);
    [mirror sendActionsForControlEvents:UIControlEventTouchUpInside];
    HARNESS_CHECK(reached() == before + 1 && dimmedMirror(mirror));
    setSourceEnabled(YES);
    [mirror sendActionsForControlEvents:UIControlEventTouchUpInside];
    HARNESS_CHECK(reached() == before + 2 && undimmedMirror(mirror));
    NSLog(@"[harness] PASS %@ follows its source's enabled state", name);
}

static void verifyDisabledDownload(SGRMirrorButton *mirror, UIControl *source, NSUInteger *fired) {
    verifyDisabledSource(mirror, ^(BOOL on) { source.enabled = on; }, ^NSUInteger { return *fired; }, @"download mirror");
}

static void verifyDisabledPlay(SGRPlayCapsule *play) {
    UIControl *control = nil;
    NSMutableArray *pending = [NSMutableArray arrayWithObject:play.source];
    while (pending.count && !control) {
        UIView *view = pending.firstObject;
        [pending removeObjectAtIndex:0];
        if ([view isKindOfClass:MockCondensedButton.class]) control = (id)view;
        [pending addObjectsFromArray:view.subviews];
    }
    HARNESS_CHECK(control && undimmedMirror(play));
    verifyDisabledSource(play, ^(BOOL on) { control.enabled = on; }, ^NSUInteger { return sg_condensedActivated; }, @"play capsule");
    // Disabled only as the accessibility trait on the wrapping view.
    NSUInteger before = sg_condensedActivated;
    play.source.accessibilityTraits |= UIAccessibilityTraitNotEnabled;
    [play sendActionsForControlEvents:UIControlEventTouchUpInside];
    HARNESS_CHECK(sg_condensedActivated == before && dimmedMirror(play));
    play.source.accessibilityTraits &= ~UIAccessibilityTraitNotEnabled;
    [play sendActionsForControlEvents:UIControlEventTouchUpInside];
    HARNESS_CHECK(sg_condensedActivated == before + 1 && undimmedMirror(play));
}

#pragma mark - building the tree

static UIView *box(UIView *parent, Class cls, CGRect frame, NSString *identifier) {
    UIView *view = [[cls alloc] initWithFrame:frame];
    view.accessibilityIdentifier = identifier;
    [parent addSubview:view];
    return view;
}

static UILabel *label(UIView *parent, CGRect frame, NSString *text, CGFloat size, UIColor *color, NSString *identifier) {
    UIView *encore = box(parent, UIView.class, frame, identifier);
    UILabel *inner = [[UILabel alloc] initWithFrame:encore.bounds];
    inner.text = text;
    inner.font = [UIFont systemFontOfSize:size];
    inner.textColor = color;
    inner.accessibilityIdentifier = [identifier stringByAppendingString:@"-internal"];
    [encore addSubview:inner];
    return inner;
}

static UIImage *artwork(void) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(300, 300)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextRef c = ctx.CGContext;
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGFloat components[] = {0.93, 0.30, 0.47, 1, 0.28, 0.12, 0.42, 1};
        CGGradientRef gradient = CGGradientCreateWithColorComponents(space, components, NULL, 2);
        CGContextDrawLinearGradient(c, gradient, CGPointZero, CGPointMake(300, 300), 0);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);
        [[UIColor colorWithWhite:1 alpha:0.35] setFill];
        for (int i = 0; i < 5; i++) {
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(30 + i * 50, 40 + (i % 3) * 60, 70, 70)] fill];
        }
    }];
}

static UIImage *playGlyph(void) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(48, 48)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        UIBezierPath *path = [UIBezierPath bezierPath];
        [path moveToPoint:CGPointMake(19, 15)];
        [path addLineToPoint:CGPointMake(33, 24)];
        [path addLineToPoint:CGPointMake(19, 33)];
        [path closePath];
        [UIColor.blackColor setFill];
        [path fill];
    }];
}

static UIView *actionButton(UIView *row, CGRect frame, NSString *identifier, NSString *a11y) {
    UIView *action = box(row, UIView.class, frame, nil);
    UIView *element = box(action, UIView.class, action.bounds, nil);
    UIView *button = box(element, UIButton.class, element.bounds, identifier);
    button.accessibilityLabel = a11y;
    UIImageView *glyph = [[UIImageView alloc] initWithFrame:CGRectInset(button.bounds, 12, 12)];
    NSDictionary *glyphs = @{@"Components.UI.AddToButton": @"plus", @"Components.UI.ContextMenuButton": @"ellipsis",
                             @"DownloadButton.Granular.None": @"arrow.down.circle", @"Components.UI.WatchFeedEntityExplorerButton": @"play.rectangle"};
    // Encore bakes the color into what it draws, and ⋯ sits in a Tertiary button, which draws it gray
    // (device 2026-09-20): drawn as an image of that color, not as a template to be tinted.
    BOOL tertiary = [identifier isEqualToString:@"Components.UI.ContextMenuButton"];
    UIImage *symbol = [UIImage systemImageNamed:glyphs[identifier] ?: @"circle"];
    if (tertiary) {
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:symbol.size];
        symbol = [[renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            [[UIColor colorWithWhite:0.70 alpha:1] set];
            [symbol drawInRect:(CGRect){CGPointZero, symbol.size}];
        }] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    }
    glyph.image = symbol;
    glyph.tintColor = UIColor.whiteColor;
    [button addSubview:glyph];
    return action;
}

// What the redesign's row shows on Play's right: the label of the Kit's last round button, the trailing one.
static NSString *trailingLabel(UIView *root) {
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        if ([NSStringFromClass(v.class) isEqualToString:@"SGRHeaderInfo"]) {
            UIView *trailing = nil;
            for (UIView *sub in v.subviews) {
                if ([NSStringFromClass(sub.class) isEqualToString:@"SGRMirrorButton"]) trailing = sub;
            }
            return trailing && !trailing.hidden ? trailing.accessibilityLabel : @"nothing";
        }
        [stack addObjectsFromArray:v.subviews];
    }
    return @"no header";
}

// Where the redesign's header drew the creator's picture and name, or that it drew none.
static NSString *creatorPictureState(UIView *root) {
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        if ([NSStringFromClass(v.class) isEqualToString:@"SGRHeaderInfo"]) {
            UIImageView *picture = nil;
            UILabel *name = nil;
            for (UIView *sub in v.subviews) {
                if ([sub isKindOfClass:UIImageView.class] && !sub.hidden && ((UIImageView *)sub).image) picture = (UIImageView *)sub;
                if ([sub isKindOfClass:UILabel.class] && [((UILabel *)sub).text isEqualToString:@"The Weeknd"]) name = (UILabel *)sub;
            }
            if (!picture) return [NSString stringWithFormat:@"none, name at %@", NSStringFromCGRect(name.frame)];
            return [NSString stringWithFormat:@"drawn at %@ radius %.0f, name at %@", NSStringFromCGRect(picture.frame),
                    picture.layer.cornerRadius, NSStringFromCGRect(name.frame)];
        }
        [stack addObjectsFromArray:v.subviews];
    }
    return @"no header";
}

// Liked Songs (trees/continuous/1.txt, 2026-09-18): the same page with no cover, a 238pt header, a column of
// only the title and the count (the count in a stack of its own, 314pt of label and a 56pt spacer), no add or
// more in the row, the play button 80x48 with its 48pt disc at x=16, and LiquidGlass.gradientContainer, the
// scrim Spotify fades in as the page scrolls. `liked` on the launch line builds it; at 3 s it is scrolled.
static void buildLikedSongs(UIViewController *page, CGFloat W) {
    UIViewController *headerVC = [SPTFreeTierPlaylistEncoreHeaderViewController new];
    [page addChildViewController:headerVC];
    UIView *header = headerVC.view;
    header.frame = CGRectMake(0, -72, W, 310);
    header.accessibilityIdentifier = @"PL.Header";
    header.backgroundColor = UIColor.clearColor;
    [page.view addSubview:header];
    [headerVC didMoveToParentViewController:page];

    UIView *headerLayout = box(header, UIView.class, CGRectMake(0, 72, W, 238), nil);
    UIView *clipping = box(headerLayout, UIView.class, headerLayout.bounds, @"_clippingView");
    UIView *background = box(clipping, UIView.class, clipping.bounds, @"_backgroundViewContainer");
    UIView *wash = box(background, UIView.class, background.bounds, nil);
    UIView *gradient = box(wash, _TtC19LegacyUI_ECMCoreKit13GradientView.class, wash.bounds, nil);
    gradient.backgroundColor = [UIColor colorWithRed:0.25 green:0.2 blue:0.7 alpha:1];
    UIView *safeArea = box(clipping, UIView.class, clipping.bounds, @"_safeAreaView");
    UIView *contentContainer = box(safeArea, UIView.class, CGRectMake(0, -72, W, 310), @"_headerContentContainer");
    UIView *contentView = box(contentContainer, UIView.class, CGRectMake(0, 72, W, 238), @"_contentViewContainer");
    UIView *layout = box(contentView, _TtC28EncoreConsumerMobile_BaseKit19HeaderContentLayout.class, contentView.bounds, nil);

    UIView *slot = box(layout, _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView.class, CGRectMake(178.33, 68, 45.33, 45.33), nil);
    box(slot, UIView.class, slot.bounds, nil);

    // Loading, the block sits above the icon's slot (so the slot is the lowest child) and moves down after.
    UIView *block = box(layout, UIView.class, CGRectMake(0, 20, 386, 108.67), nil);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        block.frame = CGRectMake(0, 129.33, 386, 108.67);
        [layout setNeedsLayout];
        [layout layoutIfNeeded];
        __block NSUInteger infos = 0;
        NSMutableArray *stack = [NSMutableArray arrayWithObject:page.view];
        while (stack.count) {
            UIView *v = stack.lastObject; [stack removeLastObject];
            if ([NSStringFromClass(v.class) isEqualToString:@"SGRHeaderInfo"]) infos++;
            [stack addObjectsFromArray:v.subviews];
        }
        NSLog(@"[harness] liked: after loading, %lu redesign blocks on the page", (unsigned long)infos);
    });
    UIView *blockInner = box(box(block, UIView.class, block.bounds, nil), UIView.class, CGRectMake(0, 0, 386, 100.67), nil);
    UIView *columnStack = box(blockInner, _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView.class, CGRectMake(16, 0, 370, 100.67), nil);
    UIView *columnAndRow = box(columnStack, UIView.class, columnStack.bounds, nil);
    UIView *columnHost = box(columnAndRow, UIView.class, CGRectMake(0, 0, 370, 44.67), nil);
    UIView *titleStack = box(columnHost, _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView.class, columnHost.bounds, nil);
    UIView *column = box(titleStack, UIView.class, titleStack.bounds, nil);
    label(column, CGRectMake(0, 0, 370, 25.33), @"Liked Songs", 21, UIColor.whiteColor, @"Encore.Label");
    UIView *countStack = box(column, _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView.class, CGRectMake(0, 29.33, 370, 15.33), nil);
    UIView *countRow = box(countStack, UIView.class, countStack.bounds, nil);
    label(countRow, CGRectMake(0, 0, 314, 15.33), @"1 016 songs", 11, [UIColor colorWithWhite:1 alpha:0.4],
          @"Components.Header.UI.Metadata").textAlignment = NSTextAlignmentLeft;
    box(countRow, UIView.class, CGRectMake(314, 7.67, 56, 0), nil);

    UIView *rowHost = box(columnAndRow, UIView.class, CGRectMake(0, 52.67, 370, 48), nil);
    UIView *rowStack = box(rowHost, _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView.class, rowHost.bounds, nil);
    UIView *container = box(rowStack, UIView.class, rowStack.bounds, nil);
    UIView *left = box(container, UIView.class, CGRectMake(0, 0, 96, 48), nil);
    UIView *leftStack = box(left, _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView.class, CGRectMake(-10, 0, 106, 48), nil);
    UIView *element = box(box(leftStack, UIView.class, leftStack.bounds, nil), _TtGC13Element_UIKit11ElementViewT_P_P__.class, CGRectMake(0, 0, 106, 48), nil);
    UIStackView *actions = (UIStackView *)box(element, UIStackView.class, element.bounds, @"HeaderActionsRow");
    actionButton(actions, CGRectMake(0, 4, 58, 40), @"Components.UI.WatchFeedEntityExplorerButton", @"Explore Liked Songs");
    actionButton(actions, CGRectMake(58, 0, 48, 48), @"DownloadButton.Granular.None", @"Download");
    box(container, UIView.class, CGRectMake(96, 23.67, 174, 1), nil);
    UIView *right = box(container, MockRightHost.class, CGRectMake(270, 0, 100, 48), nil);
    UIView *rightStack = box(right, _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView.class, CGRectMake(-184, 0, 48, 48), nil);
    UIView *shuffleHost = box(box(rightStack, UIView.class, rightStack.bounds, nil), UIView.class, CGRectMake(0, 0, 48, 48), nil);
    UIView *shuffle = box(shuffleHost, UIButton.class, shuffleHost.bounds, @"Components.UI.ShuffleButton");
    shuffle.accessibilityLabel = @"Shuffle tracks";
    UIImageView *shuffleGlyph = [[UIImageView alloc] initWithFrame:CGRectInset(shuffle.bounds, 12, 12)];
    shuffleGlyph.image = [UIImage systemImageNamed:@"shuffle"];
    shuffleGlyph.tintColor = [UIColor colorWithRed:0.02 green:0.97 blue:0 alpha:1];
    [shuffle addSubview:shuffleGlyph];

    UIView *scrim = box(headerLayout, UIView.class, CGRectMake(0, 0, W, 124), @"LiquidGlass.gradientContainer");
    scrim.alpha = 0;
    box(scrim, UIView.class, scrim.bounds, @"LiquidGlass.GradientView").backgroundColor = [UIColor colorWithRed:0.25 green:0.3 blue:0.9 alpha:1];

    UIView *foreground = box(headerLayout, UIView.class, headerLayout.bounds, @"_foregroundViewContainer");
    UIView *playButton = box(foreground, _TtC28EncoreConsumerMobile_BaseKit14PlayButtonView.class, CGRectMake(322, 182, 80, 48), @"header-play-button");
    UIControl *condensed = (UIControl *)box(playButton, MockCondensedButton.class, CGRectMake(16, 0, 48, 48), nil);
    condensed.accessibilityLabel = @"Shuffle Play";
    UIImageView *disc = [[UIImageView alloc] initWithFrame:condensed.bounds];
    disc.image = [[UIImage systemImageNamed:@"shuffle"] imageByApplyingSymbolConfiguration:
                  [UIImageSymbolConfiguration configurationWithPointSize:18]];
    disc.contentMode = UIViewContentModeCenter;
    disc.backgroundColor = [UIColor colorWithRed:0.02 green:0.97 blue:0 alpha:1];
    [condensed addSubview:disc];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        scrim.alpha = 1;
        [layout setNeedsLayout];
        [layout layoutIfNeeded];
        // Spotify's parent laying the shuffle out again, after every pass of the header's.
        [right setNeedsLayout];
        [right layoutIfNeeded];
        CGRect shuffleInRow = [container convertRect:shuffle.bounds fromView:shuffle];
        UIView *capsule = container.subviews.lastObject;
        NSLog(@"[harness] liked: after the shuffle's parent laid out: shuffle %@, capsule %@ (%@), screen middle %.1f",
              NSStringFromCGRect([container convertRect:shuffleInRow toView:nil]),
              NSStringFromCGRect([container convertRect:capsule.frame toView:nil]), capsule.class,
              CGRectGetMidX(page.view.bounds));
        NSLog(@"[harness] liked: scrolled, scrim a=%.2f hidden=%d masked=%d; column rows %@ / %@",
              scrim.alpha, scrim.layer.hidden, scrim.layer.mask != nil,
              NSStringFromCGRect(column.subviews[0].frame), NSStringFromCGRect(column.subviews[1].frame));
    });
}

@interface SGRHarnessDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation SGRHarnessDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    if ([NSProcessInfo.processInfo.arguments containsObject:@"cover-beside"])
        [NSUserDefaults.standardUserDefaults setBool:![NSProcessInfo.processInfo.arguments containsObject:@"card-cover"]
                                            forKey:SGRKeyCoverBeside];
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    CGFloat W = self.window.bounds.size.width, H = self.window.bounds.size.height;
    CGFloat fixtureWidth = [NSUserDefaults.standardUserDefaults doubleForKey:@"header-width"];
    if (fixtureWidth > 0) W = fixtureWidth;

    UIViewController *page = [_TtC35ListUXPlatform_FreeTierPlaylistImpl17FTPViewController new];
    page.view.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1];
    self.window.rootViewController = page;
    // `rtl`: the page laid out right to left, as in Arabic or Hebrew; `freeze`: its first frame under the veil held.
    if ([NSProcessInfo.processInfo.arguments containsObject:@"rtl"])
        page.view.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    watchPinnedHold(page.view, [NSProcessInfo.processInfo.arguments containsObject:@"freeze"]);
    // The device's page counts the navigation bar into its own safe area -- 116 against the window's 62 --
    // which is what put the pinned ⋯ a bar's height below the back button (trees/continuous/1.txt 2026-09-20).
    page.additionalSafeAreaInsets = UIEdgeInsetsMake(54, 0, 0, 0);

    // the list
    UIScrollView *list = (UIScrollView *)box(page.view, _TtC35ListUXPlatform_FreeTierPlaylistImpl32FTPTouchCancellingCollectionView.class,
                                             CGRectMake(0, 0, W, H), @"SPTFreeTierPlaylistTableView");
    list.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1];
    NSArray<NSArray<NSString *> *> *tracks = @[@[@"Cry For Me", @"The Weeknd"], @[@"I Can't Fucking Sing", @"The Weeknd"],
                                              @[@"São Paulo", @"The Weeknd, Anitta"], @[@"Until We're Skin & Bones", @"The Weeknd"],
                                              @[@"Baptized In Fear", @"The Weeknd"]];
    // The curation row stands over the first track, where Spotify's list has it, and the tracks start under it.
    CGFloat tracksTop = 564;
    for (NSUInteger i = 0; i < tracks.count; i++) {
        UIView *cell = box(list, _TtC35ListUXPlatform_FreeTierPlaylistImpl25ElementCollectionViewCell.class,
                           CGRectMake(0, tracksTop + i * 64, W, 64), @"Playlist.ItemCell");
        cell.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1];
        UIView *row = box(cell, UIView.class, cell.bounds, @"Encore.ListRow");
        row.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1];
        UIView *art = box(row, UIView.class, CGRectMake(16, 8, 48, 48), @"Encore.ImageView");
        UIImageView *picture = [[UIImageView alloc] initWithFrame:art.bounds];
        picture.image = artwork();
        [art addSubview:picture];
        label(row, CGRectMake(76, 12, W - 130, 20), tracks[i][0], 16, UIColor.whiteColor, @"Track.Row.Content.Title");
        label(row, CGRectMake(76, 32, W - 130, 18), tracks[i][1], 14, [UIColor colorWithWhite:1 alpha:0.7], @"Track.Row.Content.Subtitle");
    }

    // The extender under the tracks (device, trees/continuous/2.txt 2026-09-20): Recommended songs, its
    // rows and Refresh, each cell painting the black the AMOLED made of Spotify's base surface over the
    // field. Only the paint is mocked -- what the clear has to take off and what it has to leave.
    CGFloat extenderTop = tracksTop + tracks.count * 64;
    UIView *heading = box(list, _TtC35ListUXPlatform_FreeTierPlaylistImpl25ElementCollectionViewCell.class,
                          CGRectMake(0, extenderTop, W, 68), nil);
    UIView *headingPaint = box(heading, UIView.class, heading.bounds, @"PlaylistExtender.Heading");
    headingPaint.backgroundColor = UIColor.blackColor;
    label(headingPaint, CGRectMake(16, 16, W - 32, 21), @"Recommended songs", 17, UIColor.whiteColor, @"title");
    label(headingPaint, CGRectMake(16, 37, W - 32, 16), @"Based on the songs of this playlist", 11,
          [UIColor colorWithWhite:0.7 alpha:1], @"subtitle");

    // Spotify mounts the recommendations heading of some playlists (This Is ...) as a plain UICollectionViewCell
    // straight into the list, outside visibleCells.
    UIView *plainHeading = box(list, UICollectionViewCell.class, CGRectMake(0, extenderTop + 180, W, 52), nil);
    UIView *plainHeadingPaint = box(plainHeading, UIView.class, plainHeading.bounds, nil);
    plainHeadingPaint.backgroundColor = UIColor.blackColor;
    label(plainHeadingPaint, CGRectMake(16, 16, W - 32, 21), @"Recommended", 17, UIColor.whiteColor, @"title");

    UIView *extenderRow = box(list, _TtC35ListUXPlatform_FreeTierPlaylistImpl25ElementCollectionViewCell.class,
                              CGRectMake(0, extenderTop + 68, W, 64), nil);
    UIView *extenderPaint = box(extenderRow, UIView.class, extenderRow.bounds, @"PlaylistExtender.Row");
    label(extenderPaint, CGRectMake(76, 22, W - 130, 20), @"Airplanes", 16, UIColor.whiteColor, nil);
    // A badge's disc is its own black and is not as wide as the cell: it stays.
    UIView *badge = box(extenderPaint, UIView.class, CGRectMake(W - 72, 19, 26, 26), @"PlaylistExtender.Badge");
    badge.backgroundColor = UIColor.blackColor;
    badge.layer.cornerRadius = 13;

    // A card in a carousel: a cell of its own inside the row, narrower than the page, whose color is its own
    // and stays.
    UIView *card = box(extenderRow, MockCardCell.class, CGRectMake(16, 8, 140, 48), @"PlaylistExtender.Card");
    card.layer.backgroundColor = UIColor.blackColor.CGColor;

    // Refresh, nested the way the device has it: the cell, the element framework's own content cell the full
    // width of it, the element view, and the black on the layer rather than through the view
    // (trees/continuous/1.txt:1919-1922). Both of those are what the first clear walked past.
    UIView *refresh = box(list, _TtC35ListUXPlatform_FreeTierPlaylistImpl25ElementCollectionViewCell.class,
                          CGRectMake(0, extenderTop + 132, W, 48), nil);
    UIView *refreshContent = box(refresh, MockElementContentView.class, refresh.bounds, nil);
    UIView *refreshElement = box(refreshContent, _TtGC13Element_UIKit11ElementViewT_P_P__.class, refresh.bounds, nil);
    UIView *refreshPaint = box(refreshElement, UIView.class, refresh.bounds, @"PlaylistExtender.Refresh");
    refreshPaint.layer.backgroundColor = UIColor.blackColor.CGColor;
    UIView *button = box(refreshPaint, UIView.class, CGRectMake(W / 2 - 36, 8, 72, 32), @"section-header-button");
    button.backgroundColor = UIColor.whiteColor;
    button.layer.cornerRadius = 16;

    // The curation row over the first track (own-playlist/01.txt:33): Add, Mix, Notes, Video, Edit, Sort and
    // Name & details in a scroll view, of which the redesign keeps Sort and Mix.
    // `nohandover` builds the row in a cell the redesign's hook never sees, the way the device has it when
    // the collection has not laid the closed-up cell out yet: the sheet then has to find the row itself.
    BOOL handover = ![NSProcessInfo.processInfo.arguments containsObject:@"nohandover"];
    UIView *curation = box(list, handover ? _TtC35ListUXPlatform_FreeTierPlaylistImpl25ElementCollectionViewCell.class
                                          : UICollectionViewCell.class,
                           CGRectMake(0, tracksTop - 52, W, 52), nil);
    UIView *toolbar = box(curation, UIView.class, curation.bounds, @"PlaylistCuration.Row.CurationActionsToolbar");
    toolbar.layer.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1].CGColor;
    UIScrollView *pillScroll = (UIScrollView *)box(box(toolbar, UIView.class, toolbar.bounds, nil),
                                                   _TtC19LegacyUI_ECMCoreKit10ScrollView.class,
                                                   CGRectMake(0, 10, W, 32), nil);
    UIView *pillContent = box(pillScroll, UIView.class, CGRectMake(0, 0, 527, 32), nil);
    UIView *pillStack = box(pillContent, _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView.class, pillContent.bounds, nil);
    UIView *pillRow = box(pillStack, UIView.class, pillStack.bounds, nil);
    pillScroll.contentSize = pillContent.bounds.size;
    NSArray<NSArray<NSString *> *> *pills = @[@[@"Add", @"PlaylistCuration.AddButton", @"plus"],
                                              @[@"Mix", @"ListPlatform.ToolbarActions.MixButton", @"mix"],
                                              @[@"Video", @"Encore.Button.Primary", @"video"],
                                              @[@"Edit", @"Encore.Button.Primary", @"edit"],
                                              @[@"Sort", @"Encore.Button.Primary", @"sortDown"],
                                              @[@"Name & details", @"Encore.Button.Primary", @"playlist"]];
    CGFloat pillX = 0;
    NSMutableArray<UIView *> *pillViews = [NSMutableArray array];
    for (NSArray<NSString *> *pill in pills) {
        CGFloat width = 40 + pill[0].length * 6;
        UIView *wrapper = box(pillRow, _TtGC13Element_UIKit11ElementViewT_P_P__.class, CGRectMake(pillX, 0, width, 32), nil);
        UIButton *pillButton = (UIButton *)box(wrapper, UIButton.class, wrapper.bounds, pill[1]);
        pillButton.accessibilityLabel = pill[0];
        [pillButton addTarget:page action:@selector(sgr_pillFired:) forControlEvents:UIControlEventTouchUpInside];
        pillButton.layer.backgroundColor = [UIColor colorWithWhite:1 alpha:0.14].CGColor;
        pillButton.layer.cornerRadius = 16;
        SPTEncoreIconView *icon = (SPTEncoreIconView *)box(pillButton, SPTEncoreIconView.class, CGRectMake(10, 10, 12, 12), @"Encore.IconView");
        MockEncoreIcon *glyph = [MockEncoreIcon new];
        glyph.name = pill[2];
        icon->icon = glyph;
        label(pillButton, CGRectMake(26, 8, width - 32, 16), pill[0], 11, UIColor.whiteColor, @"Encore.Label");
        [pillViews addObject:wrapper];
        pillX += width + 8;
    }

    // `rebuilt` on the launch line: Spotify rebuilds the header's cells before the sheet opens. The row the
    // page was handed leaves the window and a new one takes its place in a cell the redesign's hook never
    // sees, so the sheet has to read Mix off the new row: the log has to say "Mix (rebuilt)".
    if ([NSProcessInfo.processInfo.arguments containsObject:@"rebuilt"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            CGRect frame = curation.frame;
            [curation removeFromSuperview];
            UIView *cell = box(list, UICollectionViewCell.class, frame, nil);
            UIView *row = box(cell, UIView.class, cell.bounds, @"PlaylistCuration.Row.CurationActionsToolbar");
            UIButton *mix = (UIButton *)box(row, UIButton.class, CGRectMake(0, 10, 60, 32), @"ListPlatform.ToolbarActions.MixButton");
            mix.accessibilityLabel = @"Mix (rebuilt)";
            [mix addTarget:page action:@selector(sgr_pillFired:) forControlEvents:UIControlEventTouchUpInside];
            label(mix, CGRectMake(8, 8, 44, 16), @"Mix (rebuilt)", 11, UIColor.whiteColor, @"Encore.Label");
            NSLog(@"[harness] the curation row rebuilt");
        });
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // Cleared means an alpha of 0, whether the color was taken off the layer or the view: the clear
        // color lands on both and reads back with no alpha at all.
        CGFloat (^alpha)(UIView *) = ^(UIView *v) {
            return v.layer.backgroundColor ? CGColorGetAlpha(v.layer.backgroundColor) : 0;
        };
        NSLog(@"[harness] extender paint: heading a=%.0f row-badge a=%.0f card a=%.0f refresh a=%.0f plain heading a=%.0f",
              alpha(headingPaint), alpha(badge), alpha(card), alpha(refreshPaint), alpha(plainHeadingPaint));
    });

    // The page comes in whole (Kit/SGRField.h): a veil over it until the cover has been read, or, with no cover,
    // until it has its title. Just after launch it is there or already fading; by 3 s, past the field's limit, it is gone.
    for (NSNumber *when in @[@0.01, @3]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(when.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIView *veil = nil;
            for (UIView *sub in page.view.subviews) {
                if ([NSStringFromClass(sub.class) isEqualToString:@"SGRFieldVeil"]) veil = sub;
            }
            NSLog(@"[harness] whole page at %.2f s: %@", when.doubleValue,
                  veil ? [NSString stringWithFormat:@"veil a=%.2f, %@ the pinned more", veil.layer.presentationLayer.opacity,
                          page.view.subviews.lastObject == veil ? @"over" : @"under"] : @"no veil");
        });
    }

    if ([NSProcessInfo.processInfo.arguments containsObject:@"liked"]) {
        buildLikedSongs(page, W);
        [self.window makeKeyAndVisible];
        return YES;
    }

    // the header
    UIViewController *headerVC = [SPTFreeTierPlaylistEncoreHeaderViewController new];
    [page addChildViewController:headerVC];
    UIView *header = headerVC.view;
    header.frame = CGRectMake(0, -134, W, 639.33);
    header.accessibilityIdentifier = @"PL.Header";
    header.backgroundColor = UIColor.clearColor;
    [page.view addSubview:header];
    [headerVC didMoveToParentViewController:page];

    UIView *headerLayout = box(header, UIView.class, CGRectMake(0, 134, W, 505.33), nil);
    UIView *clipping = box(headerLayout, UIView.class, headerLayout.bounds, @"_clippingView");
    UIView *background = box(clipping, UIView.class, clipping.bounds, @"_backgroundViewContainer");
    UIView *wash = box(background, UIView.class, background.bounds, nil);
    wash.clipsToBounds = YES;
    UIView *gradient = box(wash, _TtC19LegacyUI_ECMCoreKit13GradientView.class, wash.bounds, nil);
    gradient.backgroundColor = [UIColor colorWithRed:0.5 green:0.1 blue:0.3 alpha:1];
    // The second wash of the plane: a plain view painted the base surface with a gradient of its own in it,
    // drawn after the hero. Spotify keeps it at alpha 0 on an ordinary playlist and raises it with the Mix
    // feature on, where its black covered the picture whole (trees/continuous/1.txt 2026-09-20).
    UIView *mixWash = box(wash, UIView.class, wash.bounds, nil);
    mixWash.backgroundColor = UIColor.blackColor;
    mixWash.alpha = [NSProcessInfo.processInfo.arguments containsObject:@"mixon"] ? 1 : 0;
    UIView *mixGradient = box(mixWash, _TtC19LegacyUI_ECMCoreKit13GradientView.class, CGRectMake(0, 8, 560, 560), nil);
    mixGradient.backgroundColor = [UIColor colorWithRed:0.1 green:0.4 blue:0.2 alpha:1];

    UIView *safeArea = box(clipping, UIView.class, clipping.bounds, @"_safeAreaView");
    UIView *contentContainer = box(safeArea, UIView.class, CGRectMake(0, -134, W, 639.33), @"_headerContentContainer");
    UIView *contentView = box(contentContainer, UIView.class, CGRectMake(0, 134, W, 505.33), @"_contentViewContainer");
    UIView *layout = box(contentView, _TtC28EncoreConsumerMobile_BaseKit19HeaderContentLayout.class, contentView.bounds, nil);

    // The cover: a mix's full bleed picture, or a playlist's square. `mix` on the launch line builds the
    // header a playlist Spotify makes gets (trees/continuous/4.txt:1066): no Components.Header.UI.ArtworkImage
    // anywhere, and in its place a HeaderFullbleedCentralView holding the picture, the fade under it and
    // Spotify's own big title. It is the layout's first child and as wide as the page, which is what the
    // block used to be taken for.
    BOOL mix = [NSProcessInfo.processInfo.arguments containsObject:@"mix"];
    UIView *cover = nil, *fullbleed = nil;
    if (mix) {
        fullbleed = box(layout, _TtC28EncoreConsumerMobile_BaseKit26HeaderFullbleedCentralView.class,
                        CGRectMake(0, 0, W, 311), nil);
        fullbleed.clipsToBounds = YES;
        UIView *slot = box(fullbleed, UIView.class, CGRectMake(-10, 0, W + 20, W + 20), nil);
        UIView *slotImage = box(slot, UIView.class, slot.bounds, @"Encore.ImageView");
        UIImageView *slotPicture = [[UIImageView alloc] initWithFrame:slotImage.bounds];
        slotPicture.image = artwork();
        slotPicture.contentMode = UIViewContentModeScaleAspectFill;
        [slotImage addSubview:slotPicture];
        UIView *fade = box(fullbleed, _TtC19LegacyUI_ECMCoreKit13GradientView.class, CGRectMake(0, 225, W, 86), nil);
        fade.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
        UIView *titleStack = box(fullbleed, _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView.class,
                                 CGRectMake(16, 249, W - 32, 54), nil);
        label(titleStack, titleStack.bounds, @"Indie Rock Mix", 45, UIColor.whiteColor, @"Encore.Label");
    } else {
        cover = box(layout, UIView.class, CGRectMake(round((W - 182) / 2), 68, 182, 182), @"Components.Header.UI.ArtworkImage");
        UIView *coverImage = box(cover, UIView.class, cover.bounds, @"Encore.ImageView");
        UIImageView *coverPicture = [[UIImageView alloc] initWithFrame:coverImage.bounds];
        coverPicture.image = artwork();
        coverPicture.contentMode = UIViewContentModeScaleAspectFill;
        [coverImage addSubview:coverPicture];
    }

    // the block: the column, then the action row
    UIView *block = box(layout, UIView.class, CGRectMake(0, 266.67, W - 16, 178.33), nil);
    UIView *blockStack = box(block, _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView.class, block.bounds, nil);
    UIView *blockInner = box(blockStack, UIView.class, blockStack.bounds, nil);

    UIView *columnHost = box(blockInner, UIView.class, CGRectMake(0, 0, block.bounds.size.width, 122.33), nil);
    UIView *columnStack = box(columnHost, _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView.class,
                              CGRectMake(16, 0, columnHost.bounds.size.width - 16, 122.33), nil);
    UIView *column = box(columnStack, UIView.class, columnStack.bounds, nil);
    CGFloat columnWidth = column.bounds.size.width;

    label(column, CGRectMake(0, 0, columnWidth, 29.67), @"Hurry Up Tomorrow", 21, UIColor.whiteColor, @"Encore.Label");

    UIView *descriptionRow = box(column, UIView.class, CGRectMake(0, 33.67, columnWidth, 31.33), nil);
    UITextView *description = (UITextView *)box(descriptionRow, _TtC44PlaylistCuration_ExpandableTextElementKit18ExpandableTextView.class,
                                                descriptionRow.bounds, nil);
    description.text = @"On what was meant to be the last date of his 2022 tour, The Weeknd took the stage.";
    description.font = [UIFont systemFontOfSize:14];
    description.textColor = UIColor.whiteColor;
    description.backgroundColor = UIColor.clearColor;
    description.textContainerInset = UIEdgeInsetsZero;
    description.textContainer.lineFragmentPadding = 0;

    UIView *creatorRow = box(column, UIView.class, CGRectMake(0, 69, columnWidth, 34), nil);
    UIButton *creator = (UIButton *)box(creatorRow, UIButton.class, CGRectMake(0, 0, 109.67, 34),
                                        @"Components.PlaylistHeader.collaboratorsButton");
    creator.accessibilityLabel = @"Playlist created by The Weeknd";
    [creator addTarget:page action:@selector(sgr_creatorFired) forControlEvents:UIControlEventTouchUpInside];
    UIView *face = box(creator, _TtCE13Encore_FaceKitO16EncoreFoundation6Encore12FacepileView.class, CGRectMake(0, 5, 24, 24), nil);
    face.backgroundColor = [UIColor colorWithWhite:0.8 alpha:1];
    face.layer.cornerRadius = 12;
    // The owner's picture, in an image view inside the facepile, landing at 1.5 s after the header has laid out.
    UIImageView *facePicture = [[UIImageView alloc] initWithFrame:face.bounds];
    [face addSubview:facePicture];
    label(creator, CGRectMake(32, 9, 77, 16), @"The Weeknd", 13, UIColor.whiteColor, @"Encore.Label");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        facePicture.image = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(48, 48)] imageWithActions:^(UIGraphicsImageRendererContext *c) {
            [UIColor.orangeColor setFill];
            UIRectFill(CGRectMake(0, 0, 48, 48));
        }];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSLog(@"[harness] owner picture: %@", creatorPictureState(page.view));
        NSArray *args = NSProcessInfo.processInfo.arguments;
        if ([args containsObject:@"verify-details"]) {
            BOOL line = ![args containsObject:@"no-line"], picture = line && ![args containsObject:@"no-picture"];
            NSMutableSet *visible = [NSMutableSet set];
            SGForEachView(page.view, ^(UIView *view) {
                if (![NSStringFromClass(view.superview.class) isEqualToString:@"SGRHeaderInfo"] ||
                    ![view isKindOfClass:UILabel.class] || view.hidden) return;
                UILabel *label = (UILabel *)view;
                [visible addObject:label.text ?: @""];
                if ([args containsObject:@"verify-card-gap"] && [label.text isEqual:@"Barre Beats"]) {
                    CGFloat coverBottom = CGRectGetMaxY([cover convertRect:cover.bounds toView:layout]);
                    CGFloat gap = CGRectGetMinY([label convertRect:label.bounds toView:layout]) - coverBottom;
                    CGFloat expected = CGRectGetMinY(block.frame) - coverBottom;
                    if (fabs(gap - expected) > 0.5)
                        HARNESS_FAIL(@"Compact Card cover-to-title gap %.2f, expected %.2f", gap, expected);
                    NSLog(@"[harness] PASS compact Card cover-to-title gap %.2f", gap);
                }
                if ([label.text isEqual:@"The Weeknd"] && (!label.userInteractionEnabled ||
                    !(label.accessibilityTraits & UIAccessibilityTraitButton))) HARNESS_FAIL(@"Creator lost its link");
            });
            NSMutableSet *want = [NSMutableSet setWithObject:@"Barre Beats"];
            if (line) [want addObjectsFromArray:@[@"The Weeknd", @"4 637 saves • 20h 28m"]];
            if (![args containsObject:@"no-description"])
                [want addObject:@"All music for beat-driven barre classes. Some cool-downs too! I'm always adding to the list"];
            if (![visible isEqual:want] || [creatorPictureState(page.view) hasPrefix:@"drawn"] != picture)
                HARNESS_FAIL(@"Playlist metadata: visible %@, expected %@, picture %@", visible, want, creatorPictureState(page.view));
            fprintf(stderr, "PASS playlist metadata\n");
        }
    });
    box(creatorRow, UIView.class, CGRectMake(109.67, 0, columnWidth - 109.67, 34), nil);

    UIView *lengthRow = box(column, UIView.class, CGRectMake(0, 107, columnWidth, 15.33), nil);
    UIView *length = box(lengthRow, UIView.class, CGRectMake(0, 0, 126.33, 15.33), nil);
    label(length, CGRectMake(0, 0, 126.33, 15.33), @"4 637 saves • 20h 28m", 11, [UIColor colorWithWhite:1 alpha:0.7],
          @"Components.Header.UI.Metadata");
    box(lengthRow, UIView.class, CGRectMake(126.33, 0, columnWidth - 126.33, 15.33), nil);

    UIView *actionHost = box(blockInner, UIView.class, CGRectMake(0, 130.33, block.bounds.size.width, 48), nil);
    UIView *actionStack = box(actionHost, _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView.class,
                              CGRectMake(4, 0, actionHost.bounds.size.width - 4, 48), nil);
    UIView *container = box(actionStack, UIView.class, actionStack.bounds, nil);
    UIView *rowElement = box(container, _TtGC13Element_UIKit11ElementViewT_P_P__.class, CGRectMake(0, 0, 198, 48), nil);
    UIStackView *actions = (UIStackView *)box(rowElement, UIStackView.class, rowElement.bounds, @"HeaderActionsRow");
    actionButton(actions, CGRectMake(0, 4, 58, 40), @"Components.UI.WatchFeedEntityExplorerButton", @"Explore");
    // `late` on the launch line: save is not in the row yet, the way a playlist opened for the first time has it,
    // and arrives at 2.5 s as an arranged subview of the row, which lays out the row and nothing above it.
    BOOL late = [NSProcessInfo.processInfo.arguments containsObject:@"late"];
    if (late) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [actions insertArrangedSubview:actionButton(actions, CGRectMake(58, 0, 48, 48), @"Components.UI.AddToButton", @"Like")
                                   atIndex:0];
            NSLog(@"[harness] late: save arrived in the row");
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSLog(@"[harness] late: Play's right shows \"%@\"", trailingLabel(page.view));
        });
    } else if ([NSProcessInfo.processInfo.arguments containsObject:@"saved"]) {
        // Save with the Encore object behind it (download-mock.h), so the redesign can read whether it is saved.
        mockAddToButton(box(actions, UIView.class, CGRectMake(58, 0, 48, 48), nil));
    } else {
        actionButton(actions, CGRectMake(58, 0, 48, 48), @"Components.UI.AddToButton", @"Like");
    }
    // Drawn by Lottie, its state in its identifier and in the Encore object behind it (issue #65).
    UIView *downloadAction = box(actions, UIView.class, CGRectMake(106, 0, 48, 48), nil);
    if (![NSProcessInfo.processInfo.arguments containsObject:@"no-download"])
        mockDownloadButton(box(downloadAction, UIView.class, downloadAction.bounds, nil));
    actionButton(actions, CGRectMake(154, 2, 44, 44), @"Components.UI.ContextMenuButton", @"More options");

    UIView *mixShuffle = box(container, UIView.class, CGRectMake(container.bounds.size.width - 124, 0, 124, 48), nil);
    UIView *mixShuffleStack = box(mixShuffle, UIStackView.class, CGRectMake(0, 0, 68, 48), nil);
    box(mixShuffleStack, UIView.class, CGRectMake(0, 0, 20, 48), @"MixAndShuffleComposedUI.mixView");
    UIView *shuffleView = box(mixShuffleStack, UIView.class, CGRectMake(20, 0, 48, 48), @"MixAndShuffleComposedUI.shuffleView");
    UIView *shuffleElement = box(shuffleView, UIView.class, shuffleView.bounds, nil);
    UIView *shuffle = box(shuffleElement, UIButton.class, shuffleElement.bounds, @"Components.UI.ShuffleButton");
    shuffle.accessibilityLabel = @"Shuffle tracks";
    mockShuffleGlyph(shuffle);

    // The find-on-page toolbar the header conceals, whose Sort button is what the ⋯ sheet fires: one
    // identifier, in the header rather than in a cell the list reuses (trees/continuous/1.txt:1000).
    UIView *topAccessory = box(headerLayout, UIView.class, CGRectMake(0, 16, W, 134), @"_topAccessoryViewContainer");
    UIView *toolbarHeader = box(topAccessory, _TtCO19LegacyUI_ECMCoreKit5Views10HeaderView.class, CGRectMake(0, 0, W, 134), nil);
    UIView *toolbarContent = box(toolbarHeader, UIView.class, CGRectMake(16, 98, W - 32, 36), @"Components.Header.UI.Toolbar.Content");
    UIView *sortContainer = box(toolbarContent, UIView.class, CGRectMake(W - 94, 0, 62, 36), @"Components.Header.UI.Toolbar.ButtonContainer");
    sortContainer.hidden = YES;
    UIButton *headerSort = (UIButton *)box(sortContainer, UIButton.class, CGRectMake(16, 0, 30, 36), @"Components.Header.UI.Toolbar.Button");
    [headerSort setTitle:@"Sort" forState:UIControlStateNormal];
    [headerSort addTarget:page action:@selector(sgr_pillFired:) forControlEvents:UIControlEventTouchUpInside];
    headerSort.accessibilityLabel = @"Sort";

    // the play button, in the header's foreground plane
    UIView *foreground = box(headerLayout, UIView.class, headerLayout.bounds, @"_foregroundViewContainer");
    UIView *playHost = box(foreground, UIView.class, CGRectMake(W - 64, 457.33, 64, 48), nil);
    UIView *playButton = box(playHost, _TtC28EncoreConsumerMobile_BaseKit14PlayButtonView.class, CGRectMake(0, 0, 48, 48), @"header-play-button");
    UIControl *condensed = (UIControl *)box(playButton, MockCondensedButton.class, playButton.bounds, nil);
    condensed.accessibilityLabel = @"Play";
    UIImageView *disc = [[UIImageView alloc] initWithFrame:condensed.bounds];
    disc.image = playGlyph();
    disc.backgroundColor = [UIColor colorWithRed:0.12 green:0.84 blue:0.38 alpha:1];
    disc.layer.cornerRadius = 24;
    disc.clipsToBounds = YES;
    [condensed addSubview:disc];

    // The pass that used to lose the picture: while Spotify is still measuring, the block has no width of
    // its own, and the full bleed view is then the only child of the layout wide enough to be taken for it.
    // Taken for the block, everything it holds -- the picture with it -- was concealed, and concealing does
    // not come undone, so the hero stayed black for as long as the page was open (trees/continuous/3.txt
    // against 4.txt, 2026-09-20). The mix runs that pass before any other, so a regression shows here too.
    if (mix) {
        CGRect settled = block.frame;
        block.frame = CGRectMake(0, 266.67, 0, 0);
        [layout setNeedsLayout];
        [layout layoutIfNeeded];
        block.frame = settled;
        NSLog(@"[harness] the measuring pass is done: the full bleed view is %@",
              fullbleed.layer.hidden ? @"concealed" : @"still drawn");
    }

    if ([NSProcessInfo.processInfo.arguments containsObject:@"tablet-entry"]) {
        // Don't mount a portrait header before the first landscape pass. The readable
        // column, content layout and clipped background have different coordinate spaces.
        [header removeFromSuperview];
        [self.window makeKeyAndVisible];
        dispatch_async(dispatch_get_main_queue(), ^{
            for (NSNumber *wide in @[@YES, @NO, @YES]) {
                BOOL landscape = wide.boolValue;
                CGFloat width = landscape ? 1194 : 834, height = landscape ? 316 : 505;
                header.frame = CGRectMake(0, 0, width, height);
                for (UIView *v in @[headerLayout, clipping, background, wash, safeArea, contentContainer, contentView])
                    v.frame = header.bounds;
                layout.frame = CGRectOffset(header.bounds, landscape ? 90 : 0, 0);
                cover.frame = CGRectMake(20, 64, 182, 182);
                block.frame = landscape ? CGRectMake(360, 70, 620, 234) : CGRectMake(0, 267, width - 16, 238);
                UIView *track = SGFindIdentifier(list, @"Playlist.ItemCell", NULL);
                HARNESS_CHECK(track);
                track.frame = CGRectMake(0, height, width, 64);
                BOOL entry = !header.superview;
                if (entry) [page.view addSubview:header];
                [layout setNeedsLayout];
                [layout layoutIfNeeded];
                SGRHeaderInfo *info = (id)besideFind(header, @"SGRHeaderInfo");
                UIView *hero = besideFind(header, @"SGRPlaylistHero");
                HARNESS_CHECK(info.sgr_coverBeside && hero);
                [info layoutIfNeeded];
                CGRect art = [hero convertRect:hero.bounds toView:header];
                CGRect text = [info convertRect:info.bounds toView:header];
                HARNESS_CHECK(((UIImageView *)[hero valueForKey:@"picture"]).image && !CGRectIsEmpty(art));
                HARNESS_CHECK(CGRectContainsRect(header.bounds, art) && fabs(art.size.width - art.size.height) < 1);
                HARNESS_CHECK(CGRectContainsRect(header.bounds, text) && !CGRectIntersectsRect(art, text));
                for (UIView *v in info.subviews) {
                    if (v.hidden || !([v isKindOfClass:UIControl.class] || [v isKindOfClass:UILabel.class])) continue;
                    CGRect visible = [v convertRect:v.bounds toView:header];
                    HARNESS_CHECK(CGRectContainsRect(text, visible));
                    HARNESS_CHECK(CGRectGetMaxY(visible) <= [track convertPoint:CGPointZero toView:header].y);
                }
                if (entry) {
                    UIImageView *picture = [hero valueForKey:@"picture"];
                    HARNESS_CHECK(cover.layer.hidden && !picture.hidden);
                    SGSetEnabled(SGRKeyCoverBeside, NO);
                    [layout setNeedsLayout];
                    [layout layoutIfNeeded];
                    HARNESS_CHECK(!info.sgr_coverBeside && !cover.layer.hidden && !cover.layer.mask);
                    HARNESS_CHECK(picture.hidden);
                    SGSetEnabled(SGRKeyCoverBeside, YES);
                }
            }
            NSLog(@"[harness] PASS playlist landscape entry, portrait and rotation back to landscape");
            exit(0);
        });
        return YES;
    }
    [self.window makeKeyAndVisible];

    if ([NSProcessInfo.processInfo.arguments containsObject:@"cover-beside"]) {
        besideRun(self.window, page, page.view, @"Playlist", ^{
            [layout setNeedsLayout];
            [layout layoutIfNeeded];
        }, ^(NSString *text) {
            ((SPTFreeTierPlaylistEncoreHeaderViewController *)headerVC).headerController.defaultHeaderViewModel.playlistName = text;
        });
        return YES;
    }

    // The header collapsing, and the page pulled down past the top, with the frames Spotify sets in each
    // (trees/continuous/2.txt and 4.txt). The hero has to slide up out of the clipping view with the plane
    // the wash is on, not be resized into a strip at the top of the screen.
    void (^setState)(NSString *) = ^(NSString *state) {
        BOOL collapsed = [state isEqualToString:@"collapsed"];
        BOOL pulled = [state isEqualToString:@"pulled"];
        CGFloat layoutHeight = collapsed ? 110 : (pulled ? 608 : 474);
        header.frame = CGRectMake(0, collapsed ? -498 : (pulled ? 0 : -134), W, 608);
        headerLayout.frame = CGRectMake(0, collapsed ? 498 : (pulled ? 0 : 134), W, layoutHeight);
        clipping.frame = CGRectMake(0, 0, W, layoutHeight);
        background.frame = CGRectMake(0, 0, W, layoutHeight);
        background.alpha = collapsed ? 0 : 1;
        wash.frame = collapsed ? CGRectMake(0, -364, W, 474) : CGRectMake(0, 0, W, layoutHeight);
        safeArea.frame = CGRectMake(0, 0, W, layoutHeight);
        contentContainer.frame = CGRectMake(0, pulled ? 0 : -134, W, collapsed ? 244 : 608);
        contentView.frame = CGRectMake(0, 134, W, collapsed ? 110 : 474);
        layout.frame = CGRectMake(0, 0, W, collapsed ? 110 : 474);
        cover.frame = collapsed ? CGRectMake(148.67, 68, 104.67, 104.67) : CGRectMake(round((W - 243) / 2), 68, 243, 243);
        // The full bleed picture is clipped away rather than shrunk: collapsed it is the width of the page
        // and no height at all, with the picture inside it still at its own size (trees/continuous/3.txt:1066).
        fullbleed.frame = collapsed ? CGRectMake(0, 0, W, 0) : CGRectMake(0, 0, W, 311);
        block.frame = collapsed ? CGRectMake(0, -26.33, W - 16, 136.33) : CGRectMake(0, pulled ? 461 : 327, W - 16, pulled ? 220 : 178.33);
        [layout setNeedsLayout];
        [layout layoutIfNeeded];
        UIView *hero = wash.subviews.firstObject;
        UIImageView *picture = (UIImageView *)hero.subviews.firstObject;
        NSLog(@"[harness] state %@: hero %@ in the plane, %@ in the window, picture %@", state,
              NSStringFromCGRect(hero.frame), NSStringFromCGRect([wash convertRect:hero.frame toView:nil]),
              [picture isKindOfClass:UIImageView.class] && picture.image ? @"drawn" : @"EMPTY");
    };
    // `download` plays the download button's states instead of the header's (download-mock.h), with the page
    // left at rest and no sheet over it, for screenshots.
    BOOL downloads = [NSProcessInfo.processInfo.arguments containsObject:@"download"];
    if (downloads) {
        downloadScript();
        return YES;
    }
    // `other saved`: save becomes download once the playlist is saved, and save again once it is removed, each
    // change heard through the header controller's -update as on the phone (nothing is laid out).
    if ([NSProcessInfo.processInfo.arguments containsObject:@"saved"]) {
        at(2, ^{ NSLog(@"[harness] saved: before, Play's right shows \"%@\"", trailingLabel(page.view)); });
        at(2.5, ^{
            setAddTo(1);
            [(id)headerVC update];
        });
        at(3.2, ^{ NSLog(@"[harness] saved: saved, Play's right shows \"%@\"", trailingLabel(page.view)); });
        at(4.5, ^{
            setAddTo(0);
            [(id)headerVC update];
        });
        at(5.2, ^{ NSLog(@"[harness] saved: removed, Play's right shows \"%@\"", trailingLabel(page.view)); });
        at(6, ^{
            ((UIButton *)sgh_downloadButton).enabled = NO;
            setAddTo(1);
            [(id)headerVC update];
        });
        at(6.7, ^{ NSLog(@"[harness] saved: saved, download disabled, Play's right shows \"%@\"", trailingLabel(page.view)); });
        return YES;
    }
    // `veil` / `veil-off` (../album/hero-veil-check.h), instead of the scripted states: the list scrolls and the header
    // goes up with it, as at the start of a scroll on the phone; at rest the list is at its adjusted top inset.
    // `veil-card`: the veil is drawn on the picture in Spotify's own square, which only Spotify moves.
    NSString *veil = veilMode();
    if (veil) {
        CGRect rest = header.frame;
        BOOL card = [veil isEqualToString:@"veil-card"];
        UIView *root = page.view;
        veilRun(root, @"playlist", veil, NO, !card, 2.5, card ? ^UIView *(UIView *hero) {
            NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
            while (queue.count) {
                UIView *v = queue.firstObject;
                [queue removeObjectAtIndex:0];
                if ([v.accessibilityIdentifier isEqualToString:@"Components.Header.UI.ArtworkImage"]) return veilFind(v, @"UIImageView");
                [queue addObjectsFromArray:v.subviews];
            }
            return nil;
        } : nil, ^(CGFloat d) {
            header.frame = CGRectOffset(rest, 0, -MAX(0, d));
            list.contentOffset = CGPointMake(0, d - list.adjustedContentInset.top);
        });
        return YES;
    }
    for (NSUInteger i = 0; i < 3; i++) {
        NSString *state = @[@"rest", @"collapsed", @"pulled"][i];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((4 + i * 4) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            setState(state);
        });
    }

    // Spotify fading its cover square and its color wash back in as the header opens, which it does on the
    // scroll itself with nothing laid out: only the hook on that scroll sees it.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(16 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        setState(@"rest");
        cover.alpha = 1;
        gradient.alpha = 1;
        NSLog(@"[harness] Spotify's cover and wash faded back in");
        [(SPTFreeTierPlaylistEncoreHeaderViewController *)headerVC entityHeaderViewController:nil didUpdateVisibleRect:CGRectZero];
        NSLog(@"[harness] after Spotify's fade back in: cover a=%.2f layer.hidden=%d, wash a=%.2f layer.hidden=%d",
              cover.alpha, cover.layer.hidden, gradient.alpha, gradient.layer.hidden);
    });

    // The ⋯ the redesign pins over the page: outside the list and the header both, so it holds its place
    // while the header collapses and the list scrolls (issue #57). Tapped, it fires Spotify's own.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIView *pinned = nil;
        for (UIView *sub in page.view.subviews) {
            if ([NSStringFromClass(sub.class) isEqualToString:@"SGRMirrorButton"]) pinned = sub;
        }
        UIImageView *pinnedGlyph = nil;
        for (UIView *sub in pinned.subviews) {
            if ([sub isKindOfClass:UIImageView.class]) pinnedGlyph = (UIImageView *)sub;
        }
        NSLog(@"[harness] pinned more: %@ on the page, hidden=%d, glyph %@ tinted %@",
              pinned ? NSStringFromCGRect(pinned.frame) : @"MISSING", pinned.hidden,
              pinnedGlyph.image.renderingMode == UIImageRenderingModeAlwaysTemplate ? @"template" : @"as Spotify drew it",
              pinnedGlyph.tintColor);
        UIView *hit = [page.view hitTest:CGPointMake(CGRectGetMidX(pinned.frame), CGRectGetMidY(pinned.frame)) withEvent:nil];
        NSLog(@"[harness] pinned more takes the touch: %@", NSStringFromClass(hit.class));
        // The wash over the hero: its gradient concealed and its own black taken off, so the picture shows
        // through whether the Mix feature raised its alpha or not.
        NSLog(@"[harness] the plane's second wash: a=%.2f, paint a=%.0f, gradient %@", mixWash.alpha,
              mixWash.layer.backgroundColor ? CGColorGetAlpha(mixWash.layer.backgroundColor) : 0,
              mixGradient.layer.mask ? @"masked" : @"DRAWN");
        // The creator line: a tap on the name, nowhere else.
        UIView *info = nil;
        for (UIView *v = block; v; v = nil) {
            for (UIView *sub in v.subviews) if ([NSStringFromClass(sub.class) isEqualToString:@"SGRHeaderInfo"]) info = sub;
        }
        UIView *name = nil;
        for (UIView *sub in info.subviews) {
            if ([sub isKindOfClass:UILabel.class] && [((UILabel *)sub).text isEqualToString:@"The Weeknd"]) name = sub;
        }
        UIView *onName = [info hitTest:CGPointMake(CGRectGetMidX(name.bounds) + name.frame.origin.x, CGRectGetMidY(name.frame)) withEvent:nil];
        UIView *besideName = [info hitTest:CGPointMake(24, CGRectGetMidY(name.frame)) withEvent:nil];
        NSLog(@"[harness] creator line: on the name %@, beside it %@", onName ? NSStringFromClass(onName.class) : @"through",
              besideName ? NSStringFromClass(besideName.class) : @"through");
        for (UIGestureRecognizer *tap in name.gestureRecognizers) {
            [tap.view.superview performSelector:NSSelectorFromString(@"sgr_creatorTapped")];
        }
        // The list asks every cell how tall it wants to be, which is where the curation row answers 0 and
        // closes up: the harness's list is a plain scroll view, so it asks the way ListLayout does.
        if (handover) {
            UICollectionViewLayoutAttributes *wanted = [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:
                                                        [NSIndexPath indexPathForItem:0 inSection:0]];
            wanted.frame = curation.frame;
            CGSize answered = [(UICollectionViewCell *)curation preferredLayoutAttributesFittingAttributes:wanted].size;
            curation.frame = CGRectMake(0, curation.frame.origin.y, answered.width, answered.height);
            NSLog(@"[harness] the curation row answered %.0fpt tall", answered.height);
        }
    });

    // The ⋯ sheet: tapping the pinned button records the page, and the menu that opens a moment later takes
    // Sort and Mix into its table's header (issue #53). Then Sort is tapped, which has to fire Spotify's own
    // pill even though its cell is closed up to nothing.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIControl *pinnedMore = nil;
        for (UIView *sub in page.view.subviews) {
            if ([NSStringFromClass(sub.class) isEqualToString:@"SGRMirrorButton"]) pinnedMore = (UIControl *)sub;
        }
        [pinnedMore sendActionsForControlEvents:UIControlEventTouchDown];
        [pinnedMore sendActionsForControlEvents:UIControlEventTouchUpInside];
        _TtC24ContextMenu_InternalImpl25ContextMenuViewController *menu =
            [_TtC24ContextMenu_InternalImpl25ContextMenuViewController new];
        [page presentViewController:menu animated:NO completion:^{
            [menu.view setNeedsLayout];
            [menu.view layoutIfNeeded];
            [menu.table layoutIfNeeded];
            UIView *block = menu.table.tableHeaderView;
            NSMutableArray<NSString *> *rows = [NSMutableArray array];
            for (UIView *row in block.subviews) {
                if (!row.hidden) [rows addObject:[NSString stringWithFormat:@"%@ %@", row.accessibilityLabel,
                                                  NSStringFromCGRect(row.frame)]];
            }
            NSLog(@"[harness] the sheet's header is %@ %.0fpt: %@ (handover %d)",
                  block ? NSStringFromClass(block.class) : @"MISSING", block.bounds.size.height,
                  [rows componentsJoinedByString:@", "], handover);
            for (UIView *row in block.subviews) {
                if (!row.hidden) [(UIControl *)row sendActionsForControlEvents:UIControlEventTouchUpInside];
            }
        }];
    });

    // Spotify lays the column and the action row out again after the header's pass: their children go back
    // where its own layout put them, and the redesign has to take them again from its own watch on each.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSArray<NSValue *> *columnFrames = @[[NSValue valueWithCGRect:CGRectMake(0, 0, columnWidth, 29.67)],
                                             [NSValue valueWithCGRect:CGRectMake(0, 33.67, columnWidth, 31.33)],
                                             [NSValue valueWithCGRect:CGRectMake(0, 69, columnWidth, 34)],
                                             [NSValue valueWithCGRect:CGRectMake(0, 107, columnWidth, 15.33)]];
        for (NSUInteger i = 0; i < columnFrames.count && i < column.subviews.count; i++) {
            column.subviews[i].frame = columnFrames[i].CGRectValue;
        }
        shuffleView.frame = CGRectMake(20, 0, 48, 48);
        for (NSUInteger i = 0; i < actions.subviews.count; i++) {
            actions.subviews[i].frame = CGRectMake(i * 48, i == 0 ? 4 : 0, i == 0 ? 58 : 48, i == 0 ? 40 : 48);
        }
        [column setNeedsLayout];
        [actions setNeedsLayout];
        NSLog(@"[harness] Spotify's own frames put back");
    });

    // Pressing Play: Spotify reconfigures the header and shows the wash and the play disc again with
    // -setHidden:NO (trees/continuous/1.txt, 2026-09-18). They must stay drawn by nothing.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(17 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        gradient.hidden = NO;
        playButton.hidden = NO;
        cover.hidden = NO;
        NSLog(@"[harness] Pressing Play: wash hidden=%d masked=%d, disc hidden=%d masked=%d, cover hidden=%d masked=%d",
              gradient.hidden, gradient.layer.mask != nil, playButton.hidden, playButton.layer.mask != nil,
              cover.hidden, cover.layer.mask != nil);
    });
    if ([NSProcessInfo.processInfo.arguments containsObject:@"verify-actions"])
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            BOOL independent = (mix || [NSProcessInfo.processInfo.arguments containsObject:@"other"]) &&
                ![NSProcessInfo.processInfo.arguments containsObject:@"no-download"];
            verifyMixActions(page.view, independent);
        });
    return YES;
}

@end

// Before every %ctor, so the redesign's gate reads on.
__attribute__((constructor(101))) static void sgr_harnessDefaults(void) {
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"spotifyglass.redesign"];
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(SGRHarnessDelegate.class));
    }
}

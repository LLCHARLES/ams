// A mock of Spotify's album page under its own class names and accessibility identifiers, built from
// trees/clean/album/03.txt, so Redesigned/Album can be laid out and looked at on the Mac.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <AVFoundation/AVFoundation.h>
#import "../download-mock.h"
#import "Redesigned/Kit/SGRHeaderInfo.h"
#import "Redesigned/Kit/SGRTokens.h"
#import "Redesigned/Kit/SGRActionRow.h"
#import "Redesigned/Kit/SGRField.h"
#import <mach/mach.h>
#import "../harness-fail.h"
#import "Core/SGPrefs.h"
#import "motion-visibility.h"
#import "hero-veil-check.h"
#import "cover-fixtures.h"
#import "faces-check.h"
#import "more-check.h"
#import "Album.h"
#import "beside-check.h"
#import "layout-check.h"
#import "download-background-check.h"

// Download and ⋯ as one glass capsule: adjacent, level, one 88x44 shape (radius 22) under both, carried by
// download, ⋯ drawing none, its trailing edge 16pt in from the page's.
// The button's glass, first in its subviews; nil when it has never made one (its glyph is first then).
static UIView *glassOf(UIView *button) {
    UIView *glass=button.subviews.firstObject;
    return [glass isKindOfClass:UIImageView.class] ? nil : glass;
}
// `rtl`: the page laid out right to left, where the pair is mirrored: ⋯ 16pt in from the left edge, download on its
// right, the capsule the left-to-right one reflected across the page.
static void assertPinnedPair(UIView *page,SGRMirrorButton *download,SGRMirrorButton *more,BOOL rtl) {
    HARNESS_CHECK(!download.hidden && !more.hidden);
    CGFloat W=page.bounds.size.width;
    HARNESS_CHECK(fabs(rtl ? CGRectGetMinX(download.frame)-CGRectGetMaxX(more.frame) : CGRectGetMinX(more.frame)-CGRectGetMaxX(download.frame))<0.5);
    HARNESS_CHECK(fabs(CGRectGetMinY(more.frame)-CGRectGetMinY(download.frame))<0.5 && fabs(more.frame.size.height-download.frame.size.height)<0.5);
    HARNESS_CHECK(rtl ? fabs(CGRectGetMinX(more.frame)-16)<0.5 : fabs(CGRectGetMaxX(more.frame)-(W-16))<0.5);
    UIView *capsule=glassOf(download);
    HARNESS_CHECK(capsule && !capsule.hidden && (!glassOf(more) || glassOf(more).hidden));
    CGRect shape=[download convertRect:capsule.frame toView:page];
    HARNESS_CHECK(fabs(shape.size.width-88)<0.5 && fabs(shape.size.height-44)<0.5);
    HARNESS_CHECK(fabs(CGRectGetMinX(shape)-CGRectGetMinX(rtl ? more.frame : download.frame))<0.5);
    HARNESS_CHECK(fabs(CGRectGetMaxX(shape)-CGRectGetMaxX(rtl ? download.frame : more.frame))<0.5);
    HARNESS_CHECK(fabs(CGRectGetMinY(shape)-CGRectGetMinY(more.frame))<0.5);
    CGRect ltr=CGRectMake(W-16-88,CGRectGetMinY(more.frame),88,44);
    CGRect expected=rtl ? CGRectMake(W-CGRectGetMaxX(ltr),ltr.origin.y,88,44) : ltr;
    HARNESS_CHECK(fabs(shape.origin.x-expected.origin.x)<0.5 && fabs(shape.origin.y-expected.origin.y)<0.5);
    HARNESS_CHECK(capsule.layer.cornerRadius==0 || fabs(capsule.layer.cornerRadius-22)<0.5);
}

// The pinned pair on `page`: download by its identifier, ⋯ the other mirror button the page holds.
static void pinnedOn(UIView *page,SGRMirrorButton **download,SGRMirrorButton **more) {
    *download=nil;*more=nil;
    for(UIView *v in page.subviews){
        if(![v isKindOfClass:SGRMirrorButton.class])continue;
        if([v.accessibilityIdentifier isEqualToString:@"Retrine.Album.Download"])*download=(id)v;else *more=(id)v;
    }
}

// The page's first frames, plus a controlled hold once its pinned buttons are ready: on every
// frame drawn the pinned ⋯ is never its glyph alone. Either its own glass shows, or download's capsule is under it
// and covers it, download right under ⋯ in the page so that nothing -- the veil -- is between the two. Read after
// each Core Animation commit. `freeze` stops the main thread for 4 s on the first frame under the veil, so that a
// screenshot catches it. The verdict is logged and kept for verifyAlbumActions.
static BOOL sg_holdChecked,sg_holdPassed;
static dispatch_block_t sg_afterHold;
static void afterPinnedHold(dispatch_block_t action) {
    if (sg_holdChecked) {
        HARNESS_CHECK(sg_holdPassed);
        action();
    } else {
        sg_afterHold = [action copy];
    }
}
static void watchPinnedHold(UIView *page,BOOL freeze) {
    __block NSUInteger frames=0,veiled=0,onCapsule=0;
    __block BOOL failed=NO,frozen=!freeze,done=NO;
    __block CFTimeInterval start=0;
    __block SGRArtworkField *heldField=nil;
    __block BOOL observedHold=NO;
    const NSTimeInterval holdDeadlineSeconds=60;
    // Counted from the end of launch, not from here: building the page in didFinishLaunching takes ~9 s on a slow CI runner.
    dispatch_async(dispatch_get_main_queue(),^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(holdDeadlineSeconds*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
            if(!done)HARNESS_FAIL(@"pinned hold precondition timed out after %.0f s: %lu frames, %lu under the veil, controlled hold observed %d",
                                 holdDeadlineSeconds,(unsigned long)frames,(unsigned long)veiled,observedHold);
        });
    });
    CFRunLoopObserverRef observer=CFRunLoopObserverCreateWithHandler(NULL,kCFRunLoopBeforeWaiting|kCFRunLoopExit,true,2000001,^(CFRunLoopObserverRef obs,CFRunLoopActivity activity){
        if(done)return;
        SGRMirrorButton *download,*more;pinnedOn(page,&download,&more);
        if(!more || more.hidden || !more.window)return;
        if(!start)start=CACurrentMediaTime();
        UIView *veil=nil;
        for(UIView *v in page.subviews)if([NSStringFromClass(v.class) isEqualToString:@"SGRFieldVeil"])veil=v;
        // The launch's palette may release its veil before the first visible frame. Exercise the real
        // holdPage implementation after readiness instead of requiring that transient launch race.
        if(!veil && !heldField){
            heldField=[SGRArtworkField new];
            [heldField holdPage:page];
            for(UIView *v in page.subviews)if([NSStringFromClass(v.class) isEqualToString:@"SGRFieldVeil"])veil=v;
        }
        if(!veil && observedHold){
            done=YES;
            sg_holdChecked=YES;sg_holdPassed=!failed && veiled>0;
            NSLog(@"[harness] %@ pinned hold: %lu frames, %lu under the veil, %lu with ⋯ on download's capsule; ⋯ %@",sg_holdPassed?@"PASS":@"FAIL",
                  (unsigned long)frames,(unsigned long)veiled,(unsigned long)onCapsule,failed?@"was drawn without glass":@"never without glass");
            heldField=nil;
            HARNESS_CHECK(sg_holdPassed);
            dispatch_block_t action=sg_afterHold;sg_afterHold=nil;
            if(action)dispatch_async(dispatch_get_main_queue(),action);
            return;
        }
        frames++;
        if(veil)veiled++;
        // The veil itself: right under the pinned run (download, when the page has it, then ⋯), over everything else.
        if(veil && !failed){
            NSUInteger v=[page.subviews indexOfObjectIdenticalTo:veil],lowest=[page.subviews indexOfObjectIdenticalTo:more];
            if(download)lowest=MIN(lowest,[page.subviews indexOfObjectIdenticalTo:download]);
            if(v+1!=lowest){
                failed=YES;
                NSLog(@"[harness] FAIL pinned hold: frame %lu, the veil at %lu is not right under the pinned buttons (lowest at %lu)",(unsigned long)frames,(unsigned long)v,(unsigned long)lowest);
            }
        }
        UIView *own=glassOf(more);
        BOOL covered=own && !own.hidden;
        if(!covered && download && !download.hidden){
            UIView *capsule=glassOf(download);
            NSUInteger d=[page.subviews indexOfObjectIdenticalTo:download],m=[page.subviews indexOfObjectIdenticalTo:more];
            CGRect shape=capsule?[download convertRect:capsule.frame toView:page]:CGRectNull;
            covered=capsule && !capsule.hidden && d+1==m && CGRectContainsRect(CGRectInset(shape,-0.5,-0.5),more.frame);
            if(covered)onCapsule++;
        }
        if(!covered && !failed){
            failed=YES;
            NSMutableArray *order=[NSMutableArray array];
            for(UIView *v in page.subviews)[order addObject:v==more?@"more":v==download?@"download":NSStringFromClass(v.class)];
            NSUInteger n=MIN(order.count,(NSUInteger)4);
            NSLog(@"[harness] FAIL pinned hold: frame %lu at %.0f ms, ⋯ drawn without glass; the page's top subviews %@",(unsigned long)frames,
                  (CACurrentMediaTime()-start)*1000,[[order subarrayWithRange:NSMakeRange(order.count-n,n)] componentsJoinedByString:@" < "]);
        }
        if(!frozen && veil){
            frozen=YES;
            // The veil's fade, already running in the harness, which reads its cover before the window shows, is
            // paused where it is, so the frame stays the one a held page draws while the main thread waits.
            CALayer *layer=veil.layer;layer.timeOffset=[layer convertTime:CACurrentMediaTime() fromLayer:nil];layer.speed=0;
            [CATransaction flush];
            NSLog(@"[harness] first frame under the veil held 4 s for a screenshot, veil a=%.2f",layer.presentationLayer.opacity);
            [NSThread sleepForTimeInterval:4];
            layer.speed=1;layer.timeOffset=0;
        }
        if(veil && heldField && !observedHold){
            observedHold=YES;
            [heldField showPage];
        }
    });
    CFRunLoopAddObserver(CFRunLoopGetMain(),observer,kCFRunLoopCommonModes);
    CFRelease(observer);
}
static void assertPinnedAlone(SGRMirrorButton *download,SGRMirrorButton *more) {
    HARNESS_CHECK(download.hidden && !more.hidden);
    UIView *circle=glassOf(more);
    HARNESS_CHECK(circle && !circle.hidden && fabs(circle.bounds.size.width-44)<0.5 && fabs(circle.bounds.size.height-44)<0.5);
    HARNESS_CHECK(CGPointEqualToPoint(circle.center,CGPointMake(CGRectGetMidX(more.bounds),CGRectGetMidY(more.bounds))));
}

static void verifyAlbumActions(UIView *root) {
    NSMutableArray *pending=[NSMutableArray arrayWithObject:root];SGRHeaderInfo *info=nil;
    while(pending.count){UIView *v=pending.lastObject;[pending removeLastObject];
        if([v isKindOfClass:SGRHeaderInfo.class]){info=(id)v;break;}[pending addObjectsFromArray:v.subviews];}
    HARNESS_CHECK(info);
    SGRMirrorButton *shuffle=[info valueForKey:@"shuffle"],*add=[info valueForKey:@"trailing"];
    SGRPlayCapsule *play=[info valueForKey:@"play"];
    HARNESS_CHECK(add.source && !add.hidden && play.superview==info);
    for(UIView *v in info.subviews)HARNESS_CHECK(![v isKindOfClass:UIScrollView.class]);
    // The pinned download: on the page, just under the pinned ⋯ (the page's top subview), the two one capsule.
    SGRMirrorButton *download=nil;[pending setArray:@[root]];
    while(pending.count){UIView *v=pending.lastObject;[pending removeLastObject];
        if([v.accessibilityIdentifier isEqualToString:@"Retrine.Album.Download"]){download=(id)v;break;}[pending addObjectsFromArray:v.subviews];}
    HARNESS_CHECK([download isKindOfClass:SGRMirrorButton.class] && !download.hidden && download.source);
    UIView *page=download.superview;
    SGRMirrorButton *more=page.subviews.lastObject;
    HARNESS_CHECK([more isKindOfClass:SGRMirrorButton.class] && more!=download && !more.hidden);
    [page layoutIfNeeded];
    BOOL rtl=[NSProcessInfo.processInfo.arguments containsObject:@"rtl"];
    UIView *shapeView=glassOf(download);
    NSLog(@"[harness] pinned frames %@: download %@, more %@, capsule %@",rtl?@"rtl":@"ltr",NSStringFromCGRect(download.frame),
          NSStringFromCGRect(more.frame),shapeView?NSStringFromCGRect([download convertRect:shapeView.frame toView:page]):@"none");
    HARNESS_CHECK((page.effectiveUserInterfaceLayoutDirection==UIUserInterfaceLayoutDirectionRightToLeft)==rtl);
    HARNESS_CHECK(sg_holdChecked && sg_holdPassed);
    assertPinnedPair(page,download,more,rtl);
    NSLog(@"[harness] PASS pinned capsule %@: 88x44 at %@, 16pt in from the %@ edge%@",rtl?@"rtl":@"ltr",
          NSStringFromCGRect([download convertRect:shapeView.frame toView:page]),rtl?@"left":@"right",rtl?@", the left-to-right frame mirrored":@"");
    // Download gone: ⋯ alone, its own circle, nothing left of the capsule; back again, the capsule again.
    UIView *nativeDownload=download.source,*row=nativeDownload.superview;NSUInteger slot=[row.subviews indexOfObject:nativeDownload];
    // The header's pass and the page's are what draw the pinned pair, so everything from the row up lays out.
    void (^relayout)(void)=^{for(UIView *v=row;v;v=v.superview)[v setNeedsLayout];[root layoutIfNeeded];[page layoutIfNeeded];};
    [nativeDownload removeFromSuperview];
    relayout();
    assertPinnedAlone(download,more);
    if([row isKindOfClass:UIStackView.class])[(UIStackView *)row insertArrangedSubview:nativeDownload atIndex:slot];
    else [row insertSubview:nativeDownload atIndex:slot];
    relayout();
    assertPinnedPair(page,download,more,rtl);
    CGRect original=info.frame;
    for(NSNumber *width in @[@430,@390,@320]){
        CGRect frame=original;frame.size.width=width.doubleValue;info.frame=frame;
        [info setNeedsLayout];[info layoutIfNeeded];
        // Shuffle, Play, add: Play on the middle of the page, the other two 16pt off its sides.
        HARNESS_CHECK(fabs(CGRectGetMidX(play.frame)-width.doubleValue/2)<1);
        HARNESS_CHECK(fabs(CGRectGetMinX(play.frame)-CGRectGetMaxX(shuffle.frame)-16)<1);
        HARNESS_CHECK(fabs(CGRectGetMinX(add.frame)-CGRectGetMaxX(play.frame)-16)<1);
        HARNESS_CHECK(CGRectGetMinX(shuffle.frame)>=0 && CGRectGetMaxX(add.frame)<=width.doubleValue);
    }
    info.frame=original;[info setNeedsLayout];[info layoutIfNeeded];
    // Play's word changing ("Play" to "Shuffle Play") lays the header out again: a wider capsule, still centered.
    CGFloat playBefore=play.bounds.size.width;NSString *word=play.source.accessibilityLabel;
    play.source.accessibilityLabel=@"Shuffle Play";[play feedFrom:play.source];
    [info layoutIfNeeded];
    HARNESS_CHECK(play.bounds.size.width>playBefore+1 && fabs(CGRectGetMidX(play.frame)-info.bounds.size.width/2)<1);
    HARNESS_CHECK(fabs(CGRectGetMinX(add.frame)-CGRectGetMaxX(play.frame)-16)<1);
    play.source.accessibilityLabel=word;[play feedFrom:play.source];[info layoutIfNeeded];
    HARNESS_CHECK(fabs(play.bounds.size.width-playBefore)<1);
    UIControl *source=(UIControl *)download.source;__block NSUInteger fired=0;
    UIAction *action=[UIAction actionWithTitle:@"verify" image:nil identifier:@"verify-album-download" handler:^(UIAction *a){fired++;}];
    [source addAction:action forControlEvents:UIControlEventTouchUpInside];
    [download sendActionsForControlEvents:UIControlEventTouchUpInside];
    [source removeActionForIdentifier:@"verify-album-download" forControlEvents:UIControlEventTouchUpInside];
    HARNESS_CHECK(fired==1);
    NSDictionary *result=@{@"passed":@YES,@"album_add_and_pinned_download_visible":@YES,@"native_download_action_calls":@(fired),@"checked_widths":@[@430,@390,@320],@"play_word_relayout":@YES};
    NSString *path=[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject stringByAppendingPathComponent:@"album-actions-verification.json"];
    [[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil]writeToFile:path atomically:YES];
    NSLog(@"[harness] PASS album controls: shuffle | Play | add with Play centered at 430/390/320, download and ⋯ one 88x44 glass capsule 16pt in, ⋯ its own circle without download, native action once, Play's word relays out the header");
}

#pragma mark - Spotify's classes, by name

@interface _TtC28CreativeWorkPlatform_PageKit24CreativeWorkTemplateView : UIView @end
@implementation _TtC28CreativeWorkPlatform_PageKit24CreativeWorkTemplateView @end

@interface _TtC32CreativeWorkPlatform_TemplateKit28CreativeWorkTemplateListView : UIView @end
@implementation _TtC32CreativeWorkPlatform_TemplateKit28CreativeWorkTemplateListView @end

@interface _TtCO19LegacyUI_ECMCoreKit5Views10HeaderView : UIView @end
@implementation _TtCO19LegacyUI_ECMCoreKit5Views10HeaderView @end

@interface _TtC28EncoreConsumerMobile_BaseKit20HeaderNavigationBar : UIView @end
@implementation _TtC28EncoreConsumerMobile_BaseKit20HeaderNavigationBar @end

// Spotify's draws a CAGradientLayer; whether it is the view's own layer is what the device log settles.
@interface _TtC19LegacyUI_ECMCoreKit12GradientView : UIView @end
@implementation _TtC19LegacyUI_ECMCoreKit12GradientView
+ (Class)layerClass { return CAGradientLayer.class; }
@end

@interface _TtC28EncoreConsumerMobile_BaseKit14PlayButtonView : UIView @end
@implementation _TtC28EncoreConsumerMobile_BaseKit14PlayButtonView @end

@interface _TtC12Element_List18CollectionViewCell : UICollectionViewCell
// The text size the cell reports, so a check can change it under a settled cell the way Settings does.
- (void)sg_setTextSize:(NSString *)category;
@end
@implementation _TtC12Element_List18CollectionViewCell {
    UITraitCollection *_sgTextSize;
}
- (UITraitCollection *)traitCollection {
    return _sgTextSize ?: [super traitCollection];
}
- (void)sg_setTextSize:(NSString *)category {
    _sgTextSize = category ? [UITraitCollection traitCollectionWithPreferredContentSizeCategory:category] : nil;
}
@end

// The element the cell's content is, which is the only thing that says what a cell holds.
@interface MockRetrievalListStructuredDataView : UIView @end
@implementation MockRetrievalListStructuredDataView @end

@interface SGAlbumQueuePage : NSObject @end
@implementation SGAlbumQueuePage
+ (NSString *)albumURI:(id)controller {
    return [NSProcessInfo.processInfo.arguments containsObject:@"ordinal-layout"] ? @"spotify:album:0000000000000000000001" : nil;
}
@end

@interface MockAlbum_PageImpl20FooterStructuredDataView : UIView @end
@implementation MockAlbum_PageImpl20FooterStructuredDataView @end

@interface MockCondensedButton : UIControl @end
@implementation MockCondensedButton @end

@interface MockEncoreButton : UIControl @end
@implementation MockEncoreButton @end

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
    inner.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    inner.accessibilityIdentifier = [identifier stringByAppendingString:@"-internal"];
    [encore addSubview:inner];
    return inner;
}

static UIView *byIdentifier(UIView *root, NSString *identifier) {
    if ([root.accessibilityIdentifier isEqualToString:identifier]) return root;
    for (UIView *sub in root.subviews) {
        UIView *found = byIdentifier(sub, identifier);
        if (found) return found;
    }
    return nil;
}

static UIImage *artwork(void) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(300, 300)];
    // The scanner's pale border along the bottom is all the Kit's palette reads.
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) { drawScannedSleeve(ctx.CGContext, 300); }];
}

// `-coverFixture <name>` on the launch line: one of cover-fixtures.h's covers instead of the scanned sleeve.
static UIImage *harnessCover(void) {
    NSString *name = [NSUserDefaults.standardUserDefaults stringForKey:@"coverFixture"];
    if (!name) return artwork();
    UIImage *(*make)(void) = NULL;
    if ([name isEqualToString:@"colourful"]) make = colourfulCover;
    else if ([name isEqualToString:@"portrait"]) make = faceCover;
    else if ([name isEqualToString:@"darkAccent"]) make = darkAccentCover;
    else if ([name isEqualToString:@"solidLight"]) make = solidLightCover;
    else if ([name isEqualToString:@"solidDark"]) make = solidDarkCover;
    else if ([name isEqualToString:@"darkPortrait"]) make = darkPortraitCover;
    if (!make) HARNESS_FAIL(@"no cover fixture %@", name);
    return make();
}

// `cover-stats`: at 6 s the process's memory, its footprint now and at its peak, and a SHOT line for a screenshot.
static void logCoverStats(void) {
    NSString *raw = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject
                     stringByAppendingPathComponent:@"cover-fixture.png"];
    HARNESS_CHECK([UIImagePNGRepresentation(harnessCover()) writeToFile:raw atomically:YES]);
    task_vm_info_data_t info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) != KERN_SUCCESS) HARNESS_FAIL(@"no task info");
    NSLog(@"[harness] cover memory: footprint %.1f MB, peak %.1f MB", info.phys_footprint / 1048576.0, info.ledger_phys_footprint_peak / 1048576.0);
    NSLog(@"[harness] SHOT album-cover-%@-%@", [NSUserDefaults.standardUserDefaults stringForKey:@"coverFixture"] ?: @"sleeve",
          [NSUserDefaults.standardUserDefaults boolForKey:@"spotifyglass.redesign.album.adaptiveCover"] ? @"on" : @"off");
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

// One of the round buttons of the header's action row: the element view Spotify's stack arranges, the
// button inside it at the same size, and a glyph in the button.
static UIView *actionButton(UIView *row, CGRect frame, NSString *identifier, NSString *symbol, NSString *a11y) {
    UIView *element = box(row, UIView.class, frame, nil);
    // Drawn by Lottie, its state in its identifier and in the Encore object behind it (issue #65).
    if ([identifier hasPrefix:@"DownloadButton.Granular."]) {
        mockDownloadButton(element);
        return element;
    }
    if ([identifier isEqualToString:@"Components.UI.AddToButton"]) {
        mockAddToButton(element);
        return element;
    }
    UIView *button = box(element, MockEncoreButton.class, element.bounds, identifier);
    button.accessibilityLabel = a11y;
    UIImageView *glyph = [[UIImageView alloc] initWithFrame:CGRectInset(button.bounds, 12, 12)];
    glyph.image = [UIImage systemImageNamed:symbol];
    glyph.tintColor = UIColor.whiteColor;
    [button addSubview:glyph];
    return element;
}

#pragma mark - the metadata row's cells

@interface SGRMetaSource : NSObject <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic, copy) NSArray<NSString *> *items;
@end

@implementation SGRMetaSource

- (NSInteger)collectionView:(UICollectionView *)view numberOfItemsInSection:(NSInteger)section {
    return self.items.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)view cellForItemAtIndexPath:(NSIndexPath *)path {
    UICollectionViewCell *cell = [view dequeueReusableCellWithReuseIdentifier:@"meta" forIndexPath:path];
    for (UIView *old in cell.contentView.subviews) [old removeFromSuperview];
    label(cell.contentView, cell.contentView.bounds, self.items[path.item], 11,
          [UIColor colorWithWhite:0.70 alpha:1], @"Encore.Label");
    return cell;
}

- (CGSize)collectionView:(UICollectionView *)view layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)path {
    CGSize text = [self.items[path.item] sizeWithAttributes:@{NSFontAttributeName: [UIFont systemFontOfSize:11]}];
    return CGSizeMake(ceil(text.width), 15.33);
}

@end

// What the redesign's row shows on Play's right: the label of the Kit's last round button, the trailing one.
static UIControl *trailingButton(UIView *root) {
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        if ([NSStringFromClass(v.class) isEqualToString:@"SGRHeaderInfo"]) {
            UIControl *trailing = nil;
            for (UIView *sub in v.subviews) {
                if ([NSStringFromClass(sub.class) isEqualToString:@"SGRMirrorButton"]) trailing = (UIControl *)sub;
            }
            return trailing;
        }
        [stack addObjectsFromArray:v.subviews];
    }
    return nil;
}

// The trailing button's label and the symbol it draws.
static NSString *trailingState(UIView *root) {
    UIControl *trailing = trailingButton(root);
    UIImageView *glyph = nil;
    for (UIView *sub in trailing.subviews) {
        if ([sub isKindOfClass:UIImageView.class] && !sub.hidden) glyph = (UIImageView *)sub;
    }
    return [NSString stringWithFormat:@"\"%@\" %@ tint %@", trailing.accessibilityLabel, glyph.image, glyph.tintColor];
}

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

#pragma mark - the page

@interface SGRHarnessDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) SGRMetaSource *meta;
@end

@implementation SGRHarnessDelegate {
    UIView *_titleBlock, *_titleStack, *_actionRow, *_metaCells;
    NSMutableArray<UIView *> *_actionItems;
    NSMutableArray<NSValue *> *_actionFrames;
    NSMutableArray<_TtC12Element_List18CollectionViewCell *> *_footerCells;
    UIView *_listView;
    CGFloat _tracksBottom;
    UIView *_baseCard, *_greyCard;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    if ([NSProcessInfo.processInfo.arguments containsObject:@"motion-visibility"]) {
        self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        motionVisibilityCheck(self.window, NO);
        return YES;
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"download-background"]) {
        self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        self.window.rootViewController = [UIViewController new];
        [self.window makeKeyAndVisible];
        dispatch_async(dispatch_get_main_queue(), ^{
            downloadBackgroundChecks(self.window);
            exit(0);
        });
        return YES;
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"cover-beside"])
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:SGRKeyCoverBeside];
    layoutPrepare();
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    CGFloat W = self.window.bounds.size.width, H = self.window.bounds.size.height;
    CGFloat fixtureWidth = [NSUserDefaults.standardUserDefaults doubleForKey:@"header-width"];
    if (fixtureWidth > 0) W = fixtureWidth;

    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1];
    self.window.rootViewController = root;

    UIView *page = box(root.view, _TtC28CreativeWorkPlatform_PageKit24CreativeWorkTemplateView.class,
                       CGRectMake(0, 0, W, H), @"CreativeWorkPlatform.CreativeWorkTemplateView");
    // `rtl`: the page laid out right to left, as in Arabic or Hebrew; `freeze`: its first frame under the veil held.
    if ([NSProcessInfo.processInfo.arguments containsObject:@"rtl"])
        page.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    watchPinnedHold(page, [NSProcessInfo.processInfo.arguments containsObject:@"freeze"]);

    // Spotify's color wash behind the header, the height of the header at rest.
    UIView *wash = box(page, _TtCO19LegacyUI_ECMCoreKit5Views10HeaderView.class, CGRectMake(0, 0, W, 486.67), nil);
    UIView *gradient = box(wash, _TtC19LegacyUI_ECMCoreKit12GradientView.class, wash.bounds, nil);
    // The color Spotify read off the whole cover, down to its base surface.
    ((CAGradientLayer *)gradient.layer).colors = @[(id)[UIColor colorWithRed:0.29 green:0.22 blue:0.62 alpha:1].CGColor,
                                                   (id)[UIColor colorWithRed:0.07 green:0.07 blue:0.07 alpha:1].CGColor];

    // the tab, the scroll and the stack the header and the list sit in
    UIView *tab = box(page, UIView.class, CGRectMake(0, 0, W, H), @"CreativeWorkPlatform.Tab");
    // The fixture combines PCFF's scrolling owner and its mirrored content host in one view.
    UIScrollView *scroll = (UIScrollView *)box(tab, UIScrollView.class, CGRectMake(0, 0, W, H), @"PCFFTabLayoutViewController.overlayScrollView");
    // Spotify's starts its content at the very top of the page, under the status bar.
    scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    UIStackView *stack = (UIStackView *)box(scroll, UIStackView.class, CGRectMake(0, 0, W, 2200), nil);

    UIView *headerElement = box(stack, UIView.class, CGRectMake(0, 0, W, 486.67), @"CreativeWorkPlatform.Header");
    UIView *header = box(headerElement, UIView.class, headerElement.bounds, @"CreativeWorkPlatform.Components.UI.CreativeWorkHeader");
    UIView *inset = box(header, UIView.class, CGRectMake(0, 78, W, 400.67), nil);
    UIStackView *outer = (UIStackView *)box(inset, UIStackView.class, inset.bounds, nil);

    UIView *topGroup = box(outer, UIView.class, CGRectMake(0, 0, W, 321.33), nil);
    UIStackView *groupStack = (UIStackView *)box(topGroup, UIStackView.class, topGroup.bounds, nil);

    // `-coverTop <pt>`: Spotify's square that far down the header instead of right under its top inset, where a phone
    // measured it (layout-check.h's chrome cases).
    NSUserDefaults *launch = NSUserDefaults.standardUserDefaults;
    CGFloat coverTop = [launch objectForKey:@"coverTop"] ? [launch doubleForKey:@"coverTop"] : CGRectGetMinY(inset.frame);
    UIView *artRow = box(groupStack, UIView.class, CGRectMake(0, coverTop - CGRectGetMinY(inset.frame), W, 248), nil);
    UIView *coverElement = box(artRow, UIView.class, CGRectMake(round((W - 248) / 2), 0, 248, 248), nil);
    UIView *cover = box(coverElement, UIView.class, coverElement.bounds, @"CreativeWorkPlatform.Components.UI.ArtWorkElement.WithCoverArt");
    UIImageView *coverPicture = [[UIImageView alloc] initWithFrame:cover.bounds];
    coverPicture.image = harnessCover();
    coverPicture.contentMode = UIViewContentModeScaleAspectFill;
    coverPicture.clipsToBounds = YES;
    coverPicture.accessibilityIdentifier = @"Encore.ImageView";
    [cover addSubview:coverPicture];
    box(groupStack, UIView.class, CGRectMake(0, 256, 0, 0), nil);

    _titleBlock = box(groupStack, UIView.class, CGRectMake(0, 264, 215.33, 57.33), nil);
    _titleStack = box(_titleBlock, UIStackView.class, CGRectMake(16, 0, 183.33, 57.33), nil);
    label(_titleStack, CGRectZero, @"", 17, UIColor.whiteColor, @"CreativeWorkPlatform.Components.UI.PreTitleRow");
    BOOL shortTitle = [NSProcessInfo.processInfo.arguments containsObject:@"short-title"];
    UILabel *albumTitle = label(_titleStack, CGRectMake(0, 0, 183.33, 25.33), shortTitle ? @"X" : @"Hurry Up Tomorrow", 21, UIColor.whiteColor,
          @"CreativeWorkPlatform.Components.UI.TitleRow");
    UIView *parentElement = box(_titleStack, UIView.class, CGRectMake(0, 33.33, 96, 24), nil);
    UIView *parentRow = box(parentElement, MockEncoreButton.class, parentElement.bounds, @"CreativeWorkPlatform.Components.UI.ParentRow");
    parentRow.accessibilityLabel = @"The Weeknd";
    UIImageView *avatar = (UIImageView *)box(parentRow, UIImageView.class, CGRectMake(0, 0, 24, 24), @"Encore.ImageView");
    avatar.backgroundColor = [UIColor colorWithWhite:0.8 alpha:1];
    avatar.layer.cornerRadius = 12;
    // The artist's picture lands at 1.5 s, after the header has laid out; at 2.2 s the log says where the
    // redesign drew it.
    // Both phone geometry measurements use the pre-avatar capture.
    BOOL phoneFrames = [NSProcessInfo.processInfo.arguments containsObject:@"cover-beside"] &&
                       [NSProcessInfo.processInfo.arguments containsObject:@"-header-width"];
    if (!phoneFrames) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        avatar.image = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(48, 48)] imageWithActions:^(UIGraphicsImageRendererContext *c) {
            [UIColor.orangeColor setFill];
            UIRectFill(CGRectMake(0, 0, 48, 48));
        }];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIView *info = nil;
        for (UIView *v = avatar; v && !info; v = v.superview) {
            for (UIView *sub in v.subviews) {
                if ([NSStringFromClass(sub.class) isEqualToString:@"SGRHeaderInfo"]) info = sub;
            }
        }
        UIView *picture = nil, *name = nil;
        for (UIView *sub in info.subviews) {
            // The artists' faces sit in a plain view of their own.
            NSArray<UIView *> *candidates = [sub isMemberOfClass:UIView.class] && !sub.hidden ? sub.subviews : @[sub];
            for (UIView *v in candidates) {
                if ([v isKindOfClass:UIImageView.class] && !v.hidden && ((UIImageView *)v).image) picture = v;
            }
            if ([sub isKindOfClass:UILabel.class] && [((UILabel *)sub).text isEqualToString:@"The Weeknd"]) name = sub;
        }
        NSLog(@"[harness] artist picture: %@, name at %@", picture ? NSStringFromCGRect([picture convertRect:picture.bounds toView:info]) : @"none",
              NSStringFromCGRect(name.frame));
    });
    UILabel *artistName = label(parentRow, CGRectMake(32, 4.33, 72, 15.33), @"The Weeknd", 11, UIColor.whiteColor, @"Encore.Label");

    UIView *bottomGroup = box(outer, UIView.class, CGRectMake(0, 329.33, W, 71.33), nil);
    UIStackView *bottomStack = (UIStackView *)box(bottomGroup, UIStackView.class, bottomGroup.bounds, nil);

    UIView *metaWrap = box(bottomStack, UIView.class, CGRectMake(0, 0, W, 15.33), nil);
    UIStackView *metaStack = (UIStackView *)box(metaWrap, UIStackView.class, CGRectMake(16, 0, W - 32, 15.33), nil);
    UIView *metaElement = box(metaStack, UIView.class, metaStack.bounds, nil);
    UIView *metadata = box(metaElement, UIView.class, metaElement.bounds, @"Components.UI.MetadataRow");
    UICollectionViewFlowLayout *flow = [UICollectionViewFlowLayout new];
    flow.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    flow.minimumInteritemSpacing = 4;
    UICollectionView *cells = [[UICollectionView alloc] initWithFrame:metadata.bounds collectionViewLayout:flow];
    cells.backgroundColor = UIColor.clearColor;
    [cells registerClass:UICollectionViewCell.class forCellWithReuseIdentifier:@"meta"];
    self.meta = [SGRMetaSource new];
    self.meta.items = @[@"Album", @"•", @"31. 1. 2025"];
    cells.dataSource = self.meta;
    cells.delegate = self.meta;
    [metadata addSubview:cells];
    _metaCells = cells;

    _actionRow = box(bottomStack, UIStackView.class, CGRectMake(0, 23.33, 206, 48), nil);
    _actionItems = [NSMutableArray array];
    _actionFrames = [NSMutableArray array];
    NSArray *actions = @[@[@"Components.UI.WatchFeedEntityExplorerButton", @"play.rectangle", @"Explore", @0, @4, @62, @40],
                         @[@"Components.UI.AddToButton", @"plus", @"Add", @62, @0, @48, @48],
                         @[@"DownloadButton.Granular.None", @"arrow.down.circle", @"Download", @110, @0, @48, @48],
                         @[@"Components.UI.ContextMenuButton-3OxfaVgvTxUTy7276t7SPU", @"ellipsis", @"More options", @158, @0, @48, @48]];
    // `late` on the launch line: add is not in the row yet, the way an album opened for the first time has it.
    BOOL late = [NSProcessInfo.processInfo.arguments containsObject:@"late"];
    // `download`: an album without add (the row's download is what Play's right shows then), playing the
    // download button's states (download-mock.h).
    BOOL downloads = [NSProcessInfo.processInfo.arguments containsObject:@"download"];
    for (NSArray *action in actions) {
        if ((late || downloads) && [action[0] isEqualToString:@"Components.UI.AddToButton"]) continue;
        CGRect frame = CGRectMake([action[3] doubleValue], [action[4] doubleValue], [action[5] doubleValue], [action[6] doubleValue]);
        [_actionItems addObject:actionButton(_actionRow, frame, action[0], action[1], action[2])];
        [_actionFrames addObject:[NSValue valueWithCGRect:frame]];
    }

    // the track list under the header
    _listView = box(stack, _TtC32CreativeWorkPlatform_TemplateKit28CreativeWorkTemplateListView.class,
                    CGRectMake(0, 486.67, W, 700), nil);
    _listView.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1];
    UIView *collection = box(_listView, UIView.class, _listView.bounds, nil);
    collection.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1];

    // The third column: E for a row with Spotify's explicit badge, a label-backed view beside the artist line.
    // The artists the redesign drops are the ones that only repeat the header's The Weeknd; Justice named with
    // no "feat." and Playboi Carti with no mention at all keep theirs.
    NSArray<NSArray<NSString *> *> *tracks = @[@[@"Wake Me Up (feat. Justice)", @"The Weeknd, Justice", @"E"],
                                               @[@"Cry For Me", @"The Weeknd", @""],
                                               @[@"I Can't Fucking Sing", @"The Weeknd", @"E"],
                                               @[@"São Paulo (feat. Anitta)", @"The Weeknd, Anitta", @"E"],
                                               @[@"Until We're Skin & Bones", @"The Weeknd", @""],
                                               @[@"Timeless Justice", @"The Weeknd, Justice", @""],
                                               @[@"Timeless", @"The Weeknd, Playboi Carti", @"E"],
                                               @[@"A Title Long Enough To Run Under The Badge And Beyond", @"The Weeknd", @"E"],
                                               @[@"Baptized In Fear", @"The Weeknd", @""]];
    CGFloat y = 8;
    NSMutableArray<UICollectionViewCell *> *trackCells = [NSMutableArray array];
    for (NSArray<NSString *> *track in tracks) {
        UICollectionViewCell *cell = [[_TtC12Element_List18CollectionViewCell alloc] initWithFrame:CGRectMake(0, y, W, 56)];
        cell.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1];
        [collection addSubview:cell];
        UIView *content = box(cell.contentView, MockRetrievalListStructuredDataView.class, cell.contentView.bounds, nil);
        UIView *row = box(content, UIView.class, content.bounds, @"Components.UI.RetrievalRowElementUI");
        row.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1];
        UILabel *constrainedTitle = label(row, CGRectMake(16, 8, W - 90, 18), track[0], 13, UIColor.whiteColor, @"EncoreConsumerMobile.View.Granular.Title");
        if ([NSProcessInfo.processInfo.arguments containsObject:@"ordinal-layout"]) {
            UIView *owner = constrainedTitle.superview;
            constrainedTitle.translatesAutoresizingMaskIntoConstraints = NO;
            [NSLayoutConstraint activateConstraints:@[
                [constrainedTitle.leadingAnchor constraintEqualToAnchor:owner.leadingAnchor],
                [constrainedTitle.trailingAnchor constraintEqualToAnchor:owner.trailingAnchor],
                [constrainedTitle.topAnchor constraintEqualToAnchor:owner.topAnchor],
                [constrainedTitle.bottomAnchor constraintEqualToAnchor:owner.bottomAnchor],
            ]];
        }
        CGFloat artistX = 16;
        if (track[2].length) {
            UIView *badge = box(row, UIView.class, CGRectMake(16, 31, 13, 13), @"Components.UI.ExplicitIcon");
            badge.backgroundColor = [UIColor colorWithWhite:0.7 alpha:1];
            badge.layer.cornerRadius = 2;
            UILabel *e = [[UILabel alloc] initWithFrame:badge.bounds];
            e.text = @"E";
            e.font = [UIFont boldSystemFontOfSize:9];
            e.textAlignment = NSTextAlignmentCenter;
            e.textColor = UIColor.blackColor;
            [badge addSubview:e];
            artistX = 33;
        }
        label(row, CGRectMake(artistX, 30, W - 74 - artistX, 15.33), track[1], 11, UIColor.whiteColor, @"EncoreConsumerMobile.View.Granular.Subtitle");
        actionButton(row, CGRectMake(W - 64, 4, 48, 48), @"Components.UI.ContextMenuButton-5673WA8EEUSPx1ir26lhGW", @"ellipsis", @"More options");
        [trackCells addObject:cell];
        y += 56;
    }
    _tracksBottom = y;
    if ([NSProcessInfo.processInfo.arguments containsObject:@"ordinal-layout"]) layoutWhen(@"ordinal track cell mounted", ^BOOL { return trackCells[2].window != nil; }, ^{
        UICollectionViewCell *cell = trackCells[2];
        UILabel *title = (id)byIdentifier(cell, @"EncoreConsumerMobile.View.Granular.Title-internal");
        UIView *owner = title.superview, *row = owner.superview;
        UILabel *number = nil;
        for (UIView *v in row.subviews) if ([v isKindOfClass:UILabel.class] && [((UILabel *)v).text isEqual:@"1"]) number = (UILabel *)v;
        HARNESS_CHECK(number && [title.text isEqual:tracks[2][0]]);
        BOOL translatedPass = [NSProcessInfo.processInfo.arguments containsObject:@"ordinal-translated"];
        CGAffineTransform credit = title.transform;
        if (translatedPass) {
            HARNESS_CHECK(credit.ty != 0 && SGEnabled(SGRKeyAlbumHideTrackArtists));
            // Exercise the same constraint solution at another vertical translation. Neither
            // changing it nor restoring it should change the title's underlying layout position.
            title.transform = CGAffineTransformTranslate(credit, 0, 3);
        }
        // A new constraint solution in the title's owner, without a layout pass of the cell.
        NSLayoutConstraint *edge = owner.constraints.firstObject;
        edge.constant += 1;
        [owner layoutIfNeeded];
        edge.constant -= 1;
        [owner layoutIfNeeded];
        if (translatedPass) {
            HARNESS_CHECK(CGAffineTransformEqualToTransform(title.transform, CGAffineTransformTranslate(credit, 0, 3)));
            title.transform = credit;
            CGFloat delta = CGRectGetMidY([title convertRect:title.bounds toView:row]) - CGRectGetMidY(row.bounds);
            if (fabs(delta) > 0.5) HARNESS_FAIL(@"translated title displaced %.2f pt after constraint pass", delta);
        }
        CGRect drawn = [title convertRect:title.bounds toView:row];
        BOOL rtl = row.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
        CGFloat gap = rtl ? CGRectGetMinX(number.frame) - CGRectGetMaxX(drawn) : CGRectGetMinX(drawn) - CGRectGetMaxX(number.frame);
        if (gap < 5.5) HARNESS_FAIL(@"ordinal overlaps constrained title: gap %.2f", gap);
        HARNESS_CHECK(!number.isAccessibilityElement && !number.userInteractionEnabled);
        UIView *menu = byIdentifier(row, @"Components.UI.ContextMenuButton-5673WA8EEUSPx1ir26lhGW");
        HARNESS_CHECK(menu.userInteractionEnabled && !menu.hidden);
        if (SGEnabled(SGRKeyAlbumHideTrackArtists)) {
            HARNESS_CHECK(byIdentifier(row, @"EncoreConsumerMobile.View.Granular.Subtitle").alpha == 0);
            HARNESS_CHECK(byIdentifier(row, @"Components.UI.ExplicitIcon").alpha == 0);
            UIImageView *drawnBadge = nil;
            for (UIView *v in row.subviews) if ([v isKindOfClass:UIImageView.class]) drawnBadge = (id)v;
            HARNESS_CHECK(drawnBadge.image && fabs(CGRectGetMidY(number.frame) - CGRectGetMidY(drawn)) < 1);
            CGFloat textWidth = ceil([title textRectForBounds:title.bounds limitedToNumberOfLines:1].size.width);
            CGFloat badgeGap = rtl ? CGRectGetMaxX(drawn) - textWidth - CGRectGetMaxX(drawnBadge.frame) :
                CGRectGetMinX(drawnBadge.frame) - CGRectGetMinX(drawn) - textWidth;
            HARNESS_CHECK(fabs(badgeGap - 4) < 1);
        }
        if ([NSProcessInfo.processInfo.arguments containsObject:@"ordinal-count"]) {
            UILabel *count = nil;
            for (UIView *v in row.subviews) if ([v isKindOfClass:UILabel.class] && v != number) count = (id)v;
            HARNESS_CHECK(count.text.length && !CGRectIntersectsRect(count.frame, drawn) &&
                          !CGRectIntersectsRect(count.frame, menu.frame));
        }
        [cell prepareForReuse];
        HARNESS_CHECK(!number.superview);
        if (translatedPass) {
            HARNESS_CHECK(CGAffineTransformIsIdentity(title.transform));
            HARNESS_CHECK(CGRectEqualToRect(title.frame, owner.bounds));
        }
        NSLog(@"[harness] PASS ordinal layout: %.2fpt gap after container pass, reused cleanly", gap);
    });

    // What each row shows once the header has given its artist: the line's alpha, how far the title moved, and
    // where the badge is drawn against the end of the title's text. Then the first row is prepared for reuse and
    // has to come back as Spotify drew it, and laid out again has to be dropped again.
    NSString *(^rowState)(UICollectionViewCell *) = ^NSString *(UICollectionViewCell *cell) {
        [cell layoutIfNeeded];
        UIView *subtitle = byIdentifier(cell, @"EncoreConsumerMobile.View.Granular.Subtitle");
        UIView *badge = byIdentifier(cell, @"Components.UI.ExplicitIcon");
        UILabel *title = (UILabel *)byIdentifier(cell, @"EncoreConsumerMobile.View.Granular.Title-internal");
        UIImageView *drawn = nil;
        for (UIView *v in subtitle.superview.subviews) {
            if ([v isKindOfClass:UIImageView.class]) drawn = (UIImageView *)v;
        }
        NSString *line = subtitle.alpha == 0 ? @"hidden" : @"shown";
        NSString *badgeState = !badge ? @"" : (drawn ? [NSString stringWithFormat:@", badge drawn %.0fpt after the text (original a=%.0f, a11y %d)",
            CGRectGetMinX([drawn.superview convertRect:drawn.frame toView:title]) -
                [title textRectForBounds:title.bounds limitedToNumberOfLines:1].size.width, badge.alpha, drawn.isAccessibilityElement] : @", badge where it was");
        return [NSString stringWithFormat:@"\"%@\": line %@, title moved %.1fpt, title width %.0f%@", title.text, line,
                title.transform.ty, title.bounds.size.width, badgeState];
    };
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        for (UICollectionViewCell *cell in trackCells) NSLog(@"[harness] row %@", rowState(cell));
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [trackCells[0] prepareForReuse];
        NSLog(@"[harness] reused, before its pass: needs layout %d", trackCells[0].layer.needsLayout);
        UIView *row = trackCells[0].contentView.subviews.firstObject.subviews.firstObject;
        __block CGFloat subtitleAlpha = -1, badgeAlpha = -1;
        __block NSUInteger drawnCount = 0;
        for (UIView *v in row.subviews) {
            if ([v.accessibilityIdentifier isEqualToString:@"EncoreConsumerMobile.View.Granular.Subtitle"]) subtitleAlpha = v.alpha;
            if ([v.accessibilityIdentifier isEqualToString:@"Components.UI.ExplicitIcon"]) badgeAlpha = v.alpha;
            if ([v isKindOfClass:UIImageView.class]) drawnCount++;
        }
        NSLog(@"[harness] reused, restored: line a=%.0f, badge a=%.0f, drawn badges %lu", subtitleAlpha, badgeAlpha,
              (unsigned long)drawnCount);
        NSLog(@"[harness] reused, laid out again: row %@", rowState(trackCells[0]));
    });

    // `verify-badge`: a row that draws its explicit badge again after the title keeps that picture while the
    // source badge looks the same, and draws it anew for a size, appearance or badge change and after reuse; reused
    // for a row with no badge it has none. Exits nonzero on failure.
    if ([NSProcessInfo.processInfo.arguments containsObject:@"verify-badge"]) layoutWhen(@"explicit badge cell mounted", ^BOOL { return trackCells[2].window != nil; }, ^{
        UICollectionViewCell *cell = trackCells[2];
        UIView *row = cell.contentView.subviews.firstObject.subviews.firstObject;
        UIView *(^source)(void) = ^UIView *{ return byIdentifier(cell, @"Components.UI.ExplicitIcon"); };
        UIImageView *(^drawnBadge)(void) = ^UIImageView *{
            [cell layoutIfNeeded];
            UIImageView *found = nil;
            for (UIView *v in row.subviews) {
                if (![v isKindOfClass:UIImageView.class]) continue;
                HARNESS_CHECK(!found);
                found = (UIImageView *)v;
            }
            return found;
        };
        UIImageView *(^layOutAgain)(void) = ^UIImageView *{ [cell setNeedsLayout]; return drawnBadge(); };

        // The first pass may have drawn it before the row had the window's traits: one more settles it.
        layOutAgain();
        UIImageView *first = layOutAgain();
        UIImage *picture = first.image;
        HARNESS_CHECK(first && picture && source().alpha == 0);
        for (int i = 0; i < 5; i++) {
            UIImageView *again = layOutAgain();
            HARNESS_CHECK(again == first && again.image == picture);
        }

        UIView *badge = source();
        CGRect frame = badge.frame;
        badge.bounds = CGRectMake(0, 0, 15, 15);
        UIImageView *resized = layOutAgain();
        HARNESS_CHECK(resized && resized.image != picture && resized.image.size.width == 15);
        badge.frame = frame;
        UIImage *sized = layOutAgain().image;
        HARNESS_CHECK(sized && sized.size.width == frame.size.width && sized != picture);

        cell.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
        UIImage *light = layOutAgain().image;
        HARNESS_CHECK(light && light != sized);
        HARNESS_CHECK(layOutAgain().image == light);
        cell.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        UIImage *dark = layOutAgain().image;
        HARNESS_CHECK(dark && dark != light);

        // Hide explicit badge changes only the source badge's mask (Kit/SGRExplicitBadge.x), on a row not reused.
        UIView *shown = source();
        CALayer *transparent = [CALayer layer];
        shown.layer.mask = transparent;
        UIImage *masked = layOutAgain().image;
        HARNESS_CHECK(masked && masked != dark);
        HARNESS_CHECK(layOutAgain().image == masked);
        shown.layer.mask = nil;
        HARNESS_CHECK(layOutAgain().image != masked);
        dark = layOutAgain().image;

        UIImage *beforeReuse = layOutAgain().image;
        [cell prepareForReuse];
        HARNESS_CHECK(!drawnBadge() || drawnBadge().image != beforeReuse);
        UIImage *reused = layOutAgain().image;
        HARNESS_CHECK(reused && reused != beforeReuse);

        UIView *other = box(row, UIView.class, frame, @"Components.UI.ExplicitIcon");
        other.backgroundColor = UIColor.redColor;
        [badge removeFromSuperview];
        UIImage *swapped = layOutAgain().image;
        HARNESS_CHECK(swapped && swapped != reused && source() == other);

        [other removeFromSuperview];
        [cell prepareForReuse];
        HARNESS_CHECK(!layOutAgain());
        NSLog(@"[harness] PASS the album row's drawn badge is kept while unchanged and redrawn on change");
        exit(0);
    });

    // and under it the footer Spotify sends: the album's own line, the copyright, and the sections the
    // redesign drops -- each with the 16pt spacer Spotify puts between them. Fans also like stands for a
    // section no switch names. They sit in a real collection view, which is what AlbumSections.x keeps what
    // it has read of them on.
    _footerCells = [NSMutableArray array];
    UICollectionView *footerList = [[UICollectionView alloc] initWithFrame:collection.bounds
                                                      collectionViewLayout:[UICollectionViewFlowLayout new]];
    footerList.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    footerList.backgroundColor = UIColor.clearColor;
    footerList.userInteractionEnabled = NO;
    [collection addSubview:footerList];
    NSArray *footer = @[@[@"", @16], @[@"Album.ConsumptionExperience", @15.33], @[@"", @16],
                        @[@"heading:More by The Weeknd", @52.67], @[@"cards", @194.33], @[@"", @16],
                        @[@"heading:Related Music Videos", @52.67], @[@"cards", @235.67], @[@"", @16],
                        @[@"heading:Merch", @52.67], @[@"cards", @197], @[@"", @16],
                        @[@"heading:You might also like", @52.67], @[@"cards", @193.33], @[@"", @16],
                        @[@"heading:Fans also like", @52.67], @[@"cards", @190], @[@"", @16],
                        @[@"Album.Copyright", @60.67]];
    for (NSArray *item in footer) {
        NSString *kind = item[0];
        CGFloat height = [item[1] doubleValue];
        _TtC12Element_List18CollectionViewCell *cell =
            [[_TtC12Element_List18CollectionViewCell alloc] initWithFrame:CGRectMake(0, 0, W, height)];
        [footerList addSubview:cell];
        UIView *content = box(cell.contentView, MockAlbum_PageImpl20FooterStructuredDataView.class, cell.contentView.bounds, nil);
        if ([kind isEqualToString:@"Album.ConsumptionExperience"]) {
            UIView *line = box(content, UIView.class, content.bounds, kind);
            label(line, CGRectMake(16, 0, W - 32, height), @"22 songs • 1hr 24min", 11, UIColor.whiteColor, @"Encore.Label");
        } else if ([kind isEqualToString:@"Album.Copyright"]) {
            UIView *line = box(content, UIView.class, content.bounds, kind);
            UILabel *text = label(line, CGRectMake(16, 0, W - 32, height),
                                  @"© 2025 The Weeknd XO Music ULC, marketed by Republic Records.\n℗ 2025 The Weeknd XO Music ULC, marketed by Republic Records.",
                                  11, UIColor.whiteColor, @"Encore.Label");
            text.numberOfLines = 0;
        } else if ([kind hasPrefix:@"heading:"]) {
            UIView *heading = box(content, UIView.class, content.bounds, @"Components.UI.SectionHeadingHome");
            label(heading, CGRectMake(16, 16, W - 32, 20.67), [kind substringFromIndex:8], 17, UIColor.whiteColor, @"Encore.Label");
        } else if ([kind isEqualToString:@"cards"]) {
            for (int i = 0; i < 3; i++) {
                UIView *card = box(content, UIView.class, CGRectMake(16 + i * 161, 0, 153, height), @"Components.UI.ContentCardAlbum");
                card.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1];
                card.layer.cornerRadius = 4;
                // A card's caption backing as the device paints it: the base surface, on its layer.
                if (i == 0) card.layer.backgroundColor = [UIColor colorWithRed:0x12 / 255.0 green:0x12 / 255.0 blue:0x12 / 255.0 alpha:1].CGColor;
                if (i == 0 && !_baseCard) _baseCard = card;
                if (i == 1 && !_greyCard) _greyCard = card;
            }
        }
        [_footerCells addObject:cell];
    }

    // An episode page is this same template with cells of its own (device, trees/continuous/1.txt
    // 2026-09-20), and every one of them paints the black the AMOLED made of Spotify's base surface over
    // the field. Put under the tracks, clear of the footer the redesign drops: what is proved here is the
    // paint, not the layout. A card inside one of them is a cell of its own and keeps its own black.
    NSArray *episode = @[@[@"Episode Transcript", @50], @[@"", @24], @[@"", @4.67]];
    CGFloat episodeY = _tracksBottom + 140;
    NSMutableArray<UIView *> *episodePaints = [NSMutableArray array];
    for (NSArray *item in episode) {
        CGFloat height = [item[1] doubleValue];
        UICollectionViewCell *cell = [[_TtC12Element_List18CollectionViewCell alloc]
                                      initWithFrame:CGRectMake(0, episodeY, W, height)];
        [collection addSubview:cell];
        UIView *content = box(cell.contentView, UIView.class, cell.contentView.bounds, nil);
        UIView *paint = box(content, UIView.class, content.bounds, nil);
        paint.backgroundColor = UIColor.blackColor;
        if ([item[0] length]) label(paint, CGRectMake(16, 16, W - 48, 18), item[0], 13, UIColor.whiteColor, @"Encore.Label");
        [episodePaints addObject:paint];
        episodeY += height;
    }
    UICollectionViewCell *carousel = [[_TtC12Element_List18CollectionViewCell alloc]
                                      initWithFrame:CGRectMake(0, episodeY, W, 80)];
    [collection addSubview:carousel];
    UICollectionViewCell *card = [[_TtC12Element_List18CollectionViewCell alloc] initWithFrame:CGRectMake(16, 0, 153, 80)];
    card.backgroundColor = UIColor.blackColor;
    [carousel.contentView addSubview:card];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSLog(@"[harness] the episode page's paint: %@ %@ %@, and the card inside a cell %@",
              episodePaints[0].backgroundColor ?: @"clear", episodePaints[1].backgroundColor ?: @"clear",
              episodePaints[2].backgroundColor ?: @"clear", card.backgroundColor ?: @"clear");
        // The base-surface album card cleared, the one painted gray left alone.
        NSLog(@"[harness] album cards: base surface a=%.0f, gray a=%.2f",
              CGColorGetAlpha(self->_baseCard.layer.backgroundColor), CGColorGetAlpha(self->_greyCard.layer.backgroundColor));
    });

    // the sticky navigation bar, its gradient hidden until the page scrolls
    UIView *navBar = box(page, _TtC28EncoreConsumerMobile_BaseKit20HeaderNavigationBar.class, CGRectMake(0, 0, W, 118), @"CreativeWorkPlatform.HeaderNavigationBar");
    UIView *navGradient = box(navBar, _TtC19LegacyUI_ECMCoreKit12GradientView.class, navBar.bounds, nil);
    ((CAGradientLayer *)navGradient.layer).colors = @[(id)[UIColor colorWithWhite:0.02 alpha:1].CGColor,
                                                      (id)[UIColor colorWithWhite:0.02 alpha:1].CGColor];
    navGradient.hidden = YES;
    // Scrolled, Spotify shows it by -setHidden:, which is what took a conceal() back.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        navGradient.hidden = NO;
        NSLog(@"[harness] Spotify showed the navigation bar's gradient; mask %@", navGradient.layer.mask ? @"on" : @"off");
    });

    // the two controls Spotify floats over the page, outside the scroll
    UIView *shuffleElement = box(page, UIView.class, CGRectMake(282, 62, 48, 48), nil);
    UIView *shuffle = box(shuffleElement, MockEncoreButton.class, shuffleElement.bounds, @"Components.UI.ShuffleButton");
    shuffle.accessibilityLabel = @"Shuffle tracks";
    mockShuffleGlyph(shuffle);

    UIView *playElement = box(page, UIView.class, CGRectMake(338, 94, 48, 48), nil);
    UIView *playButton = box(playElement, _TtC28EncoreConsumerMobile_BaseKit14PlayButtonView.class, playElement.bounds, @"header-play-button");
    UIControl *condensed = (UIControl *)box(playButton, MockCondensedButton.class, playButton.bounds, nil);
    condensed.accessibilityLabel = @"Play";
    UIImageView *disc = [[UIImageView alloc] initWithFrame:condensed.bounds];
    disc.image = playGlyph();
    disc.backgroundColor = [UIColor colorWithRed:0.12 green:0.84 blue:0.38 alpha:1];
    disc.layer.cornerRadius = 24;
    disc.clipsToBounds = YES;
    [condensed addSubview:disc];

    [self.window makeKeyAndVisible];
    if (layoutCase()) {
        layoutRun(self.window, page, cover, scroll, artistName, ^{
            [page setNeedsLayout];
            [page layoutIfNeeded];
        });
        return YES;
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"cover-beside"]) {
        besideRun(self.window, root, page, @"Album", ^{
            [page setNeedsLayout];
            [page layoutIfNeeded];
        }, ^(NSString *text) {
            albumTitle.text = text;
        });
        return YES;
    }
    if (downloads) downloadScript();
    // `faces` (faces-check.h): the artist line's faces, after the header has drawn the one the page opened with.
    // `more` (more-check.h): the track rows' ⋯ in the page's colour, once the field has read the cover.
    if ([NSProcessInfo.processInfo.arguments containsObject:@"faces"]) afterPinnedHold(^{
        layoutWhen(@"album header mounted", ^BOOL { return facesInfo(root.view).window != nil; }, ^{
            facesRun(root.view, (UIControl *)parentRow);
        });
    });
    if ([NSProcessInfo.processInfo.arguments containsObject:@"more"])
        afterPinnedHold(^{
            layoutWhen(@"coloured album field", ^BOOL {
                CGFloat r, g, b, a;
                return [SGRAlbumFieldColor(page) getRed:&r green:&g blue:&b alpha:&a] && checkChroma(checkLab(r, g, b)) >= 0.03;
            }, ^{
                moreRun(root.view, trackCells, ^UIColor *{ return SGRAlbumFieldColor(page); });
            });
        });

    if (shortTitle) {
        layoutWhen(@"visible short album title X", ^BOOL {
            for (UIView *info in header.subviews) {
                if (![info isKindOfClass:SGRHeaderInfo.class]) continue;
                for (UIView *text in info.subviews) {
                    if ([text isKindOfClass:UILabel.class] && [((UILabel *)text).text isEqualToString:@"X"]
                        && !text.hidden && text.alpha > 0) return YES;
                }
            }
            return NO;
        }, ^{
            NSLog(@"[harness] PASS the redesigned album header displays X");
            exit(0);
        });
    }

    // `addto`: saved from elsewhere at 3 s (the ⋯ sheet, nothing laid out), then Play's right tapped at 7 s.
    if ([NSProcessInfo.processInfo.arguments containsObject:@"addto"]) {
        UIView *rootView = root.view;
        for (NSNumber *when in @[@2, @6.5, @8.5]) {
            at(when.doubleValue, ^{ NSLog(@"[harness] add-to at %@s: %@", when, trailingState(rootView)); });
        }
        at(3, ^{ setAddTo(1); NSLog(@"[harness] add-to: saved from elsewhere"); });
        at(7, ^{ [trailingButton(rootView) sendActionsForControlEvents:UIControlEventTouchUpInside]; });
    }

    // `motion`: Apple Music's animated cover, HARNESS_CANVAS_FILE (any mp4), handed to the hero at 2 s as the
    // catalog would hand it. The clip stays transparent until its first frame is decoded and then fades in;
    // it plays in a window and stops out of one.
    if ([NSProcessInfo.processInfo.arguments containsObject:@"motion"]) {
        UIView *rootView = root.view;
        __block UIView *hero = nil;
        at(2, ^{
            NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:rootView];
            while (queue.count && !hero) {
                UIView *v = queue.firstObject;
                [queue removeObjectAtIndex:0];
                if ([NSStringFromClass(v.class) isEqualToString:@"SGRAlbumHero"]) hero = v;
                [queue addObjectsFromArray:v.subviews];
            }
            const char *path = getenv("HARNESS_CANVAS_FILE");
            NSLog(@"[harness] motion: hero %@, clip %s", hero ? @"found" : @"missing", path ?: "not given");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            if (hero && path) [hero performSelector:NSSelectorFromString(@"showMotion:") withObject:[NSURL fileURLWithPath:@(path)]];
#pragma clang diagnostic pop
            AVPlayerLayer *clip = [hero valueForKeyPath:@"clip.video"];
            NSLog(@"[harness] motion: added, ready %d, opacity %.0f, fading %@", clip.readyForDisplay, clip.opacity,
                  [clip animationForKey:@"fade"] ? @"yes" : @"no");
        });
        for (NSNumber *when in @[@2.5, @4]) {
            at(when.doubleValue, ^{
                AVPlayerLayer *clip = [hero valueForKeyPath:@"clip.video"];
                NSLog(@"[harness] motion at %@s: ready %d, opacity %.0f, rate %.0f", when, clip.readyForDisplay, clip.opacity, clip.player.rate);
            });
        }
        at(4.5, ^{
            UIView *parent = hero.superview;
            NSUInteger index = [parent.subviews indexOfObject:hero];
            [hero removeFromSuperview];
            AVPlayerLayer *clip = [hero valueForKeyPath:@"clip.video"];
            NSLog(@"[harness] motion out of the window: rate %.0f", clip.player.rate);
            [parent insertSubview:hero atIndex:index];
            NSLog(@"[harness] motion back in it: rate %.0f", clip.player.rate);
        });
    }

    // In `late`, add arrives at 2.5 s, after every pass of the header's and the metadata's re-reads: an arranged
    // subview of the row, which lays out the row and nothing above it.
    if (late) {
        UIStackView *row = (UIStackView *)_actionRow;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [row insertArrangedSubview:actionButton(row, CGRectMake(62, 0, 48, 48), @"Components.UI.AddToButton", @"plus", @"Add")
                               atIndex:0];
            NSLog(@"[harness] late: add arrived in the row");
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSLog(@"[harness] late: Play's right shows \"%@\"", trailingLabel(root.view));
        });
    }

    // The list is measured the way the page's collection measures it: every cell is asked how tall it wants
    // to be, which is where AlbumSections.x answers 0 for what the redesign drops, and the answers are
    // stacked. Done a beat after launch, so the header has laid out at least once first.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self measureFooter:W];
        NSLog(@"[harness] hero %@, title stack %@, action row %@",
              NSStringFromCGRect([cover.window convertRect:cover.bounds fromView:cover]),
              NSStringFromCGRect(self->_titleStack.frame), NSStringFromCGRect(self->_actionRow.frame));

        // The ⋯ the redesign pins over the page, outside the scroll, and the artist line under the title,
        // which opens whoever made the album (issues #57 and #56).
        UIView *pinned = nil;
        for (UIView *sub in page.subviews) {
            if ([NSStringFromClass(sub.class) isEqualToString:@"SGRMirrorButton"]) pinned = sub;
        }
        NSLog(@"[harness] pinned more: %@ on the page, hidden=%d",
              pinned ? NSStringFromCGRect(pinned.frame) : @"MISSING", pinned.hidden);
        __block UIView *info = nil, *artist = nil;
        void (^__block walk)(UIView *) = ^(UIView *v) {
            if ([NSStringFromClass(v.class) isEqualToString:@"SGRHeaderInfo"]) info = v;
            for (UIView *sub in v.subviews) walk(sub);
        };
        walk(root.view);
        for (UIView *sub in info.subviews) {
            if ([sub isKindOfClass:UILabel.class] && [((UILabel *)sub).text isEqualToString:@"The Weeknd"]) artist = sub;
        }
        UIView *onName = [info hitTest:CGPointMake(CGRectGetMidX(info.bounds), CGRectGetMidY(artist.frame)) withEvent:nil];
        UIView *beside = [info hitTest:CGPointMake(24, CGRectGetMidY(artist.frame)) withEvent:nil];
        NSLog(@"[harness] artist line: on the name %@, beside it %@", onName ? NSStringFromClass(onName.class) : @"through",
              beside ? NSStringFromClass(beside.class) : @"through");
    });

    // Spotify lays the header out again after the redesign has moved things: the title block, its stack and
    // the action row go back where its own layout puts them, and the redesign has to take them again from
    // its own watch on each.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self->_titleBlock.frame = CGRectMake(0, 264, 215.33, 57.33);
        self->_titleStack.frame = CGRectMake(16, 0, 183.33, 57.33);
        self->_actionRow.frame = CGRectMake(0, 23.33, 206, 48);
        for (NSUInteger i = 0; i < self->_actionItems.count; i++) {
            self->_actionItems[i].frame = self->_actionFrames[i].CGRectValue;
        }
        [groupStack setNeedsLayout];
        [groupStack layoutIfNeeded];
        [bottomStack setNeedsLayout];
        [bottomStack layoutIfNeeded];
        NSLog(@"[harness] Spotify's own frames put back; the redesign answered with title stack %@, action row %@",
              NSStringFromCGRect(self->_titleStack.frame), NSStringFromCGRect(self->_actionRow.frame));
    });
    if ([NSProcessInfo.processInfo.arguments containsObject:@"cover-stats"]) at(6, ^{ logCoverStats(); });
    // Successive albums in one app process: the renderer's CIContext is reused as it is in Spotify.
    if ([NSProcessInfo.processInfo.arguments containsObject:@"cover-profile"]) {
        NSArray *names = @[@"portrait", @"colourful", @"darkAccent", @"solidLight", @"solidDark"];
        NSArray *covers = @[faceCover(), colourfulCover(), darkAccentCover(), solidLightCover(), solidDarkCover()];
        for (NSUInteger i = 0; i < covers.count; i++) {
            at(2 + 3 * i, ^{
                NSLog(@"[harness] cover profile %@", names[i]);
                coverPicture.image = covers[i];
            });
        }
        at(2 + 3 * covers.count, ^{ NSLog(@"[harness] cover profile complete"); exit(0); });
    }
    if([NSProcessInfo.processInfo.arguments containsObject:@"verify-actions"])
        afterPinnedHold(^{ verifyAlbumActions(root.view); });
    // `veil` / `veil-card` / `veil-off` (hero-veil-check.h): the page scrolled by its own scroll view, the header in it.
    // Square, the veil is drawn on the picture in the hero's square, its first subview, and moves nothing.
    NSString *veil = veilMode();
    BOOL square = [veil isEqualToString:@"veil-card"];
    if (veil)
        veilRun(root.view, @"album", veil, NO, !square, 2.5,
                square ? ^UIView *(UIView *hero) { return veilFind(hero.subviews.firstObject, @"UIImageView"); } : nil,
                ^(CGFloat d) { scroll.contentOffset = CGPointMake(0, d); });
    return YES;
}

// Every footer cell asked for its height the way the collection's self-sizing asks, then stacked under the
// tracks with whatever each answered.
- (void)measureFooter:(CGFloat)width {
    CGFloat y = _tracksBottom;
    NSUInteger steady = 0;
    for (_TtC12Element_List18CollectionViewCell *cell in _footerCells) {
        CGFloat natural = cell.bounds.size.height;
        NSIndexPath *path = [NSIndexPath indexPathForItem:[_footerCells indexOfObject:cell] inSection:0];
        UICollectionViewLayoutAttributes *attributes = [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:path];
        attributes.frame = CGRectMake(0, y, width, natural);
        UICollectionViewLayoutAttributes *answer = [cell preferredLayoutAttributesFittingAttributes:attributes];
        // The list asks again once the cell is laid out at that height -- and once settled the content it holds
        // no longer measures itself, so every later answer has to be the first one or the list never stops asking.
        cell.frame = CGRectMake(0, y, width, answer.size.height);
        [cell layoutIfNeeded];
        CGSize again = [cell preferredLayoutAttributesFittingAttributes:attributes].size;
        CGSize onceMore = [cell preferredLayoutAttributesFittingAttributes:attributes].size;
        HARNESS_CHECK(fabs(again.height - answer.size.height) < 0.5 && fabs(onceMore.height - answer.size.height) < 0.5);
        if (answer.size.height > 0) steady++;
        y += answer.size.height;
    }
    _listView.frame = CGRectMake(0, 486.67, width, y + 24);
    _listView.subviews.firstObject.frame = _listView.bounds;
    UIScrollView *scroll = (UIScrollView *)_listView.superview.superview;
    if ([scroll isKindOfClass:UIScrollView.class]) scroll.contentSize = CGSizeMake(width, CGRectGetMaxY(_listView.frame));
    NSLog(@"[harness] PASS footer settled: %lu cells answered the same height when asked again and again, %lu of them kept",
          (unsigned long)_footerCells.count, (unsigned long)steady);
    NSLog(@"[harness] the footer measured %.0fpt under the tracks", y - _tracksBottom);
    [self flipDroppedFooterCell:width];
}

// What a cell is can change while it keeps its width: a section dropped and then kept, say. The settled answer
// must not outlive that -- the ask has to measure again instead of answering its cached 0, and once it does,
// the new answer is the one it keeps answering.
- (void)flipDroppedFooterCell:(CGFloat)width {
    // Whichever cell this run drops -- the switches move which ones do.
    _TtC12Element_List18CollectionViewCell *cell = nil;
    NSIndexPath *path = nil;
    for (_TtC12Element_List18CollectionViewCell *c in _footerCells) {
        NSIndexPath *item = [NSIndexPath indexPathForItem:[_footerCells indexOfObject:c] inSection:0];
        UICollectionViewLayoutAttributes *ask = [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:item];
        ask.frame = c.frame;
        if ([c preferredLayoutAttributesFittingAttributes:ask].size.height == 0) {
            cell = c;
            path = item;
            break;
        }
    }
    HARNESS_CHECK(cell && path);
    UICollectionViewLayoutAttributes *attributes = [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:path];
    attributes.frame = cell.frame;
    CGFloat before = [cell preferredLayoutAttributesFittingAttributes:attributes].size.height;
    HARNESS_CHECK(before == 0);

    // The same cell at the same width, now holding the album's own line: kept, and taller by the lead over it.
    UIView *content = cell.contentView.subviews.firstObject;
    UIView *line = box(content, UIView.class, content.bounds, @"Album.ConsumptionExperience");
    label(line, CGRectMake(16, 0, width - 32, 15.33), @"22 songs • 1hr 24min", 11, UIColor.whiteColor, @"Encore.Label");
    CGFloat flipped = [cell preferredLayoutAttributesFittingAttributes:attributes].size.height;
    CGFloat kept = [cell preferredLayoutAttributesFittingAttributes:attributes].size.height;
    HARNESS_CHECK(flipped > 0 && fabs(kept - flipped) < 0.5);

    // And back: the line gone, the cell dropped again, 0 again, and asked again still 0.
    [line removeFromSuperview];
    CGFloat dropped = [cell preferredLayoutAttributesFittingAttributes:attributes].size.height;
    CGFloat stillDropped = [cell preferredLayoutAttributesFittingAttributes:attributes].size.height;
    HARNESS_CHECK(dropped == 0 && stillDropped == 0);
    NSLog(@"[harness] PASS footer refit: a dropped cell answered 0, %.2fpt once it held the album's line, then 0 again, each kept on the asks after it", flipped);
    [self refitTextSizeOfCell:1 at:width];
}

// A text-size change keeps the width, so the settled answer has to let go of it: the mask would hide the new
// height the content measures at, and the list would keep the old one.
- (void)refitTextSizeOfCell:(NSUInteger)item at:(CGFloat)width {
    _TtC12Element_List18CollectionViewCell *cell = _footerCells[item];
    UICollectionViewLayoutAttributes *attributes = [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:
                                                    [NSIndexPath indexPathForItem:item inSection:0]];
    attributes.frame = cell.frame;
    CGSize same = [cell preferredLayoutAttributesFittingAttributes:attributes].size;
    HARNESS_CHECK(fabs(same.height - cell.bounds.size.height) < 0.5);

    [cell sg_setTextSize:UIContentSizeCategoryAccessibilityLarge];
    CGSize big = [cell preferredLayoutAttributesFittingAttributes:attributes].size;
    CGSize kept = [cell preferredLayoutAttributesFittingAttributes:attributes].size;
    // The mock's content measures by its own bounds, so the bigger text size alone has to move the answer.
    HARNESS_CHECK(big.height > same.height + 0.5);
    HARNESS_CHECK(fabs(kept.height - big.height) < 0.5);
    NSLog(@"[harness] PASS footer text size: settled at %.2fpt, %.2fpt once the text size changed at the same width, and kept on the asks after it",
          same.height, big.height);
    [cell sg_setTextSize:nil];
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

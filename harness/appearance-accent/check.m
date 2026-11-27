#import <UIKit/UIKit.h>
#import "Core/SGPrefs.h"
#import "Core/SGTopController.h"
#import "Redesigned/Kit/SGRAccent.h"
#import "Redesigned/Kit/SGRBridges.h"
#import "Redesigned/Kit/SGRPalette.h"
#import "../harness-fail.h"

static UIViewController *front;
static UIImage *cover;
static NSString *coverTrack, *trackURI;
static id<SGPlayerStateObserver> observer;
static NSMutableArray *replies;
NSNotificationName const SGRNowPlayingArtworkDidChangeNotification = @"harness.artwork";
NSNotificationName const SGRFieldColorDidChangeNotification = @"harness.field";
// Supply a typed negative preference before the tweak constructors. Foundation's command-line
// argument domain does not supply the "-1" value in this console executable.
@interface SGRStockLaunchDefaults : NSObject @end
@implementation SGRStockLaunchDefaults
+ (void)load {
    if ([NSProcessInfo.processInfo.arguments containsObject:@"stock"]) {
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGRKeyAccent:@(-1),SGRKeyAccentAuto:@NO} forName:NSArgumentDomain];
        SGPrefsChanged();
    }
}
@end
BOOL SGRedesignedUI(void) { return YES; }
UIWindow *SGAppWindow(void) { return nil; }
UIViewController *SGTopControllerInWindow(UIWindow *window, NSMutableArray *path, NSMutableArray *presented) { return front; }
NSString *SGURIString(id uri) { return uri; }
UIImage *SGRNowPlayingArtwork(NSString **track, NSString **identity) {
    if (track) *track = coverTrack;
    if (identity) *identity = coverTrack;
    return cover;
}
void SGAddPlayerStateObserver(id<SGPlayerStateObserver> value) { observer = value; }
// The owner's only read is state.track.URI.
@interface Track : NSObject
@property (nonatomic, copy) NSString *URI;
@end
@implementation Track @end
@interface State : NSObject
@property (nonatomic, strong) Track *track;
@end
@implementation State @end
SPTPlayerState *SGPlayerState(void) {
    State *state = [State new]; state.track = [Track new]; state.track.URI = trackURI;
    return (id)state;
}
@interface SGRPalette ()
@property (nonatomic, readwrite) UIColor *fieldColor;
@end
@implementation SGRPalette
+ (void)paletteForImage:(UIImage *)image request:(SGRPaletteRequest)request completion:(void (^)(SGRPalette *))completion {
    [replies addObject:[completion copy]];
}
+ (void)tintForImage:(UIImage *)image surface:(UIColor *)surface strong:(BOOL)strong completion:(void (^)(UIColor *))completion {
    HARNESS_FAIL(@"unexpected tint request");
}
@end

// UIKit owns the transition and final hierarchy. Deliver completion after setting that hierarchy,
// just as UIKit does for a completed push or a cancelled interactive pop.
@interface Transition : NSObject
@property (nonatomic, copy) void (^completion)(id);
- (BOOL)animateAlongsideTransition:(id)animation completion:(void (^)(id))completion;
@end
@implementation Transition
- (BOOL)animateAlongsideTransition:(id)animation completion:(void (^)(id))completion { self.completion = completion; return YES; }
@end
@interface PageFieldNotice : NSObject
@property (nonatomic, strong) UIView *accentPage;
@end
@implementation PageFieldNotice @end

static NSUInteger checks;
static void expect(BOOL ok, NSString *name) {
    checks++;
    if (!ok) HARNESS_FAIL(@"%@", name);
}
static void rgb(NSInteger wanted, NSString *name) {
    checks++;
    if (SGRAccentRGB() != wanted) HARNESS_FAIL(@"%@: got #%06lX, expected #%06lX", name, (long)SGRAccentRGB(), (long)wanted);
}
static void settings(BOOL automatic) {
    [NSUserDefaults.standardUserDefaults setVolatileDomain:@{
        SGRKeyAccent: @0x123456, SGRKeyAccentAuto: @(automatic),
        @"spotifyglass.accent": @0xABCDEF
    } forName:NSArgumentDomain];
    SGRAccentPreferencesChanged();
}
static void show(UIViewController *page) { front = page; SGRAccentRefreshContext(); }
static void deliver(NSUInteger index, UIColor *color) {
    void (^reply)(SGRPalette *) = replies[index];
    [replies removeObjectAtIndex:index];
    SGRPalette *palette = [SGRPalette new]; palette.fieldColor = color;
    reply(palette);
}
static double linear(double v) { return v <= .04045 ? v/12.92 : pow((v+.055)/1.055, 2.4); }
static NSInteger colorRGB(UIColor *color) {
    CGFloat r, g, b, a;
    [color getRed:&r green:&g blue:&b alpha:&a];
    return (lround(r*255)<<16) | (lround(g*255)<<8) | lround(b*255);
}

// Count KVC metadata writes at the CAAnimation boundary, not allocations inside Apple's setters.
@interface MeasuredBasicAnimation : CABasicAnimation
@property (nonatomic) NSUInteger metadataWrites;
@property (nonatomic) NSUInteger metadataReads;
@end
@implementation MeasuredBasicAnimation
- (id)valueForKey:(NSString *)key {
    if ([key isEqual:@"sgr.accent.sources"]) self.metadataReads++;
    return [super valueForKey:key];
}
- (void)setValue:(id)value forKey:(NSString *)key {
    self.metadataWrites++;
    [super setValue:value forKey:key];
}
@end
@interface MeasuredKeyframeAnimation : CAKeyframeAnimation
@property (nonatomic) NSUInteger metadataWrites;
@end
@implementation MeasuredKeyframeAnimation
- (void)setValue:(id)value forKey:(NSString *)key {
    self.metadataWrites++;
    [super setValue:value forKey:key];
}
@end

static void checkAnimationMetadata(void) {
    MeasuredBasicAnimation *basic = [MeasuredBasicAnimation animationWithKeyPath:@"opacity"];
    MeasuredKeyframeAnimation *keys = [MeasuredKeyframeAnimation animationWithKeyPath:@"opacity"];
    NSArray *plain = @[@0, @0.5, @1];
    for (NSUInteger index = 0; index < 100; index++) {
        basic.fromValue = @0;
        basic.toValue = @1;
        basic.byValue = nil;
        keys.values = plain;
    }
    expect(basic.metadataWrites == 0 && keys.metadataWrites == 0, @"no-token animation setters write no metadata");
    expect(!basic.metadataReads, @"numeric animation setters never consult accent provenance");
    expect([keys.values isEqual:plain], @"no-token keyframes preserve their values");
    keys.values = nil;
    expect(keys.values == nil && keys.metadataWrites == 0, @"nil keyframes remain nil without metadata");

    id unowned = (__bridge id)UIColor.blueColor.CGColor;
    id token = (__bridge id)SGRAccentColor().CGColor;
    basic.keyPath = @"fillColor";
    basic.fromValue = token;
    basic.metadataWrites = 0;
    basic.toValue = unowned;
    expect(basic.metadataWrites == 0, @"unowned slot does not rewrite another slot's provenance");
    basic.fromValue = unowned;
    expect(basic.metadataWrites == 1, @"replacing a token clears its provenance");
    basic.metadataWrites = 0;
    basic.fromValue = unowned;
    expect(basic.metadataWrites == 0, @"already cleared basic slot writes no metadata");

    keys.keyPath = @"fillColor";
    keys.values = @[unowned, token, unowned];
    CALayer *layer = [CALayer layer];
    SGRAccentSetLayerOverride(layer, UIColor.redColor);
    [layer addAnimation:keys forKey:@"mixed"];
    NSArray *mixed = [(CAKeyframeAnimation *)[layer animationForKey:@"mixed"] values];
    expect(colorRGB([UIColor colorWithCGColor:(__bridge CGColorRef)mixed[0]]) == 0x0000FF &&
           colorRGB([UIColor colorWithCGColor:(__bridge CGColorRef)mixed[1]]) == 0xFF0000 &&
           colorRGB([UIColor colorWithCGColor:(__bridge CGColorRef)mixed[2]]) == 0x0000FF,
           @"lazy keyframe provenance preserves both unowned neighbors");
    keys.metadataWrites = 0;
    keys.values = @[unowned, unowned, unowned];
    expect(keys.metadataWrites == 1, @"replacing token keyframes clears provenance");
    keys.metadataWrites = 0;
    keys.values = @[unowned, unowned, unowned];
    expect(keys.metadataWrites == 0, @"already cleared keyframes write no metadata");
    [layer addAnimation:keys forKey:@"cleared"];
    NSArray *cleared = [(CAKeyframeAnimation *)[layer animationForKey:@"cleared"] values];
    expect(colorRGB([UIColor colorWithCGColor:(__bridge CGColorRef)cleared[1]]) == 0x0000FF,
           @"cleared keyframe provenance cannot recolor a replacement");
    [layer addAnimation:basic forKey:@"basic"];
    expect(colorRGB([UIColor colorWithCGColor:(__bridge CGColorRef)[(CABasicAnimation *)[layer animationForKey:@"basic"] fromValue]]) == 0x0000FF,
           @"cleared basic provenance cannot recolor a replacement");
}

static void checkSpotifyPick(void) {
    if (SGInt(SGRKeyAccent, SGRDefaultAccent) != -1)
        HARNESS_FAIL(@"stock launch input: %@", [NSUserDefaults.standardUserDefaults objectForKey:SGRKeyAccent]);
    SGRAccentStart();
    expect(SGRAccentColor() == nil, @"Picked/Spotify keeps the previous nil-token contract");
    UIColor *legacy = [UIColor colorWithRed:29/255.0 green:185/255.0 blue:84/255.0 alpha:1];
    UIView *control = [UIView new]; control.tintColor = legacy;
    expect(colorRGB(legacy) == 0x1DB954, @"Picked/Spotify leaves the old brand green exact");
    CAShapeLayer *shape = [CAShapeLayer layer]; shape.fillColor = legacy.CGColor;
    expect(colorRGB([UIColor colorWithCGColor:shape.fillColor]) == 0x1DB954, @"Picked/Spotify leaves layer colors exact");
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"fillColor"];
    animation.fromValue = (id)legacy.CGColor;
    expect(colorRGB([UIColor colorWithCGColor:(__bridge CGColorRef)animation.fromValue]) == 0x1DB954, @"Picked/Spotify leaves animation inputs exact");
    CGFloat r=29/255.0,g=185/255.0,b=84/255.0;
    expect(!SGRAccentSwap(&r,&g,&b) && r==29/255.0 && g==185/255.0 && b==84/255.0, @"disabled substitution does not alter components");
    // Existing colors predate the preference change; enabling must not split old and new controls.
    [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGRKeyAccent:@(-1),SGRKeyAccentAuto:@YES} forName:NSArgumentDomain];
    SGRAccentPreferencesChanged();
    UIViewController *page=[UIViewController new]; front=page;
    SGRAccentPublishPageColor(page.view,UIColor.yellowColor);
    expect(!SGRAccentSubstitutionEnabled() && SGRAccentColor() == nil, @"Automatic from stock waits for restart");
    rgb(0x1ED760, @"pending Automatic keeps the stock effective accent");
    expect(colorRGB(control.tintColor) == 0x1DB954 &&
           colorRGB([UIColor colorWithCGColor:shape.fillColor]) == 0x1DB954,
           @"pre-existing controls remain stock while restart is pending");
    expect(colorRGB([UIColor colorWithRed:29/255.0 green:185/255.0 blue:84/255.0 alpha:1]) == 0x1DB954,
           @"new colors match old controls while Automatic waits for restart");
    settings(NO);
    expect(SGRPickedAccentRGB() == 0x123456, @"pending custom pick is saved for relaunch");
    expect(!SGRAccentSubstitutionEnabled() && colorRGB(control.tintColor) == 0x1DB954 &&
           colorRGB([UIColor colorWithRed:29/255.0 green:185/255.0 blue:84/255.0 alpha:1]) == 0x1DB954,
           @"custom pick from stock keeps both old and new controls stock");
    [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGRKeyAccent:@(-1),SGRKeyAccentAuto:@NO} forName:NSArgumentDomain];
    SGRAccentPreferencesChanged();
    expect(colorRGB([UIColor colorWithRed:29/255.0 green:185/255.0 blue:84/255.0 alpha:1]) == 0x1DB954,
           @"returning to Spotify cancels the pending accent");
    printf("Picked Spotify: %lu checks passed\n",(unsigned long)checks);
}

int main(void) {
    @autoreleasepool {
        if ([NSProcessInfo.processInfo.arguments containsObject:@"stock"]) { checkSpotifyPick(); return 0; }
        replies = [NSMutableArray array];
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGRKeyAccent: @0x123456} forName:NSArgumentDomain];
        SGPrefsChanged();
        SGRAccentStart();
        checkAnimationMetadata();
        if ([NSProcessInfo.processInfo.arguments containsObject:@"animations"]) {
            printf("animation metadata: %lu checks passed\n", (unsigned long)checks);
            return 0;
        }
        rgb(0x123456, @"Automatic defaults off");
        UIViewController *a = [UIViewController new], *b = [UIViewController new], *noArt = [UIViewController new], *player = [UIViewController new];
        PageFieldNotice *field = [PageFieldNotice new]; field.accentPage = a.view;
        [NSNotificationCenter.defaultCenter postNotificationName:SGRFieldColorDidChangeNotification object:field userInfo:@{@"color": UIColor.yellowColor}];
        SGRAccentPublishPageColor(b.view, UIColor.whiteColor);
        SGRAccentPublishPageColor(noArt.view, nil);
        show(a);
        rgb(0x123456, @"page publication cannot change Picked");
        settings(YES);
        rgb(0xFFFF00, @"A owns foreground");

        UILabel *label = [UILabel new];
        label.textColor = [UIColor colorWithRed:30/255.0 green:215/255.0 blue:96/255.0 alpha:1];
        UIView *control = [UIView new]; control.tintColor = SGRAccentColor();
        CAShapeLayer *shape = [CAShapeLayer layer];
        CGFloat components[] = {30/255.0, 215/255.0, 96/255.0, 1};
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGColorRef green = CGColorCreate(space, components);
        shape.fillColor = green; CGColorRelease(green); CGColorSpaceRelease(space);
        show(b);
        rgb(0xFFFFFF, @"A to B");
        expect(colorRGB(label.textColor) == 0xFFFFFF, @"assigned token text follows B");
        expect(colorRGB(control.tintColor) == 0xFFFFFF, @"assigned control tint follows B");
        expect(colorRGB([UIColor colorWithCGColor:shape.fillColor]) == 0xFFFFFF, @"Lottie shape follows B");
        UIColor *constructed = [[UIColor alloc] initWithRed:30/255.0 green:215/255.0 blue:96/255.0 alpha:1];
        expect(colorRGB(constructed) == 0xFFFFFF, @"UIColor initializer preserves token behavior");

        Transition *pop = [Transition new];
        SGRAccentTrackTransition((id)pop);
        front = a; // interactive transition's tentative top, not a committed owner
        SGRAccentPublishPageColor(a.view, UIColor.cyanColor);
        rgb(0xFFFFFF, @"interactive pop retains committed B");
        front = b; pop.completion(nil);
        rgb(0xFFFFFF, @"cancelled pop returns to B");
        SGRAccentPublishPageColor(a.view, UIColor.yellowColor);
        rgb(0xFFFFFF, @"late A color cannot repaint B");

        trackURI = @"spotify:track:one";
        [observer playerStateDidChange:SGPlayerState()];
        coverTrack = trackURI; cover = [UIImage new];
        [NSNotificationCenter.defaultCenter postNotificationName:SGRNowPlayingArtworkDidChangeNotification object:nil];
        deliver(0, UIColor.cyanColor);
        show(noArt);
        rgb(0x00FFFF, @"no-color page falls back to playing cover");
        show(b); show(player);
        rgb(0x00FFFF, @"player open uses cover, not underlying page");
        show(b);
        rgb(0xFFFFFF, @"player close restores page");
        show(player);
        trackURI = @"spotify:track:two";
        [observer playerStateDidChange:SGPlayerState()];
        rgb(0x123456, @"new track without cover falls back to pick");
        coverTrack = trackURI; cover = [UIImage new];
        [NSNotificationCenter.defaultCenter postNotificationName:SGRNowPlayingArtworkDidChangeNotification object:nil];
        trackURI = @"spotify:track:three";
        [observer playerStateDidChange:SGPlayerState()];
        deliver(0, UIColor.yellowColor);
        rgb(0x123456, @"late previous track palette ignored");

        show(a);
        SGRAccentPublishPageColor(a.view, UIColor.blackColor);
        NSInteger result = SGRAccentRGB();
        double luminance = .2126*linear(((result>>16)&255)/255.0)+.7152*linear(((result>>8)&255)/255.0)+.0722*linear((result&255)/255.0);
        expect((luminance+.05)/.12 >= 4.5, @"dark artwork accent reaches 4.5:1 against the darkest allowed field boundary");
        expect((luminance+.05)/.05 >= 4.5, @"black glyph on automatic accent remains readable");
        settings(NO);
        rgb(0x123456, @"off restores exact picked color");
        expect(colorRGB(label.textColor) == 0x123456, @"live text returns to picked color");
        expect(SGRPickedAccentRGB() == 0x123456, @"automatic never overwrites saved pick");
        expect(SGInt(@"spotifyglass.accent", -1) == 0xABCDEF, @"Native accent is untouched");
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGRKeyAccent:@(-1),SGRKeyAccentAuto:@NO} forName:NSArgumentDomain];
        SGRAccentPreferencesChanged();
        expect(!SGRAccentSubstitutionEnabled() && SGRAccentColor() == nil &&
               colorRGB(label.textColor) == 0x1ED760, @"entering Spotify restores existing tokens");
        UIView *offControl = [UIView new];
        offControl.tintColor = [UIColor colorWithRed:30/255.0 green:215/255.0 blue:96/255.0 alpha:1];
        UILabel *offLabel = [UILabel new];
        offLabel.textColor = [[UIColor alloc] initWithRed:29/255.0 green:185/255.0 blue:84/255.0 alpha:1];
        UIView *offDerived = [UIView new];
        offDerived.backgroundColor = [offControl.tintColor colorWithAlphaComponent:.5];
        CAShapeLayer *offShape = [CAShapeLayer layer];
        CGColorSpaceRef offSpace = CGColorSpaceCreateDeviceRGB();
        CGColorRef offGreen = CGColorCreate(offSpace, components);
        offShape.fillColor = offGreen;
        CABasicAnimation *offBasic = [CABasicAnimation animationWithKeyPath:@"fillColor"];
        offBasic.fromValue = (__bridge id)offGreen;
        CAKeyframeAnimation *offKeys = [CAKeyframeAnimation animationWithKeyPath:@"fillColor"];
        offKeys.values = @[(__bridge id)UIColor.blueColor.CGColor, (__bridge id)offGreen];
        CGColorRelease(offGreen); CGColorSpaceRelease(offSpace);
        expect(colorRGB(offControl.tintColor) == 0x1ED760 && colorRGB(offLabel.textColor) == 0x1DB954 &&
               colorRGB([UIColor colorWithCGColor:offShape.fillColor]) == 0x1ED760,
               @"off-interval assignments render exact stock greens");
        CGFloat offR=29/255.0, offG=185/255.0, offB=84/255.0;
        expect(!SGRAccentSwap(&offR,&offG,&offB) && offR==29/255.0 && offG==185/255.0 && offB==84/255.0,
               @"component substitution remains off despite provenance tracking");
        SGRAccentPublishPageColor(a.view, UIColor.yellowColor);
        settings(YES);
        expect(SGRAccentSubstitutionEnabled() && colorRGB(label.textColor) == 0xFFFF00 &&
               colorRGB([UIColor colorWithCGColor:shape.fillColor]) == 0xFFFF00,
               @"accent launch restores Automatic live after switching to Spotify");
        expect(colorRGB(offControl.tintColor) == 0xFFFF00 && colorRGB(offLabel.textColor) == 0xDBDB00 &&
               colorRGB([UIColor colorWithCGColor:offShape.fillColor]) == 0xFFFF00,
               @"colors assigned while stock recolor when Automatic returns");
        CGFloat derivedAlpha;
        [offDerived.backgroundColor getRed:NULL green:NULL blue:NULL alpha:&derivedAlpha];
        expect(colorRGB(offDerived.backgroundColor) == 0xFFFF00 && derivedAlpha == .5,
               @"alpha derivation while stock retains live color and opacity");
        [offShape addAnimation:offBasic forKey:@"off.basic"];
        [offShape addAnimation:offKeys forKey:@"off.keys"];
        expect(colorRGB([UIColor colorWithCGColor:(__bridge CGColorRef)[(CABasicAnimation *)[offShape animationForKey:@"off.basic"] fromValue]]) == 0xFFFF00 &&
               colorRGB([UIColor colorWithCGColor:(__bridge CGColorRef)[(CAKeyframeAnimation *)[offShape animationForKey:@"off.keys"] values][1]]) == 0xFFFF00,
               @"animations authored while stock resolve the accent on later submission");
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGRKeyAccent:@(-1),SGRKeyAccentAuto:@NO} forName:NSArgumentDomain];
        SGRAccentPreferencesChanged();
        expect(colorRGB(label.textColor) == 0x1ED760, @"second Spotify switch restores original token components");
        settings(NO);
        expect(SGRAccentSubstitutionEnabled() && colorRGB(label.textColor) == 0x123456 &&
               colorRGB([UIColor colorWithCGColor:shape.fillColor]) == 0x123456,
               @"accent launch restores a custom accent live after switching to Spotify");
        expect(colorRGB(offControl.tintColor) == 0x123456 && colorRGB(offLabel.textColor) == 0x0F2D4A &&
               colorRGB([UIColor colorWithCGColor:offShape.fillColor]) == 0x123456,
               @"off-interval colors also follow the custom pick with their original shade");
        printf("appearance accent: %lu checks passed\n", (unsigned long)checks);
    }
    return 0;
}

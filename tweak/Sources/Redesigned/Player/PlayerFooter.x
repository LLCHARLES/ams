// Player redesign: the footer as the Music app's row of three glyphs, lyrics, devices and queue, spread
// evenly across the player, and no share button.
//
// Spotify's footer is Connect with the device's name at the leading edge, share, and the queue at the
// trailing edge. Connect and the queue stay Spotify's controls (the device sheet, the remote device
// tint, the Jam avatars) and are only moved, by a translation of the arranged view that holds each: a
// transform survives the stack view laying them out again, and moving the holder keeps its touches
// inside its own bounds. The device name goes transparent, since the glyph alone sits in the middle, and
// Connect's holder takes touches only in a square over the glyph (SGRPlayerCoverConnect).
// Both draw the Music app's glyphs (issue #109): a stand-in inside each of Spotify's glyph views, so it is hidden,
// faded and pulsed with Spotify's own, while Spotify's drawing goes clear at its source. Connect's is the output's
// device, as the Music app's is (AirPlay audio on the phone, the AirPods by model, a HomePod, a Mac...), with the
// device's name on a line under the row; a tap on it opens the system's AirPlay picker and a press held opens
// Spotify's Connect sheet (SGRRoutePicker). Connect's glyph is an image Spotify draws the color into: each new one is
// read once for that color, which says only whether a Connect device is in use (the stand-in keeps the row's color),
// and is swapped for a clear image of its size. The queue's is an SPTEncoreIconView: its foreground colors are kept
// for the stand-in and Spotify's drawn clear.
// Spotify has no lyrics control down here, so that one is the Kit's glyph button, and it turns the
// lyrics in the player on and off (PlayerLyrics.x): filled while they are up, dimmed and dead for a
// track that has none.
//
// The row sits lower than Spotify puts it, just over the home indicator the way the Music app's does
// (issue #54): the footer unit's view is translated down, the controls follow it part of the way, and a
// band of the redesign's hands the touches below the bottom stack's bounds back to the row.
//
// Tree (trees/clean/player/01.txt:295-320): FooterElementsUnit's view 402x44 > UIStackView 382x44 >
// ElementView > ConnectButtonOutputSwitcherViewHolder id=Components.ConnectButtonOutputSwitcher 153x36
// (a 19x19 UIImageView glyph and a MarqueeLabel with the device name), a spacer, a hidden media trimmer,
// ElementView > EncoreButton id=ShareButtonNowPlayingView 44x44, ElementView > Queue control
// id=QueueButtonNowPlaying 47x32 (an 18x18 SPTEncoreIconView id=Encore.IconView glyph, out/rep/ptree.txt:1228-1279).
#import <substrate.h>
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Headers/SPTEncoreIconView.h"
#import "Player.h"

static const CGFloat kLyricsGlyphSize = 20;
// Filled and at full strength while the lyrics are up, the way the Music app marks the control that is on.
static NSString *const kLyricsSymbol = @"quote.bubble", *const kLyricsSymbolOpen = @"quote.bubble.fill";
// Where the three glyphs sit, as parts of the footer's width.
static const CGFloat kLeading = 0.2, kMiddle = 0.5, kTrailing = 0.8;
static const CGFloat kGlyphMaxWidth = 30;
// The route line's middle below the glyphs' (the Music app's, measured on a screenshot).
static const CGFloat kRouteLineDrop = 32;

// Issue #54: Spotify ends its bottom stack 61pt above the screen's bottom (01.txt:127, 576.67 + 236 of
// 874), so the row's middle sat 83pt up, well clear of the home indicator, and the controls crowded it.
// The Music app keeps that row just over the home indicator: its middle this far above the safe area's
// bottom, and never less than kRowMinBottom above the screen's on a phone without a home indicator.
// The Music app's on iOS 27.2 sits higher than it did: its glyphs' middle 31.5pt over the safe area's bottom, with room
// under them for the route line (its owner's screenshot, 2026-10-30).
static const CGFloat kRowAboveSafeArea = 32, kRowMinBottom = 34;
// The controls follow a share of the row's move when nothing stands between them, so the gaps above
// and below them even out instead of all the room opening under them.
static const CGFloat kControlsShare = 0.3;
// The volume row's sides, the player's own margin.
static const CGFloat kVolumeMargin = 24;
// And the controls go up this much over it, so the gaps above and below the volume row match.
static const CGFloat kVolumeLift = 10;

// "airplayaudio" is the name iOS 16 knows; iOS 18 calls it airplay.audio and keeps this one as its alias.
static NSString *const kConnectSymbol = @"airplayaudio", *const kQueueSymbol = @"list.bullet";

static char kConnectKey, kShareKey, kTrimmerKey, kSharedByKey, kQueueKey, kQueueIconKey, kLyricsGlyphKey, kReachKey, kRowKey;
static __weak SGRGlyphButton *sg_lyricsGlyph;

// The view the footer's stack view arranges around `view`.
static UIView *arrangedAround(UIView *view, UIView *host) {
    for (UIView *v = view; v && v != host; v = v.superview) {
        if ([v.superview isKindOfClass:UIStackView.class]) return v;
    }
    return nil;
}

// Where `point` of `view` is in the host with the arranged view's own transform left out.
static CGFloat untransformedX(UIView *arranged, UIView *view, CGPoint point, UIView *host) {
    CGPoint local = [view convertPoint:point toView:arranged];
    CGPoint inRow = CGPointMake(arranged.center.x + local.x - CGRectGetMidX(arranged.bounds), arranged.center.y);
    return [arranged.superview convertPoint:inRow toView:host].x;
}

static CGFloat moveTo(UIView *arranged, UIView *view, CGPoint point, UIView *host, CGFloat x) {
    if (!arranged) return -1;
    CGFloat from = untransformedX(arranged, view, point, host);
    CGAffineTransform transform = CGAffineTransformMakeTranslation(round(x - from), 0);
    if (!CGAffineTransformEqualToTransform(arranged.transform, transform)) arranged.transform = transform;
    return from;
}

#pragma mark - lyrics

void SGRPlayerLyricsChanged(void) {
    SGRPlayerMotionLyricsChanged();
    SGRPlayerVisualiserUpdate();
    SGRGlyphButton *glyph = sg_lyricsGlyph;
    if (!glyph) return;
    BOOL enabled = SGRPlayerLyricsAvailable() || SGRPlayerLyricsOpen(), open = SGRPlayerLyricsOpen();
    BOOL wasOpen = [glyph.glyph.symbol isEqualToString:kLyricsSymbolOpen];
    if (glyph.enabled == enabled && wasOpen == open) return;
    // Lyrics turn up once the player has fetched them, well after the footer laid out: a fade, not a pop.
    // While the player opens or closes the glyph and the lyrics come and go together, so nothing animates.
    BOOL animated = glyph.window && !SGRPlayerIsTransitioning();
    [glyph.glyph setSymbol:open ? kLyricsSymbolOpen : kLyricsSymbol animated:animated];
    void (^mark)(void) = ^{
        glyph.enabled = enabled;
        glyph.glyph.tintColor = open ? SGRPrimary() : SGRSecondary();
    };
    if (animated) SGRAnimate(SGRMotionFade, mark, nil);
    else mark();
}

SGRGlyphButton *SGRPlayerLyricsGlyphIn(UIView *host) {
    SGRGlyphButton *glyph = objc_getAssociatedObject(host, &kLyricsGlyphKey);
    if (!glyph) {
        glyph = [SGRGlyphButton buttonWithSymbol:kLyricsSymbol pointSize:kLyricsGlyphSize title:@"Lyrics"];
        glyph.glyph.tintColor = SGRSecondary();
        glyph.onTap = ^{ SGRPlayerToggleLyrics(); };
        objc_setAssociatedObject(host, &kLyricsGlyphKey, glyph, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (glyph.superview != host) [host addSubview:glyph];
    sg_lyricsGlyph = glyph;
    return glyph;
}

#pragma mark - the Music app's glyphs

static char kStandInKey, kClearKey, kQueueActiveColorKey;

// The Kit's glyph centered inside `drawn`: it takes `drawn`'s hidden, alpha and animations with it.
static SGRGlyphView *standIn(UIView *drawn, NSString *symbol) {
    if (!drawn) return nil;
    SGRGlyphView *glyph = objc_getAssociatedObject(drawn, &kStandInKey);
    if (!glyph) {
        glyph = [[SGRGlyphView alloc] initWithSymbol:symbol pointSize:kLyricsGlyphSize weight:UIImageSymbolWeightRegular];
        glyph.userInteractionEnabled = NO;
        glyph.isAccessibilityElement = NO;
        glyph.tintColor = SGRSecondary();   // at rest, as the Lyrics glyph while it is off
        // Kept centered when Spotify resizes the view between the footer's passes (a new Connect image of another size).
        glyph.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin
                               | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        objc_setAssociatedObject(drawn, &kStandInKey, glyph, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (glyph.superview != drawn) [drawn addSubview:glyph];
    CGPoint middle = CGPointMake(CGRectGetMidX(drawn.bounds), CGRectGetMidY(drawn.bounds));
    if (!CGPointEqualToPoint(glyph.center, middle)) glyph.center = middle;
    return glyph;
}

// The color Spotify drew its glyph in (SGRPlayerImageInk, kept on the image, so an image Spotify hands over again costs
// a lookup). One drawn from the tint answers the tint.
static UIColor *inkOf(UIImageView *view, UIImage *image) {
    if (image.isSymbolImage || image.renderingMode == UIImageRenderingModeAlwaysTemplate) return view.tintColor;
    return SGRPlayerImageInk(image) ?: SGRPrimary();
}

// A lit glyph as a bitmap in its color, the way Spotify draws its own: Follow the cover finds lit controls by their
// pixels, and a symbol image has none to read. The symbol's alignment insets are kept, so it sits where it did.
// Drawn in the glyph's traits (Bold Text, contrast), as its template image is.
static UIImage *litImage(SGRGlyphView *glyph, UIImage *symbol, UIColor *color) {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat formatForTraitCollection:glyph.traitCollection];
    format.scale = symbol.scale;
    UIImage *tinted = [symbol imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal];
    __block UIImage *bitmap;
    [glyph.traitCollection performAsCurrentTraitCollection:^{
        bitmap = [[[UIGraphicsImageRenderer alloc] initWithSize:symbol.size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [tinted drawAtPoint:CGPointZero];
        }];
    }];
    return [bitmap imageWithAlignmentRectInsets:symbol.alignmentRectInsets];
}

// The middle glyph is the output's, as the Music app's is: AirPlay audio on the phone, AirPods, headphones, a HomePod,
// a car (its owner's screenshots, 2026-10-30). iOS gives an app the route's type and name and, through AVFoundation's
// output devices, a kind (AVOutputDevice's deviceSubType, 2 for the AirPods, 12 for a HomePod mini, the phone's log);
// the model and the system's own symbol name come back empty, so AirPods are told apart by their name and a HomePod
// is drawn as the full-size one until MediaPlayer names its model (fetchPicked). A Spotify Connect device plays with the phone's own route, so it keeps AirPlay, lit.
typedef NS_ENUM(NSInteger, SGROutputKind) { SGROutputKindHeadphones = 2, SGROutputKindHeadset = 3, SGROutputKindTV = 11, SGROutputKindHomePod = 12, SGROutputKindAppleTV = 13, SGROutputKindCar = 14 };

// A Spotify Connect device in use (Spotify lights its glyph) and its name, from Spotify's label inside Connect: it plays
// over the network while iOS's own route can stay where it was (a HomePod, its owner's recording, 2026-10-30), so it
// comes before the route.
static NSString *sg_spotifyDeviceName;
static BOOL sg_connectLit;

// The AirPlay route MediaPlayer says is picked, its name and its model (fetchPicked). Stale from a route change until the
// next answer: two AirPlay routes can both be named "AirPlay", so the last answer may be the other device's.
static NSString *sg_pickedName, *sg_pickedProduct, *sg_pickedFor;
static BOOL sg_pickedStale;

// The output device playing: the one named as the route is, or, for an AirPlay route iOS names only "AirPlay" (the
// phone's log, 2026-10-30), the AirPlay one (deviceType 0) among them. The context's list can hold more than one.
static id outputDevice(AVAudioSessionPortDescription *port) {
    @try {
        Class contextClass = NSClassFromString(@"AVOutputContext");
        if (![contextClass respondsToSelector:@selector(sharedSystemAudioContext)]) return nil;
        NSArray *devices = [[contextClass performSelector:@selector(sharedSystemAudioContext)] valueForKey:@"outputDevices"];
        id named = nil, airPlay = nil;
        NSMutableString *list = [NSMutableString string];
        for (id device in devices) {
            if ([[device valueForKey:@"name"] isEqual:port.portName]) named = device;
            if (!airPlay && [[device valueForKey:@"deviceType"] integerValue] == 0) airPlay = device;
            [list appendFormat:@" [%@ %@/%@]", [device valueForKey:@"name"], [device valueForKey:@"deviceType"], [device valueForKey:@"deviceSubType"]];
        }
        static NSString *told;
        NSString *line = [NSString stringWithFormat:@"%@ (%@):%@", port.portName, port.portType, list];
        if (![told isEqualToString:line]) {
            told = line;
            SGLog(@"DIAG output devices for %@, picked %@ (%@)", line, sg_pickedName, sg_pickedStale ? @"stale" : @"current");
        }
        if (named) return named;
        return [port.portType isEqualToString:AVAudioSessionPortAirPlay] ? airPlay : (devices.count == 1 ? devices.firstObject : nil);
    } @catch (NSException *e) {
        return nil;
    }
}

static NSInteger kindOf(id device) {
    @try { return device ? [[device valueForKey:@"deviceSubType"] integerValue] : -1; } @catch (NSException *e) { return -1; }
}

// The output's name, where iOS names the route only "AirPlay": MediaPlayer's answer while it is this route's, else
// AVFoundation's device (`device`, outputDevice's), which follows a switch at once.
static NSString *outputName(AVAudioSessionPortDescription *port, id device) {
    if (![port.portType isEqualToString:AVAudioSessionPortAirPlay]) return port.portName;
    BOOL generic = [port.portName isEqualToString:@"AirPlay"] || !port.portName.length;
    if (!generic) return port.portName;
    if (sg_pickedName.length && !sg_pickedStale) return sg_pickedName;
    NSString *name = nil;
    @try { name = [device valueForKey:@"name"]; } @catch (NSException *e) {}
    if ([name isKindOfClass:NSString.class] && name.length) return name;
    return sg_pickedName.length ? sg_pickedName : port.portName;
}

// The AirPlay route playing, as MediaPlayer's routing controller has it: its name, which iOS's own route can leave as
// "AirPlay" for good (the phone's log, 2026-10-30), and its model, which AVFoundation leaves out for an app
// (MPAVOutputDeviceRoute's productIdentifier, AudioAccessory1,1 for the owner's HomePod). Fetched once per AirPlay
// route, with discovery on only while the routes are fetched, and the glyph drawn again when it comes.
static void paintConnectAgain(void);

// Each output's model as MediaPlayer's routes name it (MRAVOutputDevice's modelID: BTHeadphones76,8240 for a pair of
// AirPods, AudioAccessory1,1 for a HomePod, MacBookPro18,3), kept by the output's name across launches. iOS names a
// Bluetooth device's model only while it is not the one playing (the phone's log, 2026-10-30: none for the AirPods Pro
// in use, Caitlin's named), so what was seen before is what draws it.
// Only devices this phone has played to are kept (kOutputsUsedKey), not every one discovery finds nearby, and no more
// than kOutputModelsMax of them.
static NSString *const kOutputModelsKey = @"spotifyglass.redesign.outputModels", *const kOutputsUsedKey = @"spotifyglass.redesign.outputsUsed";
static const NSUInteger kOutputModelsMax = 24;
static NSMutableDictionary<NSString *, NSString *> *sg_outputModels;
static NSMutableOrderedSet<NSString *> *sg_outputsUsed;

static NSMutableOrderedSet<NSString *> *outputsUsed(void) {
    if (!sg_outputsUsed) {
        NSArray *stored = [NSUserDefaults.standardUserDefaults arrayForKey:kOutputsUsedKey];
        sg_outputsUsed = stored ? [NSMutableOrderedSet orderedSetWithArray:stored] : [NSMutableOrderedSet orderedSet];
    }
    return sg_outputsUsed;
}

static NSMutableDictionary<NSString *, NSString *> *outputModels(void);

// An output played to, the most recent last; the oldest beyond the limit is forgotten with its model.
static void markOutputUsed(NSString *name) {
    if (!name.length || [name isEqualToString:@"AirPlay"]) return;
    NSMutableOrderedSet *used = outputsUsed();
    if ([used.lastObject isEqual:name]) return;
    [used removeObject:name];
    [used addObject:name];
    BOOL forgot = NO;
    while (used.count > kOutputModelsMax) {
        forgot = [outputModels() objectForKey:used.firstObject] != nil || forgot;
        [outputModels() removeObjectForKey:used.firstObject];
        [used removeObjectAtIndex:0];
    }
    [NSUserDefaults.standardUserDefaults setObject:used.array forKey:kOutputsUsedKey];
    if (forgot) [NSUserDefaults.standardUserDefaults setObject:outputModels() forKey:kOutputModelsKey];
}

static NSMutableDictionary<NSString *, NSString *> *outputModels(void) {
    if (!sg_outputModels) {
        NSDictionary *stored = [NSUserDefaults.standardUserDefaults dictionaryForKey:kOutputModelsKey];
        sg_outputModels = stored ? [stored mutableCopy] : [NSMutableDictionary dictionary];
    }
    return sg_outputModels;
}

static void rememberModels(NSArray *routes) {
    NSMutableDictionary *models = outputModels();
    BOOL changed = NO;
    for (id route in routes) {
        @try {
            NSString *name = [route valueForKey:@"routeName"];
            id device = [route valueForKey:@"outputDevice"];
            NSString *model = [device respondsToSelector:@selector(modelID)] ? [device valueForKey:@"modelID"] : nil;
            if (![name isKindOfClass:NSString.class] || ![outputsUsed() containsObject:name]) continue;
            if (![model isKindOfClass:NSString.class] || !model.length || [models[name] isEqualToString:model]) continue;
            models[name] = model;
            changed = YES;
            SGLog(@"redesign player: %@ is a %@", name, model);
        } @catch (NSException *e) {}
    }
    if (changed) [NSUserDefaults.standardUserDefaults setObject:models forKey:kOutputModelsKey];
}

// Apple's Bluetooth product IDs (BTHeadphones76,<id>), drawn as the system's menu draws them; a newer ID than these is a
// newer pair, drawn as the newest of its kind.
static NSString *symbolForHeadphones(NSString *model, NSString *name) {
    NSString *prefix = @"BTHeadphones76,";
    if (![model hasPrefix:prefix]) return nil;
    NSInteger product = [[model substringFromIndex:prefix.length] integerValue];
    // SF Symbols' own names, as iOS 27 has them.
    switch (product) {
        case 0x2002: case 0x200F: return @"airpods";
        case 0x2013: return @"airpods.gen3";
        case 0x2019: case 0x201B: return @"airpods.gen4";
        // The first and second generation look alike and share one artwork; the third has its own (the Music app draws
        // the owner's AirPods Pro 2 as airpods.pro.gen1, iOS 27.2, 2026-10-30).
        case 0x200E: case 0x2014: case 0x2024: return @"airpods.pro.gen1";
        case 0x2027: return @"airpods.pro.gen3";
        case 0x200A: case 0x201F: return @"airpods.max";
        case 0x2003: return @"beats.powerbeats3";
        case 0x200D: return @"beats.powerbeats";
        case 0x200B: return @"beats.powerbeats.pro";
        case 0x2012: return @"beats.fit.pro";
        case 0x2011: return @"beats.studiobuds";
        case 0x2016: return @"beats.studiobuds.plus";
        case 0x2006: case 0x2009: case 0x200C: case 0x2017: return @"beats.headphones";
    }
    NSString *lower = name.lowercaseString;
    if ([lower containsString:@"airpods"] && product > 0x2024) {
        if ([lower containsString:@"max"]) return @"airpods.max";
        if ([lower containsString:@"pro"]) return @"airpods.pro.gen3";
        return @"airpods.gen4";
    }
    return nil;
}

static id sg_routing;
static NSUInteger sg_fetchToken;

// Discovery off again, only by the fetch that turned it on last: an earlier one's answer switched it off under a later
// fetch still running.
static void endDiscovery(NSUInteger token) {
    if (token != sg_fetchToken || !sg_routing) return;
    @try { ((void (*)(id, SEL, NSInteger))objc_msgSend)(sg_routing, @selector(setDiscoveryMode:), 0); } @catch (NSException *e) {}
}

static NSUInteger sg_fetchAttempt;

static void fetchPicked(AVAudioSessionPortDescription *port) {
    if (!port.UID || [sg_pickedFor isEqualToString:port.UID]) return;
    sg_pickedFor = port.UID;
    NSUInteger token = ++sg_fetchToken, attempt = sg_fetchAttempt;
    sg_fetchAttempt = 0;
    NSString *portType = port.portType;
    // The last answer stays until the new one comes, used only while its name fits the route (outputSymbol): cleared at
    // once, every switch drew a speaker for a moment (the phone's log, 2026-10-30).
    Class controllerClass = NSClassFromString(@"MPAVRoutingController");
    SEL fetch = NSSelectorFromString(@"fetchAvailableRoutesWithCompletionHandler:");
    @try {
        if (!sg_routing && controllerClass) sg_routing = ((id (*)(id, SEL, NSString *))objc_msgSend)([controllerClass alloc], @selector(initWithName:), @"vitrine");
        id controller = sg_routing;
        if (![controller respondsToSelector:fetch] || ![controller respondsToSelector:@selector(setDiscoveryMode:)]) return;
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(controller, @selector(setDiscoveryMode:), 3);
        // Never left on: a fetch that does not answer has discovery ended for it.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ endDiscovery(token); });
        ((void (*)(id, SEL, id))objc_msgSend)(controller, fetch, ^(NSArray *routes) {
            dispatch_async(dispatch_get_main_queue(), ^{
                endDiscovery(token);
                if (token != sg_fetchToken) return;
                @try {
                    id picked = [controller valueForKey:@"pickedRoute"];
                    NSString *name = [picked valueForKey:@"routeName"];
                    // MediaPlayer can still answer with the route before (a pair of AirPods while AirPlay already plays,
                    // the phone's log, 2026-10-30): an AirPlay route takes only an AirPlay answer, asked again a moment later.
                    BOOL wantAirPlay = [portType isEqualToString:AVAudioSessionPortAirPlay];
                    BOOL airPlay = [picked respondsToSelector:@selector(isAirPlayRoute)] && [[picked valueForKey:@"isAirPlayRoute"] boolValue];
                    if (!airPlay) for (id route in routes) {
                        if ([[route valueForKey:@"routeName"] isEqual:name] && [route respondsToSelector:@selector(isAirPlayRoute)])
                            airPlay = [[route valueForKey:@"isAirPlayRoute"] boolValue];
                    }
                    // A placeholder of iOS's while a route is handed over (its owner's screenshot, 2026-10-30), no device's.
                    if ([name isEqual:@"AirPlayHandoffDevice"]) airPlay = NO;
                    if (wantAirPlay && !airPlay) {
                        if (attempt < 3) {
                            sg_pickedFor = nil;
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                if (token == sg_fetchToken) {
                                    sg_fetchAttempt = attempt + 1;
                                    paintConnectAgain();
                                }
                            });
                        }
                        return;
                    }
                    // The picked route can be another class with no model (the phone's log, 2026-10-30): its model is
                    // on the route of that name in the list.
                    NSString *product = nil;
                    rememberModels(routes);
                    for (id route in routes) {
                        if (![[route valueForKey:@"routeName"] isEqual:name] || ![route respondsToSelector:@selector(productIdentifier)]) continue;
                        product = [route valueForKey:@"productIdentifier"];
                        if ([product isKindOfClass:NSString.class] && product.length) break;
                    }
                    sg_pickedName = [name isKindOfClass:NSString.class] ? name : nil;
                    sg_pickedProduct = [product isKindOfClass:NSString.class] ? product : nil;
                    sg_pickedStale = NO;
                } @catch (NSException *e) {}
                SGLog(@"redesign player: AirPlay to %@, a %@", sg_pickedName ?: @"a route MediaPlayer did not name", sg_pickedProduct ?: @"model it did not name");
                paintConnectAgain();
            });
        });
    } @catch (NSException *e) {}
}

static NSString *symbolForProduct(NSString *product) {
    if ([product hasPrefix:@"AudioAccessory5"]) return @"homepod.mini.fill";
    if ([product hasPrefix:@"AudioAccessory6"]) return @"homepod.2.fill";
    if ([product hasPrefix:@"AudioAccessory"]) return @"homepod.fill";
    if ([product hasPrefix:@"AppleTV"]) return @"appletv.fill";
    if ([product hasPrefix:@"MacBook"]) return @"macbook";
    if ([product hasPrefix:@"iMac"]) return @"desktopcomputer";
    if ([product hasPrefix:@"Macmini"]) return @"macmini.fill";
    if ([product hasPrefix:@"Mac"]) return @"desktopcomputer";
    if ([product hasPrefix:@"iPad"]) return @"ipad";
    if ([product hasPrefix:@"iPhone"]) return @"iphone";
    return nil;
}

// A device's symbol from the system's own catalogue: asked by name the usual way, iOS answers as the SDK Spotify is built
// with (iOS 26), which lacks iOS 27's names and draws airpods.pro as it was; read from CoreGlyphs itself, it has them all
// (the phone, iOS 27.2, 2026-10-30).
static UIImage *deviceSymbol(NSString *name, UIImageConfiguration *config) {
    static NSBundle *glyphs;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ glyphs = [NSBundle bundleWithPath:@"/System/Library/CoreServices/CoreGlyphs.bundle"]; });
    UIImage *image = glyphs ? [UIImage imageNamed:name inBundle:glyphs withConfiguration:config] : nil;
    return image.isSymbolImage ? image : [UIImage systemImageNamed:name withConfiguration:config];
}

// Whether this iOS has the symbol, asked once per name.
static BOOL hasDeviceSymbol(NSString *name) {
    static NSMutableDictionary<NSString *, NSNumber *> *known;
    if (!known) known = [NSMutableDictionary dictionary];
    NSNumber *has = known[name];
    if (!has) known[name] = has = @(deviceSymbol(name, nil) != nil);
    return has.boolValue;
}

// The Spotify Connect device in use, if Spotify's lit glyph names one while the phone's own sound stays on its speaker:
// Spotify lights its glyph for every output that is not the speaker, naming it "AirPlay", "Wired Connection" or a handoff
// placeholder (the phone, 2026-10-30), and those are the route's, which the route draws itself.
static NSString *spotifyConnectName(AVAudioSessionPortDescription *port) {
    NSString *name = sg_spotifyDeviceName;
    BOOL speaker = !port || [port.portType isEqualToString:AVAudioSessionPortBuiltInSpeaker] || [port.portType isEqualToString:AVAudioSessionPortBuiltInReceiver];
    return speaker && sg_connectLit && name.length ? name : nil;
}

static NSString *outputSymbol(void) {
    AVAudioSessionPortDescription *port = AVAudioSession.sharedInstance.currentRoute.outputs.firstObject;
    NSString *type = port.portType, *name = port.portName.lowercaseString ?: @"";
    NSString *symbol = kConnectSymbol;
    NSString *connectName = spotifyConnectName(port);
    if (connectName) {
        // A Spotify Connect device: drawn by the model remembered for its name (a Mac played to over AirPlay before),
        // else as AirPlay.
        markOutputUsed(connectName);
        NSString *model = outputModels()[connectName];
        symbol = symbolForProduct(model) ?: symbolForHeadphones(model, connectName) ?: kConnectSymbol;
    } else if ([type isEqualToString:AVAudioSessionPortHeadphones] || [type isEqualToString:AVAudioSessionPortUSBAudio]
               || [type isEqualToString:AVAudioSessionPortLineOut]) {
        // Wired, through the headphone jack, an adapter, or USB-C earphones: drawn as EarPods (its owner's pick, 2026-10-30).
        symbol = @"earpods";
    } else if ([type isEqualToString:AVAudioSessionPortCarAudio]) {
        symbol = @"car.fill";
    } else if ([type isEqualToString:AVAudioSessionPortHDMI]) {
        symbol = @"tv.fill";
    } else if ([type isEqualToString:AVAudioSessionPortBluetoothA2DP] || [type isEqualToString:AVAudioSessionPortBluetoothLE]
               || [type isEqualToString:AVAudioSessionPortBluetoothHFP]) {
        markOutputUsed(port.portName);
        fetchPicked(port);
        NSString *known = symbolForHeadphones(outputModels()[port.portName], port.portName);
        // By name until the model is known; the first and second AirPods Pro share airpods.pro.gen1, as the Music app
        // draws them, airpods.pro being the third's.
        if (known) symbol = known;
        else if ([name containsString:@"airpods max"]) symbol = @"airpods.max";
        else if ([name containsString:@"airpods pro"]) symbol = @"airpods.pro.gen1";
        else if ([name containsString:@"airpods"]) symbol = @"airpods";
        else if ([name containsString:@"beats"]) symbol = @"beats.headphones";
        else {
            NSInteger kind = kindOf(outputDevice(port));
            if (kind == SGROutputKindCar) symbol = @"car.fill";
            else if (kind == SGROutputKindHeadphones || kind == SGROutputKindHeadset) symbol = @"headphones";
            else symbol = @"hifispeaker.fill";
        }
    } else if ([type isEqualToString:AVAudioSessionPortAirPlay]) {
        id device = outputDevice(port);
        NSString *deviceName = outputName(port, device);
        markOutputUsed(deviceName);
        fetchPicked(port);
        // The model remembered for the output's name draws it at once; MediaPlayer's answer, while it is this route's, after.
        BOOL fits = !sg_pickedStale && ([port.portName isEqualToString:sg_pickedName] || [port.portName isEqualToString:@"AirPlay"]);
        NSString *modelSymbol = symbolForProduct(outputModels()[deviceName]) ?: (fits ? symbolForProduct(sg_pickedProduct) : nil);
        NSInteger kind = modelSymbol ? -1 : kindOf(device);
        if (modelSymbol) symbol = modelSymbol;
        // Not yet known (iOS's list and MediaPlayer's answer can trail a switch): AirPlay's own glyph until they come.
        else if (kind < 0 && sg_pickedStale) symbol = kConnectSymbol;
        else if (kind == SGROutputKindHomePod) symbol = @"homepod.fill";
        else if (kind == SGROutputKindAppleTV) symbol = @"appletv.fill";
        else if (kind == SGROutputKindTV) symbol = @"tv.fill";
        else symbol = @"hifispeaker.fill";
    }
    // A name an older iOS lacks falls back to its older name, then to AirPlay.
    static NSDictionary<NSString *, NSString *> *older;
    if (!older) older = @{@"airpods.pro.gen1": @"airpodspro", @"airpods.pro.gen3": @"airpods.pro", @"airpods.pro": @"airpodspro",
                          @"airpods.max": @"airpodsmax", @"airpods.gen4": @"airpods.gen3", @"airpods.gen3": @"airpods",
                          @"homepod.2.fill": @"homepod.fill", @"homepod.mini.fill": @"homepodmini.fill", @"beats.fit.pro": @"beats.fitpro",
                          @"beats.studiobuds.plus": @"beats.studiobuds", @"macbook": @"laptopcomputer", @"beats.powerbeats.pro": @"beats.powerbeats", @"beats.powerbeats3": @"beats.powerbeats"};
    while (!hasDeviceSymbol(symbol) && older[symbol]) symbol = older[symbol];
    if (!hasDeviceSymbol(symbol)) symbol = kConnectSymbol;
    static NSString *told;
    NSString *line = [NSString stringWithFormat:@"%@ (%@), drawn as %@", port.portType, port.portName, symbol];
    if (![told isEqualToString:line]) {
        told = line;
        SGLog(@"redesign player: output %@", line);
    }
    return symbol;
}

// The line under the row, the Music app's: the device's name, nothing on the phone's own speaker (its owner's
// screenshots, 2026-10-30; the Music app's "iPhone → " before an AirPlay one left out, its owner's pick). A Spotify
// Connect device plays from the phone's speaker route with Spotify's glyph lit, and is named by Spotify's own label
// inside Connect, hidden in the row.
static NSHashTable<UILabel *> *sg_routeLines;

static NSString *routeText(void) {
    AVAudioSessionPortDescription *port = AVAudioSession.sharedInstance.currentRoute.outputs.firstObject;
    NSString *connectName = spotifyConnectName(port);
    if (connectName) return connectName;
    NSString *type = port.portType;
    if (!port || [type isEqualToString:AVAudioSessionPortBuiltInSpeaker] || [type isEqualToString:AVAudioSessionPortBuiltInReceiver]) return nil;
    return outputName(port, outputDevice(port));
}

static void updateRouteLine(void) {
    if (!sg_routeLines.count) return;
    NSString *text = routeText() ?: @"";
    for (UILabel *line in sg_routeLines.allObjects) {
        if (![line.text isEqualToString:text]) line.text = text;
        line.hidden = text.length == 0;
    }
}

static char kConnectInkKey;
// Every Connect glyph standing in: the ordinary player's and the AI DJ's (DJPlayer.x) can both be up.
static NSHashTable<UIImageView *> *sg_connectsDrawn;
static void paintConnect(UIImageView *drawn);
static void paintConnectAgain(void) {
    for (UIImageView *drawn in sg_connectsDrawn.allObjects) paintConnect(drawn);
}

// The stand-in in the output's glyph, lit in the ink Spotify last drew its own in.
static void paintConnect(UIImageView *drawn) {
    SGRGlyphView *glyph = objc_getAssociatedObject(drawn, &kStandInKey);
    if (!glyph) return;
    // Spotify lights its glyph for a Connect device in use; the stand-in keeps the row's color, as the Music app's device
    // glyph does (its owner, 2026-10-30), and the light says the device is Spotify's (outputSymbol, routeText).
    UIColor *ink = objc_getAssociatedObject(drawn, &kConnectInkKey);
    sg_connectLit = ink && SGRPlayerAccentLike(ink);
    NSString *want = outputSymbol();
    if (![glyph.symbol isEqualToString:want]) [glyph setSymbol:want animated:NO];
    UIImage *symbol = deviceSymbol(want, glyph.preferredSymbolConfiguration);
    updateRouteLine();
    glyph.image = symbol;
}

// Spotify's new Connect glyph: its color onto the stand-in, drawn into the stand-in's image so Follow the cover
// repaints it the way it did Spotify's, and a clear image of the same size in its place, so nothing moves.
static void takeConnectImage(UIImageView *drawn) {
    UIImage *image = drawn.image;
    UIImage *clear = objc_getAssociatedObject(drawn, &kClearKey);
    if (!image.CGImage || image == clear) return;
    objc_setAssociatedObject(drawn, &kConnectInkKey, inkOf(drawn, image), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    paintConnect(drawn);
    if (!clear || !CGSizeEqualToSize(clear.size, image.size) || clear.scale != image.scale) {
        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
        format.scale = image.scale;
        clear = [[[UIGraphicsImageRenderer alloc] initWithSize:image.size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {}];
        objc_setAssociatedObject(drawn, &kClearKey, clear, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    drawn.image = clear;
}

// Spotify draws a new glyph when the device changes, with no layout pass of the footer to tell it, so its setImage:
// tells the stand-in; the clear image set back in reports too, and stops there. Each pass looks too, at the cost of a
// compare, for a view the image cannot be watched on.
static void standInForConnect(UIImageView *drawn) {
    BOOL made = objc_getAssociatedObject(drawn, &kStandInKey) != nil;
    if (!standIn(drawn, kConnectSymbol)) return;
    if (!sg_connectsDrawn) sg_connectsDrawn = [NSHashTable weakObjectsHashTable];
    [sg_connectsDrawn addObject:(UIImageView *)drawn];
    takeConnectImage(drawn);
    if (!made) SGRObserveImage(drawn, ^(UIImageView *view) { takeConnectImage(view); });
}

// The queue's state as Spotify sets it, for the stand-in; Spotify's own glyph is drawn in clear.
static void tintQueueStandIn(SPTEncoreIconView *icon) {
    SGRGlyphView *glyph = objc_getAssociatedObject(icon, &kStandInKey);
    // Lit by Spotify's own state, not by a color a cover could make look gray. Lit, it is drawn in the color, as Connect
    // is, so Follow the cover finds it by its pixels and repaints it.
    UIColor *active = objc_getAssociatedObject(icon, &kQueueActiveColorKey);
    UIImage *symbol = [UIImage systemImageNamed:glyph.symbol withConfiguration:glyph.preferredSymbolConfiguration];
    BOOL lit = icon.isActive && active;
    glyph.image = lit ? litImage(glyph, symbol, active) : symbol;
    if (lit) SGRPlayerPaintCover(glyph);
}

static void standInForQueue(SPTEncoreIconView *icon) {
    if (![icon isKindOfClass:%c(SPTEncoreIconView)]) return;
    BOOL made = objc_getAssociatedObject(icon, &kStandInKey) != nil;
    if (!standIn(icon, kQueueSymbol) || made) return;
    UIColor *color = icon.foregroundColor, *active = icon.activeForegroundColor;
    // Through the setters below, which now keep each color and hand Spotify's drawing clear.
    if (color) icon.foregroundColor = color;
    if (active) icon.activeForegroundColor = active;
    tintQueueStandIn(icon);
}

%hook SPTEncoreIconView
// The stand-in does not take the color at rest, only the active one.
- (void)setForegroundColor:(UIColor *)color {
    %orig(objc_getAssociatedObject(self, &kStandInKey) ? UIColor.clearColor : color);
}
- (void)setActiveForegroundColor:(UIColor *)color {
    BOOL ours = objc_getAssociatedObject(self, &kStandInKey) != nil;
    if (ours) objc_setAssociatedObject(self, &kQueueActiveColorKey, color, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig(ours ? UIColor.clearColor : color);
    if (ours) tintQueueStandIn(self);
}
- (void)setIsActive:(BOOL)active {
    %orig;
    if (objc_getAssociatedObject(self, &kStandInKey)) tintQueueStandIn(self);
}
%end

#pragma mark - the row

static UIView *connectGlyphIn(UIView *holder) {
    __block UIView *glyph = nil;
    SGForEachView(holder, ^(UIView *view) {
        if (!glyph && [view isKindOfClass:UIImageView.class] && ![view isKindOfClass:SGRGlyphView.class]
            && view.bounds.size.width > 0 && view.bounds.size.width <= kGlyphMaxWidth) glyph = view;
    });
    return glyph;
}

// Connect is Spotify's control as wide as the device's name, with the glyph near its leading edge. With the
// name hidden and the glyph in the middle, its touches would reach far past the glyph, over the queue, and
// hardly before it. So the row's view that holds it takes touches only in a square over the glyph, the size
// of the row's other two; Spotify's own views inside still handle them. The square is kept on that view, and
// its class answers from it, as it does for every other view of the class.
static char kConnectHitKey;
static NSMutableDictionary<NSString *, NSValue *> *sg_origPointInside;   // class name -> original IMP

static BOOL connectPointInside(UIView *self, SEL _cmd, CGPoint point, UIEvent *event) {
    NSValue *square = objc_getAssociatedObject(self, &kConnectHitKey);
    if (square) return CGRectContainsPoint(square.CGRectValue, point);
    // The nearest hooked class up the chain holds the original this view would have run.
    for (Class cls = self.class; cls; cls = class_getSuperclass(cls)) {
        NSValue *orig = sg_origPointInside[NSStringFromClass(cls)];
        // A subclass hooked after its parent got the parent's hook as its original; that one is skipped.
        if (orig && orig.pointerValue != (void *)connectPointInside)
            return ((BOOL (*)(UIView *, SEL, CGPoint, UIEvent *))orig.pointerValue)(self, _cmd, point, event);
    }
    return NO;
}

void SGRPlayerCoverConnect(UIView *arranged, UIView *glyph) {
    if (!arranged || !glyph) return;
    // The ordinary footer and the DJ's can hand over views of different classes; each class is hooked once.
    if (!sg_origPointInside) sg_origPointInside = [NSMutableDictionary new];
    NSString *name = NSStringFromClass(arranged.class);
    if (!sg_origPointInside[name]) {
        IMP orig = NULL;
        MSHookMessageEx(arranged.class, @selector(pointInside:withEvent:), (IMP)connectPointInside, &orig);
        sg_origPointInside[name] = [NSValue valueWithPointer:(void *)orig];
    }
    CGRect drawn = [glyph convertRect:glyph.bounds toView:arranged];
    CGRect square = CGRectMake(CGRectGetMidX(drawn) - 22, CGRectGetMidY(drawn) - 22, 44, 44);
    objc_setAssociatedObject(arranged, &kConnectHitKey, [NSValue valueWithCGRect:square], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Connect's glyph, ready to be moved: Connect laid out first, since the glyph is unsized until it is (the first time the
// player opens), and its device name hidden. The name is a MarqueeLabel on the phone's speaker and a plain Encore label
// on AirPods; Connect holds nothing else that draws text. With no glyph yet the caller leaves Connect where Spotify put
// it, and `host` looks again on the next turn of the run loop.
UIView *SGRPlayerConnectGlyphIn(UIView *host, UIView *connect) {
    [connect layoutIfNeeded];
    UIView *glyph = connectGlyphIn(connect);
    static NSUInteger lookedAgain;   // a Connect with no glyph at all is left alone after this many
    if (glyph) lookedAgain = 0;
    if (connect && !glyph && lookedAgain++ < 20) {
        __weak UIView *weakHost = host;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakHost setNeedsLayout]; });
    }
    __block NSString *name = nil;
    SGForEachView(connect, ^(UIView *view) {
        if ([view isKindOfClass:UILabel.class] || SGClassNamed(view.class, @"MarqueeLabel")) SGRPlayerVanish(view);
        if (!name.length && [view isKindOfClass:UILabel.class]) name = ((UILabel *)view).text;
    });
    BOOL renamed = !(name == sg_spotifyDeviceName || [name isEqualToString:sg_spotifyDeviceName]);
    sg_spotifyDeviceName = name;
    if (glyph) standInForConnect((UIImageView *)glyph);
    // Spotify names another device after its glyph is drawn (another Connect device with the same glyph draws none).
    if (renamed) paintConnectAgain();
    return glyph;
}

#pragma mark - the AirPlay picker

// A tap on the middle glyph opens the system's AirPlay picker, the Music app's, and a press held opens Spotify's Connect
// sheet with a haptic (its owner, 2026-10-30; a tap opened Spotify's sheet before). The tap is a real AVRoutePickerView over
// the glyph, drawing nothing of its own (its glyph is always the plain AirPlay one); the press, recognized first, cancels
// its button's touch and sends Spotify's Connect its tap.
@interface SGRRoutePicker : AVRoutePickerView
@property (nonatomic, weak) UIView *holder;
@end

@implementation SGRRoutePicker
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    // Its own glyph is always the plain AirPlay one, whatever plays (the phone, 2026-10-30), so it draws nothing.
    self.tintColor = UIColor.clearColor;
    self.activeTintColor = UIColor.clearColor;
    self.prioritizesVideoDevices = NO;
    self.accessibilityLabel = @"AirPlay";
    UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(held:)];
    hold.minimumPressDuration = 0.4;
    [self addGestureRecognizer:hold];
    return self;
}

- (void)held:(UILongPressGestureRecognizer *)hold {
    if (hold.state != UIGestureRecognizerStateBegan) return;
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
    [self openConnect];
}

// Spotify opens its sheet from a tap recognizer on the holder, not from its button's actions (the phone's log,
// 2026-10-30): the recognizer's targets are sent the tap a finger would have made.
- (BOOL)openConnect {
    for (UIGestureRecognizer *tap in self.holder.gestureRecognizers) {
        if (![tap isKindOfClass:UITapGestureRecognizer.class]) continue;
        NSArray *targets = nil;
        @try { targets = [tap valueForKey:@"targets"]; } @catch (NSException *e) {}
        BOOL sent = NO;
        for (id entry in targets) {
            Ivar targetIvar = class_getInstanceVariable(object_getClass(entry), "_target");
            Ivar actionIvar = class_getInstanceVariable(object_getClass(entry), "_action");
            if (!targetIvar || !actionIvar) continue;
            id target = object_getIvar(entry, targetIvar);
            SEL action = *(SEL *)((char *)(__bridge void *)entry + ivar_getOffset(actionIvar));
            if (!target || !action) continue;
            ((void (*)(id, SEL, id))objc_msgSend)(target, action, tap);
            sent = YES;
        }
        return sent;
    }
    return NO;
}

- (NSString *)accessibilityValue {
    return routeText();
}

- (NSArray<UIAccessibilityCustomAction *> *)accessibilityCustomActions {
    __weak typeof(self) weakSelf = self;
    return @[[[UIAccessibilityCustomAction alloc] initWithName:@"Spotify Connect" actionHandler:^BOOL(UIAccessibilityCustomAction *action) {
        return [weakSelf openConnect];
    }]];
}
@end

// The lyrics glyph is a button of the Kit's and presses like one; Connect's and the queue's are drawn inside Spotify's
// controls, which never press them (its owner's recording, 2026-10-30). A recognizer of a finger's whole stay on the
// control presses the glyph and lets go of it as the finger lifts, taking nothing from the tap or the hold.
@interface SGRGlyphPressWatch : NSObject <UIGestureRecognizerDelegate>
@end

@implementation SGRGlyphPressWatch
- (void)touched:(UILongPressGestureRecognizer *)press {
    UIView *source = [press.view isKindOfClass:SGRRoutePicker.class] ? ((SGRRoutePicker *)press.view).holder : press.view;
    __block SGRGlyphView *glyph = nil;
    SGForEachView(source, ^(UIView *view) {
        if (!glyph && [view isKindOfClass:SGRGlyphView.class]) glyph = (SGRGlyphView *)view;
    });
    UIGestureRecognizerState state = press.state;
    if (state == UIGestureRecognizerStateBegan) SGRGlyphPress(glyph, YES);
    else if (state == UIGestureRecognizerStateEnded || state == UIGestureRecognizerStateCancelled || state == UIGestureRecognizerStateFailed) SGRGlyphPress(glyph, NO);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}
@end

static char kGlyphPressKey;

static void pressGlyphOnTouch(UIView *control) {
    if (!control || objc_getAssociatedObject(control, &kGlyphPressKey)) return;
    static SGRGlyphPressWatch *watch;
    if (!watch) watch = [SGRGlyphPressWatch new];
    UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:watch action:@selector(touched:)];
    press.minimumPressDuration = 0;
    press.allowableMovement = 30;
    press.cancelsTouchesInView = NO;
    press.delaysTouchesBegan = NO;
    press.delaysTouchesEnded = NO;
    press.delegate = watch;
    [control addGestureRecognizer:press];
    objc_setAssociatedObject(control, &kGlyphPressKey, press, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static char kRoutePickerKey;

static char kRouteLineKey;

void SGRPlayerPlaceRoute(UIView *host, UIView *connect, CGPoint middle) {
    if (!host || !connect) return;
    SGRRoutePicker *picker = objc_getAssociatedObject(host, &kRoutePickerKey);
    if (!picker) {
        picker = [[SGRRoutePicker alloc] initWithFrame:CGRectMake(0, 0, 44, 44)];
        objc_setAssociatedObject(host, &kRoutePickerKey, picker, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        pressGlyphOnTouch(picker);
        SGLog(@"redesign player: the middle glyph opens AirPlay, held it opens Connect");
    }
    picker.holder = connect;
    // One element for VoiceOver where the glyph is: the picker, with Connect's sheet as its action; Spotify's own is hidden.
    if (!connect.accessibilityElementsHidden) connect.accessibilityElementsHidden = YES;
    if (picker.superview != host || host.subviews.lastObject != picker) [host addSubview:picker];
    if (!CGPointEqualToPoint(picker.center, middle)) picker.center = middle;

    UILabel *line = objc_getAssociatedObject(host, &kRouteLineKey);
    if (!line) {
        line = [UILabel new];
        // The Music app's size and color: 15pt, white at about 68% (186 of 255 over a background of 41, its owner's
        // screenshot, 2026-10-30). Its regular weight, blended into the background there, reads heavier than a plain
        // label's, which looked thin beside it in regular and medium (its owner); semibold reads as it does.
        line.font = SGRFont(UIFontTextStyleSubheadline, UIFontWeightSemibold, UIContentSizeCategoryLarge);
        line.textColor = [UIColor colorWithWhite:1 alpha:SGRIncreaseContrast() ? 0.8 : 0.68];
        line.textAlignment = NSTextAlignmentCenter;
        line.userInteractionEnabled = NO;
        line.isAccessibilityElement = NO;   // read as the picker's value
        objc_setAssociatedObject(host, &kRouteLineKey, line, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!sg_routeLines) sg_routeLines = [NSHashTable weakObjectsHashTable];
        [sg_routeLines addObject:line];
    }
    if (line.superview != host) [host addSubview:line];
    // Under the glyph, as far below it as the Music app's (32 pt on a 956 pt screen), no wider than the row.
    CGFloat lineHeight = ceil(line.font.lineHeight), width = host.bounds.size.width;
    line.frame = CGRectMake(24, round(middle.y + kRouteLineDrop - lineHeight / 2), width - 48, lineHeight);
    updateRouteLine();
}

#pragma mark - lower down

// Moved down, the row is drawn partly below the bottom stack it is arranged in, and UIKit does not look
// into a view for a touch outside its bounds. This band over the part that hangs out hands such a touch
// to the row itself, and lets every other one through.
@interface SGRFooterReach : UIView
@property (nonatomic, weak) UIView *row;
@end

@implementation SGRFooterReach
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *row = self.row;
    if (!row.window || row.alpha < 0.01 || row.hidden) return nil;
    UIView *hit = [row hitTest:[row convertPoint:point fromView:self] withEvent:event];
    return hit == row ? nil : hit;
}
@end

static UIViewController *unitOf(UIView *view) {
    UIResponder *next = view.nextResponder;
    return [next isKindOfClass:UIViewController.class] && ((UIViewController *)next).viewIfLoaded == view ? (UIViewController *)next : nil;
}

// The arranged view drawn right above `row` in its stack, by where the stack put them.
static UIView *rowAbove(UIView *row) {
    UIView *best = nil;
    CGFloat top = row.center.y - row.bounds.size.height / 2, bestBottom = -CGFLOAT_MAX;
    // The volume row lives in the same stack, between the controls and the footer: it is not what is above, or the
    // controls would be taken for something else whenever it ends within a point of the footer (the AI DJ's gap does).
    static Class volumeRow;
    if (!volumeRow) volumeRow = NSClassFromString(@"SGRVolumeRow");
    for (UIView *sibling in row.superview.subviews) {
        if (sibling == row || sibling.hidden || sibling.alpha < 0.01 || sibling.bounds.size.height < 1) continue;
        if (volumeRow && [sibling isKindOfClass:volumeRow]) continue;
        CGFloat bottom = sibling.center.y + sibling.bounds.size.height / 2;
        if (bottom <= top + 1 && bottom > bestBottom) {
            best = sibling;
            bestBottom = bottom;
        }
    }
    return best;
}

void SGRPlayerLowerRow(UIView *row) {
    UIView *stack = row.superview, *player = stack.superview;
    UIWindow *window = row.window;
    if (![stack isKindOfClass:UIStackView.class] || !player || !window) return;
    // Where the stack put the row, the row's own transform left out, and where it belongs.
    CGFloat middle = [stack convertPoint:row.center toView:player].y;
    CGFloat height = player.bounds.size.height;
    CGFloat target = height - MAX(window.safeAreaInsets.bottom + kRowAboveSafeArea, kRowMinBottom);
    CGFloat move = MAX(0, round(target - middle));
    CGAffineTransform down = CGAffineTransformMakeTranslation(0, move);
    if (!CGAffineTransformEqualToTransform(row.transform, down)) row.transform = down;

    // Only the controls, and only straight above: a volume row between them keeps its place and theirs.
    UIView *above = rowAbove(row);
    // The ordinary player's controls unit, or the AI DJ's head unit (DJPlayer.x), which holds the same buttons.
    Class unit = unitOf(above).class;
    BOOL controls = SGClassNamed(unit, @"PlaybackControlsElementsUnit") || SGClassNamed(unit, @"DJMHeadUnitViewController");
    // With the volume row, the controls stay where Spotify put them and the row takes the room the footer leaves.
    // The volume row is placed against the controls where they would stand for it; one that does not show leaves them
    // following the footer as they do without it.
    BOOL volume = SGRPlayerVolumeOn() && controls;
    CGFloat share = volume ? 0 : kControlsShare, lift = volume ? kVolumeLift : 0;
    CGAffineTransform follow = CGAffineTransformMakeTranslation(0, controls ? round(move * share) - lift : 0);
    if (above && controls && !CGAffineTransformEqualToTransform(above.transform, follow)) above.transform = follow;
    SGRPlayerPaintCover(stack);
    if (volume && !SGRPlayerPlaceVolume(stack, above, row, kVolumeMargin)) {
        share = kControlsShare;
        follow = CGAffineTransformMakeTranslation(0, round(move * share));
        if (!CGAffineTransformEqualToTransform(above.transform, follow)) above.transform = follow;
    } else if (!volume) {
        SGRPlayerPlaceVolume(stack, nil, row, kVolumeMargin);
    }

    SGRFooterReach *reach = objc_getAssociatedObject(row, &kReachKey);
    if (!reach) {
        reach = [SGRFooterReach new];
        reach.row = row;
        objc_setAssociatedObject(row, &kReachKey, reach, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (reach.superview != player) [player addSubview:reach];
    CGRect stackFrame = [stack convertRect:stack.bounds toView:player];
    CGRect drawn = [row convertRect:row.bounds toView:player];
    CGFloat from = CGRectGetMaxY(stackFrame);
    CGRect band = CGRectMake(CGRectGetMinX(drawn), from, drawn.size.width, MAX(0, CGRectGetMaxY(drawn) - from));
    if (!CGRectEqualToRect(reach.frame, band)) reach.frame = band;

    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SGLog(@"redesign player: footer row from %.0f to %.0f of %.0f (safe area %.0f), controls %@ %.0f, volume %@", middle, middle + move, height,
              window.safeAreaInsets.bottom, controls ? @"follow" : @"stay", controls ? round(move * share) : 0, SGRPlayerVolumeOn() ? @"on" : @"off");
    });
}

%hook _TtC20NowPlaying_ModesImpl18FooterElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    UIView *host = ((UIViewController *)self).viewIfLoaded;
    if (!host) return;
    // The unit lays out before its row does, and the moves are measured from where the row put things.
    [SGFindRemembered(host, &kRowKey, ^BOOL(UIView *v) { return SGIsRow(v); }) layoutIfNeeded];
    CGFloat width = host.bounds.size.width, middleY = CGRectGetMidY(host.bounds);
    BOOL rtl = host.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;

    // Share; Spotify's clip button, hidden in every clean tree, which would turn up where the queue moves to; and
    // "From <friend>" on a track a friend shared, which sits in the middle of the row, over Connect, which the row
    // moves there (the Music app has no such chip). Found in one walk: nothing between them touches the tree.
    static const void *const goneKeys[] = {&kShareKey, &kTrimmerKey, &kSharedByKey};
    UIView *gone[3];
    static NSArray<NSString *> *goneIdentifiers;
    if (!goneIdentifiers) goneIdentifiers = @[@"ShareButtonNowPlayingView", @"nowplaying-npv-media-trimmer-navigation-button", @"Components.UI.SharedByChip"];
    SGRFindByIdentifiers(host, goneIdentifiers, goneKeys, gone);
    UIView *share = gone[0];
    for (NSUInteger i = 0; i < 3; i++) {
        SGRPlayerVanish(gone[i]);
        // The arranged view goes too: a view that takes touches swallows them even with nothing on it.
        SGRPlayerVanish(arrangedAround(gone[i], host));
    }

    SGRGlyphButton *lyrics = SGRPlayerLyricsGlyphIn(host);
    lyrics.bounds = CGRectMake(0, 0, 44, 44);
    lyrics.center = CGPointMake(round(width * (rtl ? kTrailing : kLeading)), middleY);
    SGRPlayerLyricsChanged();

    UIView *connect = SGRFindByIdentifier(host, @"Components.ConnectButtonOutputSwitcher", &kConnectKey);
    UIView *glyph = SGRPlayerConnectGlyphIn(host, connect);
    CGFloat connectFrom = glyph ? moveTo(arrangedAround(connect, host), glyph, CGPointMake(CGRectGetMidX(glyph.bounds), CGRectGetMidY(glyph.bounds)), host, round(width * kMiddle)) : -1;

    UIView *queue = SGRFindByIdentifier(host, @"QueueButtonNowPlaying", &kQueueKey);
    standInForQueue((SPTEncoreIconView *)SGRFindByIdentifier(queue, @"Encore.IconView", &kQueueIconKey));
    pressGlyphOnTouch(queue);
    CGFloat queueFrom = moveTo(arrangedAround(queue, host), queue, CGPointMake(CGRectGetMidX(queue.bounds), CGRectGetMidY(queue.bounds)), host, round(width * (rtl ? kLeading : kTrailing)));

    SGRPlayerLowerRow(host);
    if (glyph) SGRPlayerPlaceRoute(host, connect, CGPointMake(round(width * kMiddle), middleY));
    SGRPlayerCoverConnect(arrangedAround(connect, host), glyph);

    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SGLog(@"redesign player: footer lyrics at %.0f, connect %.0f (%@) to %.0f, queue %.0f to %.0f, share %@", lyrics.center.x,
              connectFrom, glyph ? @"glyph" : @"button", round(width * kMiddle), queueFrom, round(width * (rtl ? kLeading : kTrailing)), share ? @"gone" : @"not found");
    });
}
%end

// The Connect button lays itself out again when the device changes (its name comes or goes, another device's glyph,
// the button's width with them),
// with no pass of the footer around it: the glyph moved inside it while the footer's transform, worked out from where
// the glyph was, stayed, so Connect slid off its place (the phone, 2026-10-24: switched to another device from
// elsewhere, the DJ footer's Connect 11pt left of its slot). The footer is laid out again whenever the glyph moves, and
// its pass puts the button back on its place, the ordinary player's and the DJ's alike.
static char kGlyphSeenKey;

%hook _TtC23Connect_EntryPointsImpl37ConnectButtonOutputSwitcherViewHolder
- (void)layoutSubviews {
    %orig;
    UIView *connect = (UIView *)self;
    UIView *glyph = connectGlyphIn(connect);
    if (!glyph) return;
    // The glyph's place in the button and the button's size: the glyph keeps its place at the button's leading edge while
    // the button grows and shrinks with the device's name (101.5pt with "iPhone", 51 without, the phone, 2026-10-24), and
    // the element holding it is laid out again round its new size, so either one moving is a move of the glyph.
    CGRect seen = [glyph convertRect:glyph.bounds toView:connect];
    seen.size = connect.bounds.size;
    NSValue *was = objc_getAssociatedObject(connect, &kGlyphSeenKey);
    if (was && CGRectEqualToRect(was.CGRectValue, seen)) return;
    objc_setAssociatedObject(connect, &kGlyphSeenKey, [NSValue valueWithCGRect:seen], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!was) return;
    // The footer unit's view: the first ancestor a controller owns.
    for (UIView *v = connect.superview; v; v = v.superview) {
        if (!unitOf(v)) continue;
        [v setNeedsLayout];
        break;
    }
}
%end

%group VolumeSlider
%hook UISlider
- (void)setValue:(float)value animated:(BOOL)animated {
    %orig;
    SGRPlayerVolumeSliderSet(self);
}
%end
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    if (SGRPlayerVolumeOn()) %init(VolumeSlider);
    // Spotify draws no new Connect glyph when only the phone's route changes (AirPods to a HomePod). Posted off the main
    // thread, so not observed on the main queue (AGENTS.md).
    [NSNotificationCenter.defaultCenter addObserverForName:AVAudioSessionRouteChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // iOS can keep one ID for every AirPlay route (an AirPlay route named "AirPlay"), so each change is asked anew,
            // and the last answer may be another device's until then.
            sg_pickedFor = nil;
            sg_pickedStale = YES;
            paintConnectAgain();
        });
        // iOS fills in the new output a moment after the route changes, an AirPlay route named "AirPlay" until then.
        for (NSNumber *delay in @[@0.6, @2]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                paintConnectAgain();
            });
        }
    }];
    SGRequireClasses(@[@"_TtC20NowPlaying_ModesImpl18FooterElementsUnit", @"SPTEncoreIconView"]);
}

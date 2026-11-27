#import <objc/message.h>
#import <CoreText/SFNTLayoutTypes.h>
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "SGRRestyle.h"
#import "SGRBackdropInk.h"
#import "SGRRefinements.h"
#import "SGRTokens.h"

static char kPlateKey, kImageObserverKey, kLayoutObserverKey, kHeldAlphaKey, kTextObserverKey;

#pragma mark - instance subclasses

// A Swift class can lose its metadata when the runtime makes a subclass of it, and an instance KVO
// already swapped the class of would be swapped back when its last observer goes; neither is subclassed.
static BOOL subclassable(Class cls) {
    const char *name = class_getName(cls);
    return strncmp(name, "_Tt", 3) != 0 && !strchr(name, '.') && strncmp(name, "NSKVONotifying_", 15) != 0;
}

// The class `prefix` + the instance's class, made once, answering `class` with the original so
// isKindOfClass:, NSStringFromClass and the tree dumps see what Spotify made.
static Class instanceSubclass(Class original, const char *prefix, void (^install)(Class subclass, Class original)) {
    NSString *name = [NSString stringWithFormat:@"%s%s", prefix, class_getName(original)];
    Class subclass = objc_getClass(name.UTF8String);
    if (subclass) return subclass;
    subclass = objc_allocateClassPair(original, name.UTF8String, 0);
    if (!subclass) return Nil;
    install(subclass, original);
    class_addMethod(subclass, @selector(class), imp_implementationWithBlock(^Class(id self) { return original; }), "#@:");
    objc_registerClassPair(subclass);
    return subclass;
}

// Moves the view into the subclass unless it is already in it; NO when the view cannot be subclassed.
static BOOL adopt(UIView *view, const char *prefix, void (^install)(Class subclass, Class original)) {
    Class current = object_getClass(view);
    if (strncmp(class_getName(current), prefix, strlen(prefix)) == 0) return YES;
    if (!subclassable(current)) return NO;
    Class subclass = instanceSubclass(current, prefix, install);
    if (!subclass) return NO;
    object_setClass(view, subclass);
    return YES;
}

static void addOverride(Class subclass, Class original, SEL selector, id block) {
    Method method = class_getInstanceMethod(original, selector);
    if (method) class_addMethod(subclass, selector, imp_implementationWithBlock(block), method_getTypeEncoding(method));
}

#pragma mark - the class itself

// What an instance of one of Spotify's own classes cannot have -- a subclass of its own -- the class every
// instance of it shares can: the override goes on the class, the way each of the tweak's %hooks does. The
// class is taken off the instance rather than named, since Encore's names carry a build hash that moves with
// every Spotify release, and it is given the override once; an instance that never asked to be watched pays
// one associated-object lookup for it.
//
// `make` is handed the implementation the override stands in front of and answers the block that replaces
// it; that block must call the one it was given first. The implementation replaced is the class's own where
// it has one -- so nothing above it in the hierarchy, UIKit's own classes included, is touched -- and the
// inherited one where it does not.
static BOOL overrideOnClass(Class cls, SEL selector, id (^make)(IMP replaced)) {
    if (!cls || !selector) return NO;
    // Never the class KVO made for one instance: it is swapped away again when the last observer goes, and
    // the override with it. Everything else here is a class Spotify itself wrote.
    if (strncmp(class_getName(cls), "NSKVONotifying_", 15) == 0) return NO;
    // Done already? A class is an object too, and a selector is a pointer unique to its name, so the class
    // carries its own mark per selector -- a plain lookup, since callers ask again on every pass they make.
    if (objc_getAssociatedObject(cls, (void *)selector)) return YES;

    Method inherited = class_getInstanceMethod(cls, selector);
    if (!inherited) return NO;
    Method own = nil;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned int i = 0; i < count; i++) {
        if (method_getName(methods[i]) == selector) own = methods[i];
    }
    free(methods);
    IMP replaced = own ? method_getImplementation(own)
                       : class_getMethodImplementation(class_getSuperclass(cls), selector);
    if (!replaced) return NO;

    IMP override = imp_implementationWithBlock(make(replaced));
    if (own) method_setImplementation(own, override);
    else if (!class_addMethod(cls, selector, override, method_getTypeEncoding(inherited))) return NO;
    objc_setAssociatedObject(cls, (void *)selector, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return YES;
}

// Said once per class: what could not be watched at all, and what had to be watched through its class.
static void logWatch(UIView *view, SEL selector, BOOL kept, BOOL onClass) {
    static NSMutableSet<NSString *> *logged;
    NSString *name = NSStringFromClass(object_getClass(view));
    NSString *mark = [NSString stringWithFormat:@"%@ %s", name, sel_getName(selector)];
    if (!SGLogFirst(&logged, mark)) return;
    if (!kept) SGLog(@"redesign kit: %@ cannot be watched for %s", name, sel_getName(selector));
    else if (onClass) SGLog(@"redesign kit: %@ watched for %s through its class", name, sel_getName(selector));
}

// `alpha` held on an instance of one of Spotify's own classes through one setAlpha: override on its class, shared by
// SGRSuppress (0) and SGRKeepOpaque (1); every instance not marked keeps what it is given. The class `class` answers,
// so an instance KVO observes (the player's repeat button) is held too: KVO's class passes setAlpha: on to it. Only a
// class inside the app: a plain UILabel KVO observes answers UILabel, which must never be touched. An instance marked
// on an earlier call is held already: callers ask on every layout pass.
static BOOL holdAlphaOnClass(UIView *view, CGFloat alpha) {
    NSNumber *held = objc_getAssociatedObject(view, &kHeldAlphaKey);
    if (held && held.doubleValue == alpha) return YES;
    BOOL spotifys = [[NSBundle bundleForClass:view.class].bundlePath hasPrefix:NSBundle.mainBundle.bundlePath];
    BOOL onClass = spotifys && overrideOnClass(view.class, @selector(setAlpha:), ^id(IMP replaced) {
        return ^(UIView *self, CGFloat given) {
            NSNumber *hold = objc_getAssociatedObject(self, &kHeldAlphaKey);
            ((void (*)(id, SEL, CGFloat))replaced)(self, @selector(setAlpha:), hold ? hold.doubleValue : given);
        };
    });
    if (onClass) objc_setAssociatedObject(view, &kHeldAlphaKey, @(alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    logWatch(view, @selector(setAlpha:), onClass, onClass);
    return onClass;
}

#pragma mark - visibility through the ancestor chain

static char kVisibilityObserverKey, kVisibilitySubscribersKey;

@interface SGRVisibilityObserver : NSObject
@property (nonatomic, weak) UIView *view;
@property (nonatomic, copy) dispatch_block_t changed;
@property (nonatomic, strong) NSHashTable<UIView *> *ancestors;
- (void)detach;
- (void)attach;
@end

@implementation SGRVisibilityObserver
- (void)detach {
    for (UIView *ancestor in self.ancestors) {
        NSHashTable *subscribers = objc_getAssociatedObject(ancestor, &kVisibilitySubscribersKey);
        [subscribers removeObject:self];
        if (!subscribers.count) objc_setAssociatedObject(ancestor, &kVisibilitySubscribersKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    self.ancestors = nil;
}
- (void)dealloc { [self detach]; }
- (void)attach {
    [self detach];
    self.ancestors = [NSHashTable weakObjectsHashTable];
    for (UIView *ancestor = self.view; ancestor; ancestor = ancestor.superview) {
        NSHashTable *subscribers = objc_getAssociatedObject(ancestor, &kVisibilitySubscribersKey);
        if (!subscribers) {
            subscribers = [NSHashTable weakObjectsHashTable];
            objc_setAssociatedObject(ancestor, &kVisibilitySubscribersKey, subscribers, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        [subscribers addObject:self];
        [self.ancestors addObject:ancestor];
    }
}
@end

static void reportVisibility(UIView *view, BOOL hierarchyChanged) {
    NSHashTable *subscribers = objc_getAssociatedObject(view, &kVisibilitySubscribersKey);
    if (!subscribers) return;
    for (SGRVisibilityObserver *observer in subscribers.allObjects) {
        if (hierarchyChanged) [observer attach];
        if (observer.view && observer.changed) observer.changed();
    }
}

void SGRObserveVisibility(UIView *view, dispatch_block_t changed) {
    SGRVisibilityObserver *observer = objc_getAssociatedObject(view, &kVisibilityObserverKey);
    if (!changed) {
        [observer detach];
        observer.changed = nil;
        objc_setAssociatedObject(view, &kVisibilityObserverKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // A descendant gets no callback when an ancestor moves inside one window. Observe UIKit's
        // mutation boundary, without KVO changing Spotify's Swift classes or our other instance subclasses.
        for (NSString *name in @[@"didMoveToSuperview", @"didMoveToWindow"]) {
            SEL selector = NSSelectorFromString(name);
            Method method = class_getInstanceMethod(UIView.class, selector);
            IMP original = method_getImplementation(method);
            method_setImplementation(method, imp_implementationWithBlock(^(UIView *self) {
                ((void (*)(id, SEL))original)(self, selector);
                reportVisibility(self, YES);
            }));
        }
        Method hidden = class_getInstanceMethod(UIView.class, @selector(setHidden:));
        IMP setHidden = method_getImplementation(hidden);
        method_setImplementation(hidden, imp_implementationWithBlock(^(UIView *self, BOOL value) {
            ((void (*)(id, SEL, BOOL))setHidden)(self, @selector(setHidden:), value);
            reportVisibility(self, NO);
        }));
        Method alpha = class_getInstanceMethod(UIView.class, @selector(setAlpha:));
        IMP setAlpha = method_getImplementation(alpha);
        method_setImplementation(alpha, imp_implementationWithBlock(^(UIView *self, CGFloat value) {
            ((void (*)(id, SEL, CGFloat))setAlpha)(self, @selector(setAlpha:), value);
            reportVisibility(self, NO);
        }));
    });
    if (!observer) {
        observer = [SGRVisibilityObserver new];
        observer.view = view;
        objc_setAssociatedObject(view, &kVisibilityObserverKey, observer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [observer attach];
    }
    observer.changed = changed;
}

#pragma mark - views

UIView *SGRChildNamed(UIView *host, NSString *marker) {
    for (UIView *sub in host.subviews) {
        if ([NSStringFromClass(sub.class) containsString:marker]) return sub;
    }
    return nil;
}

NSString *SGRFirstLabelText(UIView *root) {
    __block NSString *found = nil;
    SGForEachView(root, ^(UIView *view) {
        if (found || ![view isKindOfClass:UILabel.class]) return;
        NSString *text = [((UILabel *)view).text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (text.length) found = text;
    });
    return found;
}

UILabel *SGRLargeTitleIn(UIView *host, const void *key) {
    UILabel *title = objc_getAssociatedObject(host, key);
    if (!title) {
        title = [UILabel new];
        title.textColor = SGRPrimary();
        title.accessibilityTraits = UIAccessibilityTraitHeader;
        title.adjustsFontSizeToFitWidth = YES;
        title.minimumScaleFactor = 0.6;
        title.userInteractionEnabled = NO;
        objc_setAssociatedObject(host, key, title, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (title.superview != host) [host addSubview:title];
    return title;
}

UIImageView *SGRHeaderArtworkIn(UIView *root) {
    static const CGFloat minimumArtworkWidth = 80;
    __block UIImageView *found = nil, *empty = nil;
    SGForEachView(root, ^(UIView *v) {
        if (found || ![v isKindOfClass:UIImageView.class]) return;
        UIImageView *image = (UIImageView *)v;
        if (image.bounds.size.width < minimumArtworkWidth) return;
        if (image.image) found = image;
        else if (!empty) empty = image;
    });
    return found ?: empty;
}

void SGRBlankView(UIView *view) {
    if (!view) return;
    if (!view.layer.mask) view.layer.mask = [CALayer layer];
    if (view.userInteractionEnabled) view.userInteractionEnabled = NO;
    view.accessibilityElementsHidden = YES;
}

void SGRConcealView(UIView *view) {
    if (!view) return;
    if (!view.layer.hidden) view.layer.hidden = YES;
    SGRBlankView(view);
}

BOOL SGRIsTrackContent(UIView *content) {
    return SGClassNamed(object_getClass(content), @"RetrievalListStructuredData");
}

void SGRCollapseCell(UICollectionViewCell *cell, CGFloat natural, const void *key) {
    UIView *content = cell.contentView;
    objc_setAssociatedObject(cell, key, @(natural), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (content.autoresizingMask & UIViewAutoresizingFlexibleHeight) content.autoresizingMask &= ~UIViewAutoresizingFlexibleHeight;
    CGRect frame = CGRectMake(0, 0, cell.bounds.size.width, natural);
    if (!CGRectEqualToRect(content.frame, frame)) content.frame = frame;
    if (!content.hidden) content.hidden = YES;
    if (!cell.clipsToBounds) cell.clipsToBounds = YES;
    cell.accessibilityElementsHidden = YES;
}

void SGRRestoreCell(UICollectionViewCell *cell, const void *key) {
    UIView *content = cell.contentView;
    objc_setAssociatedObject(cell, key, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    content.autoresizingMask |= UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    content.frame = cell.bounds;
    content.hidden = NO;
    cell.clipsToBounds = NO;
    cell.accessibilityElementsHidden = NO;
}

void SGRVanish(UIView *view) {
    if (!view) return;
    if (view.alpha != 0) view.alpha = 0;
    view.userInteractionEnabled = NO;
    view.accessibilityElementsHidden = YES;
}

void SGRSuppress(UIView *view) {
    if (!view) return;
    BOOL kept = adopt(view, "SGRSuppressed_", ^(Class subclass, Class original) {
        addOverride(subclass, original, @selector(setAlpha:), ^(UIView *self, CGFloat alpha) {
            struct objc_super parent = {self, original};
            ((void (*)(struct objc_super *, SEL, CGFloat))objc_msgSendSuper)(&parent, @selector(setAlpha:), 0);
        });
        addOverride(subclass, original, @selector(setUserInteractionEnabled:), ^(UIView *self, BOOL enabled) {
            struct objc_super parent = {self, original};
            ((void (*)(struct objc_super *, SEL, BOOL))objc_msgSendSuper)(&parent, @selector(setUserInteractionEnabled:), NO);
        });
    });
    // One of Spotify's Swift classes (an Encore button, whose state render sets its alpha back to 1) keeps it
    // through an override on the class, which only holds the instances marked here (holdAlphaOnClass).
    if (!kept) holdAlphaOnClass(view, 0);
    view.alpha = 0;
    view.userInteractionEnabled = NO;
    view.accessibilityElementsHidden = YES;
}

void SGRKeepOpaque(UIView *view) {
    if (!view) return;
    holdAlphaOnClass(view, 1);
    if (view.alpha != 1) view.alpha = 1;
}

static BOOL hasMonospacedDigits(UIFont *font) {
    for (NSDictionary *setting in font.fontDescriptor.fontAttributes[UIFontDescriptorFeatureSettingsAttribute]) {
        if ([setting[UIFontFeatureTypeIdentifierKey] integerValue] == kNumberSpacingType
            && [setting[UIFontFeatureSelectorIdentifierKey] integerValue] == kMonospacedNumbersSelector) return YES;
    }
    return NO;
}

// The Music app's times (SGRTimeLabelStyle): 12 pt like the caption 1 style, semibold, at most this large at the
// biggest text sizes. Measured on the Music app's player at 3x: the digits stand 27 px tall (a 13 pt font's 29).
static const CGFloat kTimeFontSize = 12, kTimeFontMost = 18;
// Their ink: white at this alpha, ADDED to what is behind them (plusL) as the Music app's are, so they rise and fall
// with the backdrop: measured on its player over a light, a mid and a dark cover, its digits stand 67 of 255 above
// the backdrop each time (0.265), where Spotify's own #B3B3B3 peaked at 179 whatever stood behind. More opaque and
// plainly composited under Increase Contrast.
// Against the Music app's player over a dark blue and a pink animated cover (3x) they stood a fifth dimmer than its own
// and were lifted to 0.48; that was ink drawn plain, decided while the opening player's container was masked and kept
// (SGRInkFor). Added to the backdrop they are back at 0.265.
static const CGFloat kTimeInkAlpha = 0.265, kTimeInkContrastAlpha = 0.7, kTimeInkLightAlpha = 0.85;
static char kTimeStyleKey, kTimeLitKey;

static UIFont *timeFont(void) {
    UIFont *base = [UIFont systemFontOfSize:kTimeFontSize weight:UIFontWeightSemibold];
    base = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleCaption1] scaledFontForFont:base maximumPointSize:kTimeFontMost];
    return SGMonospacedDigitsFont(base);
}

static UIColor *timeInk(UILabel *label, BOOL *plusL) {
    if (UIAccessibilityDarkerSystemColorsEnabled()) {
        if (plusL) *plusL = NO;
        return [UIColor colorWithWhite:1 alpha:kTimeInkContrastAlpha];
    }
    return SGRInkFor(label, kTimeInkAlpha, kTimeInkLightAlpha, plusL);
}

static BOOL sameFont(UIFont *a, UIFont *b) {
    return [a.fontName isEqualToString:b.fontName] && fabs(a.pointSize - b.pointSize) < 0.01;
}

static void applyMonospaced(UILabel *label, Class original) {
    NSAttributedString *text = label.attributedText;
    struct objc_super parent = {label, original};
    BOOL styled = objc_getAssociatedObject(label, &kTimeStyleKey) != nil;
    UIFont *target = styled ? timeFont() : nil;
    if (!text.length) {
        UIFont *font = label.font;
        if (target) {
            if (!font || !sameFont(font, target)) ((void (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&parent, @selector(setFont:), target);
        } else if (font && !hasMonospacedDigits(font)) {
            ((void (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&parent, @selector(setFont:), SGMonospacedDigitsFont(font));
        }
        return;
    }
    __block NSMutableAttributedString *mapped = nil;
    [text enumerateAttribute:NSFontAttributeName inRange:NSMakeRange(0, text.length) options:0 usingBlock:^(UIFont *font, NSRange range, BOOL *stop) {
        if (target) {
            if (font && sameFont(font, target)) return;
            if (!mapped) mapped = [text mutableCopy];
            [mapped addAttribute:NSFontAttributeName value:target range:range];
            return;
        }
        if (!font || hasMonospacedDigits(font)) return;
        if (!mapped) mapped = [text mutableCopy];
        [mapped addAttribute:NSFontAttributeName value:SGMonospacedDigitsFont(font) range:range];
    }];
    // The time left leads with a hyphen in Spotify's text; the Music app's is a minus sign, which is as wide as a plus.
    if (styled && [text.string hasPrefix:@"-"]) {
        if (!mapped) mapped = [text mutableCopy];
        [mapped replaceCharactersInRange:NSMakeRange(0, 1) withString:@"\u2212"];
    }
    if (mapped) ((void (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&parent, @selector(setAttributedText:), mapped);
    // The times' ink, except while a finger scrubs and they are lit (SGRTimeLabelLit). It goes through the label's own
    // textColor, which colors the whole text, so the label's color is the ink too and is what a scrub gives back.
    if (styled && !objc_getAssociatedObject(label, &kTimeLitKey)) {
        UIColor *ink = timeInk(label, NULL);
        NSAttributedString *now = label.attributedText;
        UIColor *shown = now.length ? [now attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL] : label.textColor;
        if (!shown || ![shown isEqual:ink]) ((void (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&parent, @selector(setTextColor:), ink);
    }
    if (styled) {
        BOOL plusL = NO;
        timeInk(label, &plusL);
        NSString *filter = plusL ? @"plusL" : nil;
        if (![label.layer.compositingFilter isEqual:filter]) label.layer.compositingFilter = filter;
    }
}

// Spotify's setters run first; what they left is then given the feature through the original class's
// own setters. UILabel may set one property through another, so a pass started inside a pass is
// skipped rather than trusted to settle.
static BOOL sg_keepingMonospaced = NO;

static void keepMonospaced(UILabel *label, Class original) {
    if (sg_keepingMonospaced) return;
    sg_keepingMonospaced = YES;
    applyMonospaced(label, original);
    sg_keepingMonospaced = NO;
}

// The same pass again, for a new reading of the backdrop: the class the override was made over is found as
// SGRMonospacedDigits's own end finds it. Only the ink changes (the text and font are already as styled).
static void refreshTimeInk(UILabel *label) {
    if (!label || !label.window || objc_getAssociatedObject(label, &kTimeStyleKey) == nil) return;
    Class original = object_getClass(label);
    for (Class c = original; c; c = class_getSuperclass(c)) {
        if ([NSStringFromClass(c) hasPrefix:@"SGRMonospaced_"]) {
            original = class_getSuperclass(c);
            break;
        }
    }
    keepMonospaced(label, original);
}

// Snapshot the input, not UIKit's synthesized attributedText. Edits through
// UILabel's original class still invalidate its drawing even if they bypass our setters.
@interface SGRDigitsWrite : NSObject
@property (nonatomic) SEL setter;
@property (nonatomic, copy) id input;
@end
@implementation SGRDigitsWrite
@end
static char kDigitsWrite;

static BOOL equalValue(id a, id b) {
    return a == b || [a isEqual:b];
}

void SGRMonospacedDigits(UILabel *label) {
    if (![label isKindOfClass:UILabel.class]) return;
    BOOL kept = adopt(label, "SGRMonospaced_", ^(Class subclass, Class original) {
        for (NSString *name in @[@"setNeedsDisplay", @"invalidateIntrinsicContentSize"]) {
            SEL selector = NSSelectorFromString(name);
            addOverride(subclass, original, selector, ^(UILabel *self) {
                ((SGRDigitsWrite *)objc_getAssociatedObject(self, &kDigitsWrite)).setter = NULL;
                struct objc_super parent = {self, original};
                ((void (*)(struct objc_super *, SEL))objc_msgSendSuper)(&parent, selector);
            });
        }
        for (NSString *name in @[@"setText:", @"setAttributedText:", @"setFont:"]) {
            SEL selector = NSSelectorFromString(name);
            addOverride(subclass, original, selector, ^(UILabel *self, id value) {
                SGRDigitsWrite *last = objc_getAssociatedObject(self, &kDigitsWrite);
                BOOL textSetter = selector != @selector(setFont:);
                if (textSetter && last.setter == selector && equalValue(last.input, value)) return;
                last.setter = NULL; // Invalidate before UIKit can call another setter.
                // A label SGRRollDigits marked shows the change by SGRRefinements.h's rules.
                BOOL watched = SGRRollingDigitsWatched(self);
                NSAttributedString *before = watched ? self.attributedText : nil;
                struct objc_super parent = {self, original};
                ((void (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&parent, selector, value);
                keepMonospaced(self, original);
                if (watched) SGRRollingDigitsTextChanged(self, before);
                if (textSetter && !sg_keepingMonospaced) {
                    if (!last) {
                        last = [SGRDigitsWrite new];
                        objc_setAssociatedObject(self, &kDigitsWrite, last, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    }
                    last.input = value;
                    last.setter = selector;
                } else last.setter = NULL;
            });
        }
        addOverride(subclass, original, @selector(didMoveToWindow), ^(UILabel *self) {
            struct objc_super parent = {self, original};
            ((void (*)(struct objc_super *, SEL))objc_msgSendSuper)(&parent, @selector(didMoveToWindow));
            if (SGRRollingDigitsWatched(self)) SGRRollingDigitsMovedToWindow(self);
        });
    });
    Class original = kept ? class_getSuperclass(object_getClass(label)) : object_getClass(label);
    keepMonospaced(label, original);
}

void SGRTimeLabelStyle(UILabel *label) {
    if (![label isKindOfClass:UILabel.class]) return;
    objc_setAssociatedObject(label, &kTimeStyleKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // The override is in place or goes in now, and the label is given the style once at once.
    SGRMonospacedDigits(label);
    // The ink follows how light the backdrop is (SGRBackdropInk.h): taken again at each new reading.
    __weak UILabel *weak = label;
    SGRBackdropInkObserve(label, ^{ refreshTimeInk(weak); });
}

void SGRTimeLabelLit(UILabel *label, BOOL lit) {
    if (![label isKindOfClass:UILabel.class]) return;
    objc_setAssociatedObject(label, &kTimeLitKey, lit ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Only the views that asked: everything else of the class carrying the override goes straight back out.
static void reportImage(UIImageView *view) {
    void (^block)(UIImageView *) = objc_getAssociatedObject(view, &kImageObserverKey);
    if (block) block(view);
}

BOOL SGRObserveImage(UIImageView *view, void (^changed)(UIImageView *view)) {
    if (![view isKindOfClass:UIImageView.class]) return NO;
    BOOL first = objc_getAssociatedObject(view, &kImageObserverKey) == nil;
    objc_setAssociatedObject(view, &kImageObserverKey, changed, OBJC_ASSOCIATION_COPY_NONATOMIC);
    BOOL kept = adopt(view, "SGRImageObserved_", ^(Class subclass, Class original) {
        addOverride(subclass, original, @selector(setImage:), ^(UIImageView *self, UIImage *image) {
            struct objc_super parent = {self, original};
            ((void (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&parent, @selector(setImage:), image);
            reportImage(self);
        });
    });
    // Encore's image views, which is what every picture Spotify loads arrives in, are Swift classes: no
    // instance of one can be given a subclass of its own, so the class itself carries the override.
    BOOL onClass = !kept && overrideOnClass(object_getClass(view), @selector(setImage:), ^id(IMP replaced) {
        return ^(UIImageView *self, UIImage *image) {
            ((void (*)(id, SEL, id))replaced)(self, @selector(setImage:), image);
            reportImage(self);
        };
    });
    if (first) logWatch(view, @selector(setImage:), kept || onClass, onClass);
    return kept || onClass;
}

BOOL SGRObserveText(UILabel *label, void (^changed)(UILabel *label)) {
    if (![label isKindOfClass:UILabel.class]) return NO;
    objc_setAssociatedObject(label, &kTextObserverKey, changed, OBJC_ASSOCIATION_COPY_NONATOMIC);
    BOOL kept = adopt(label, "SGRTextObserved_", ^(Class subclass, Class original) {
        for (NSString *name in @[@"setText:", @"setAttributedText:"]) {
            SEL selector = NSSelectorFromString(name);
            addOverride(subclass, original, selector, ^(UILabel *self, id value) {
                struct objc_super parent = {self, original};
                ((void (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&parent, selector, value);
                void (^block)(UILabel *) = objc_getAssociatedObject(self, &kTextObserverKey);
                if (block) block(self);
            });
        }
    });
    if (!kept) logWatch(label, @selector(setText:), NO, NO);
    return kept;
}

// A pass the block itself sets off (a frame it moves) reaches layoutSubviews again before the block has
// returned; one level is enough to settle, and re-entering would not end.
static BOOL sg_reportingLayout = NO;

BOOL SGRObserveLayout(UIView *view, void (^laidOut)(UIView *view)) {
    if (![view isKindOfClass:UIView.class]) return NO;
    objc_setAssociatedObject(view, &kLayoutObserverKey, laidOut, OBJC_ASSOCIATION_COPY_NONATOMIC);
    BOOL kept = adopt(view, "SGRLayoutObserved_", ^(Class subclass, Class original) {
        addOverride(subclass, original, @selector(layoutSubviews), ^(UIView *self) {
            struct objc_super parent = {self, original};
            ((void (*)(struct objc_super *, SEL))objc_msgSendSuper)(&parent, @selector(layoutSubviews));
            if (sg_reportingLayout) return;
            void (^block)(UIView *) = objc_getAssociatedObject(self, &kLayoutObserverKey);
            if (!block) return;
            sg_reportingLayout = YES;
            block(self);
            sg_reportingLayout = NO;
        });
    });
    if (!kept) {
        static NSMutableSet<NSString *> *logged;
        NSString *name = NSStringFromClass(object_getClass(view));
        SGLogOnce(&logged, name, @"redesign kit: %@ cannot be watched for its layout");
    }
    return kept;
}

// An identifier ending in * matches by prefix, for Spotify's ids that carry an entity after a dash.
static BOOL identifierMatches(NSString *identifier, NSString *wanted) {
    if (!identifier) return NO;
    if ([wanted hasSuffix:@"*"]) return [identifier hasPrefix:[wanted substringToIndex:wanted.length - 1]];
    return [identifier isEqualToString:wanted];
}

static UIView *findIdentifier(UIView *view, NSString *identifier) {
    if (identifierMatches(view.accessibilityIdentifier, identifier)) return view;
    for (UIView *sub in view.subviews) {
        UIView *found = findIdentifier(sub, identifier);
        if (found) return found;
    }
    return nil;
}

BOOL SGRIsAvatar(UIView *view) {
    static Class faceClass;
    if (!faceClass) faceClass = NSClassFromString(@"_TtC29ListeningActivity_ElementsKit21AdaptiveFaceContainer");
    return [view.accessibilityIdentifier isEqualToString:@"Components.UI.SideDrawerButton"]
        || (faceClass && [view isKindOfClass:faceClass]);
}

UIView *SGRFindByIdentifier(UIView *root, NSString *identifier, const void *cacheKey) {
    if (!root || !identifier.length) return nil;
    if (!cacheKey) return findIdentifier(root, identifier);
    return SGFindRemembered(root, cacheKey, ^BOOL(UIView *v) { return identifierMatches(v.accessibilityIdentifier, identifier); });
}

@implementation SGRShadowPlate {
    CGRect _pathBounds;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.accessibilityElementsHidden = YES;
    _cornerRadius = SGRRadiusArtwork;
    _pathBounds = CGRectNull;
    CALayer *layer = self.layer;
    layer.shadowColor = UIColor.blackColor.CGColor;
    layer.shadowOpacity = 0.45;
    layer.shadowRadius = 32;
    layer.shadowOffset = CGSizeMake(0, 12);
    return self;
}

- (void)setCornerRadius:(CGFloat)radius {
    _cornerRadius = radius;
    _pathBounds = CGRectNull;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    if (CGRectEqualToRect(bounds, _pathBounds)) return;
    _pathBounds = bounds;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:_cornerRadius].CGPath;
    [CATransaction commit];
}

@end

SGRShadowPlate *SGRShadowPlateIn(UIView *host, const void *key) {
    if (!host) return nil;
    const void *slot = key ?: &kPlateKey;
    SGRShadowPlate *plate = objc_getAssociatedObject(host, slot);
    if (!plate) {
        plate = [[SGRShadowPlate alloc] initWithFrame:host.bounds];
        objc_setAssociatedObject(host, slot, plate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (plate.superview != host) [host insertSubview:plate atIndex:0];
    return plate;
}

#pragma mark - Spotify's controls and pages

// Nearly as wide as the cell. The bands are the width of the page -- a row's surface, a carousel's
// collection, a "see more" fade (artist, trees/continuous/3.txt 2026-09-18; episode page and the
// playlist's Recommended songs, trees/continuous/1.txt and 2.txt 2026-09-20) -- while a badge's black
// disc is 26pt and an avatar's ring the same.
static const CGFloat kPaintedShare = 0.75;

// The layer's color, not the view's. -[UIView backgroundColor] answers only what was set through the
// view; a view painted straight on its layer reads back nil there, and the first pass of this left the
// playlist's Refresh band black while everything beside it cleared (device, trees/continuous/1.txt
// 2026-09-20). The layer is where the paint really is, and where the Kit's repaint hook watches for it.
//
// A cell nested inside the cell is walked into only while it is as wide as the band being looked for:
// a card in a carousel is its own and narrower, while the element framework wraps a cell's content in
// views of its own that are the full width, and stopping at one of those is stopping before the paint.
// A "see more" fade lies over the section's last row with the footer drawn on top of both, its button over the
// row's bottom line (Popular's 6th track, device 2026-10-07: the fade over the whole cell, the footer from 40pt).
// With the fade gone, the row fades itself out above the footer instead, so the field shows through, not a paint.
// Only above a section footer (ListSectionFooterElement): the About card lays its photo, a fade and its words out the
// same way, and its photo is not to fade (device 2026-10-08).
static char kRowFadeKey;
static BOOL isFooter(UIView *view) {
    return [NSStringFromClass(view.class) containsString:@"ListSectionFooter"];
}

static void fadeRowsAbove(UIView *gradient) {
    NSArray<UIView *> *siblings = gradient.superview.subviews;
    NSUInteger at = [siblings indexOfObject:gradient];
    if (at == NSNotFound || at + 1 >= siblings.count || !isFooter(siblings[at + 1])) return;
    CGFloat footerTop = siblings[at + 1].frame.origin.y;
    for (NSUInteger i = 0; i < at; i++) {
        UIView *row = siblings[i];
        CGFloat top = footerTop - 12 - row.frame.origin.y, bottom = footerTop + 8 - row.frame.origin.y, height = row.bounds.size.height;
        if (footerTop <= row.frame.origin.y || top >= height || height <= 0) continue;
        CAGradientLayer *fade = objc_getAssociatedObject(row, &kRowFadeKey);
        if (!fade) {
            fade = [CAGradientLayer layer];
            fade.colors = @[(id)UIColor.blackColor.CGColor, (id)UIColor.clearColor.CGColor];
            objc_setAssociatedObject(row, &kRowFadeKey, fade, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        fade.frame = row.bounds;
        fade.locations = @[@(fmax(0, top) / height), @(fmin(bottom, height) / height)];
        [CATransaction commit];
        if (row.layer.mask != fade) row.layer.mask = fade;
    }
}

// A row reused away from the footer, with no fade and footer after it any more, is shown whole again.
static BOOL aboveFooter(UIView *row) {
    NSArray<UIView *> *siblings = row.superview.subviews;
    NSUInteger at = [siblings indexOfObject:row];
    for (NSUInteger i = at + 1; at != NSNotFound && i + 1 < siblings.count; i++) {
        if (SGClassNamed(siblings[i].class, @"GradientView") && isFooter(siblings[i + 1])) return YES;
    }
    return NO;
}

static void clearPaint(UIView *view, UIView *cell, CGFloat wide) {
    BOOL full = view.bounds.size.width >= wide;
    if (view != cell && !full && [view isKindOfClass:UICollectionViewCell.class]) return;
    // A row's fade is only ever in place as its mask, so an unmasked view has none to take off.
    CALayer *mask = view.layer.mask;
    if (mask && mask == objc_getAssociatedObject(view, &kRowFadeKey) && !aboveFooter(view)) view.layer.mask = nil;
    if (full) {
        // Read off the layer, written through the view, so the two are left saying the same thing: the
        // clear color lands on both, and reads back with an alpha the next pass does not take for paint.
        CGColorRef color = view.layer.backgroundColor;
        if (color && SGIsBaseSurface(color)) view.backgroundColor = UIColor.clearColor;
        if (SGClassNamed(view.class, @"GradientView")) {
            if (!view.layer.mask) view.layer.mask = [CALayer layer];
            fadeRowsAbove(view);
        }
    }
    for (UIView *sub in view.subviews) clearPaint(sub, cell, wide);
}

void SGRClearCellPaint(UIView *cell) {
    if (!cell) return;
    clearPaint(cell, cell, cell.bounds.size.width * kPaintedShare);
}

// The way a tap on Spotify's own button would fire it: the first control under it, through the actions
// it registered, and through accessibility for an Encore control that reads its touches from a gesture
// recognizer instead -- which is every one of Spotify's own Swift controls.
static UIControl *firstControlIn(UIView *source) {
    __block UIControl *control = nil;
    SGForEachView(source, ^(UIView *v) {
        if (!control && [v isKindOfClass:UIControl.class]) control = (UIControl *)v;
    });
    return control;
}

// Spotify says a button is off through the control's enabled flag or, for an Encore control that has no
// such flag, through the not-enabled accessibility trait on it or on the view that wraps it. Not through
// userInteractionEnabled, which the redesign's concealment changes on purpose.
BOOL SGRSourceEnabled(UIView *source) {
    if (!source) return NO;
    UIControl *control = firstControlIn(source);
    if (control && !control.enabled) return NO;
    return !((source.accessibilityTraits | control.accessibilityTraits) & UIAccessibilityTraitNotEnabled);
}

BOOL SGRActivate(UIView *source) {
    if (!SGRSourceEnabled(source)) return NO;
    UIControl *control = firstControlIn(source);
    if (control && SGRFire(control)) return YES;
    id target = control ?: source;
    static NSMutableSet<NSString *> *logged;
    NSString *name = NSStringFromClass([target class]);
    SGLogOnce(&logged, name, @"redesign kit: %@ fired through accessibility");
    [target accessibilityActivate];
    return YES;
}

BOOL SGRFire(UIControl *control) {
    if (![control isKindOfClass:UIControl.class]) return NO;
    __block UIControlEvents registered = control.allControlEvents;
    [control enumerateEventHandlers:^(UIAction *action, id target, SEL selector, UIControlEvents events, BOOL *stop) {
        registered |= events;
    }];
    UIControlEvents fire = (registered & UIControlEventPrimaryActionTriggered) ? UIControlEventPrimaryActionTriggered
                         : (registered & UIControlEventTouchUpInside) ? UIControlEventTouchUpInside : 0;
    static NSMutableSet<NSString *> *logged;
    NSString *name = NSStringFromClass(control.class);
    if (SGLogFirst(&logged, name)) {
        SGLog(@"redesign kit: %@ fires %@ (events 0x%lx)", name, fire == UIControlEventPrimaryActionTriggered ? @"its primary action" : fire ? @"touch up inside" : @"nothing", (unsigned long)registered);
    }
    if (!fire) return NO;
    [control sendActionsForControlEvents:fire];
    return YES;
}

#pragma mark - the ink over a light backdrop (SGRBackdropInk.h)

NSNotificationName const SGRBackdropInkDidChangeNotification = @"spotifyglass.redesign.backdropInkDidChange";

// The field is drawn this small and read cell by cell, so a view's ink is taken from the backdrop behind it alone: a
// row's mean across the width read a left-aligned artist line over a dark cover's middle (a dark figure, a black
// sleeve) as darker than what stands behind the text, and drew it dimmer than the Music app's.
enum { kInkColumns = 16, kInkRows = 48 };
// Seconds between readings; four times that in Low Power Mode.
static const NSTimeInterval kInkEvery = 0.25;
// A reading is reported when a row moved this much (of 1).
static const CGFloat kInkReportDelta = 0.02;
// Never divide by less than this headroom when drawing plusL's result as a normal white.
static const CGFloat kInkLeastHeadroom = 0.05;

static char kInkObserverKey;
static __weak UIView *sg_inkSource;
static NSTimer *sg_inkTimer;
static NSHashTable<UIView *> *sg_inkObservers;
static float sg_inkRows[kInkRows];
static float sg_inkCells[kInkRows][kInkColumns];
static BOOL sg_inkHave;
static NSUInteger sg_inkTicks;

static CGFloat inkLuma(const uint8_t *p) {
    return (0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2]) / 255.0;
}

static BOOL sourceShows(UIView *source) {
    if (!source.window) return NO;
    for (UIView *view = source; view; view = view.superview)
        if (view.hidden || view.alpha <= 0.01) return NO;
    return UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
}

static void notifyInk(void) {
    for (UIView *view in sg_inkObservers.allObjects) {
        void (^block)(void) = objc_getAssociatedObject(view, &kInkObserverKey);
        if (block) block();
    }
    [NSNotificationCenter.defaultCenter postNotificationName:SGRBackdropInkDidChangeNotification object:nil];
}

// The source drawn kInkColumns by kInkRows pixels, as the render server shows it (Metal and video layers included, which a
// layer's own renderInContext: leaves out).
static void readField(void) {
    UIView *source = sg_inkSource;
    if (!sourceShows(source)) return;
    CGSize bounds = source.bounds.size;
    if (bounds.width < 1 || bounds.height < 1) return;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1;
    format.opaque = YES;
    __block BOOL drawn = NO;
    UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(kInkColumns, kInkRows) format:format]
        imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGContextScaleCTM(context.CGContext, kInkColumns / bounds.width, kInkRows / bounds.height);
        drawn = [source drawViewHierarchyInRect:source.bounds afterScreenUpdates:NO];
    }];
    CGImageRef cg = image.CGImage;
    if (!drawn || !cg) return;
    uint8_t pixels[kInkColumns * kInkRows * 4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef bitmap = CGBitmapContextCreate(pixels, kInkColumns, kInkRows, 8, kInkColumns * 4, space,
                                                kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!bitmap) return;
    CGContextDrawImage(bitmap, CGRectMake(0, 0, kInkColumns, kInkRows), cg);
    CGContextRelease(bitmap);
    float rows[kInkRows], cells[kInkRows][kInkColumns];
    for (int y = 0; y < kInkRows; y++) {
        CGFloat sum = 0;
        for (int x = 0; x < kInkColumns; x++) {
            const uint8_t *p = pixels + (y * kInkColumns + x) * 4;
            cells[y][x] = (float)inkLuma(p);
            sum += cells[y][x];
        }
        rows[y] = sum / kInkColumns;
    }
    BOOL moved = !sg_inkHave;
    for (int y = 0; y < kInkRows && !moved; y++) {
        for (int x = 0; x < kInkColumns && !moved; x++) moved = fabsf(cells[y][x] - sg_inkCells[y][x]) > kInkReportDelta;
    }
    if (!moved) return;
    memcpy(sg_inkRows, rows, sizeof rows);
    memcpy(sg_inkCells, cells, sizeof cells);
    sg_inkHave = YES;
    notifyInk();
}

// The Music app draws this ink as white added to the backdrop (plusL), which the render server works out again on
// every frame, so its text follows a new cover's crossfade (0.8 s) as it goes. Read every kInkEvery, Retrine's ink
// jumped in three or four steps through the same crossfade, and a dark cover giving way to a light one left the text
// dim over the light one for up to a quarter second. While the backdrop changes the readings follow it at the
// crossfade a little more closely: from a change of cover (SGRBackdropInkFollow), every kInkFollow until it has ended and
// kInkFollowSettle more. Only then: the field drifts all the time it plays, and following that would never stop. Not in
// Low Power Mode.
static const NSTimeInterval kInkFollow = kInkEvery / 2, kInkFollowSettle = 0.2;
static CFTimeInterval sg_inkFollowUntil;
static BOOL sg_inkFollowing;

static void followStep(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kInkFollow * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!sourceShows(sg_inkSource) || NSProcessInfo.processInfo.lowPowerModeEnabled || CACurrentMediaTime() > sg_inkFollowUntil) {
            sg_inkFollowing = NO;
            return;
        }
        readField();
        followStep();
    });
}

void SGRBackdropInkFollow(CFTimeInterval duration) {
    if (!sg_inkSource || NSProcessInfo.processInfo.lowPowerModeEnabled) return;
    sg_inkFollowUntil = MAX(sg_inkFollowUntil, CACurrentMediaTime() + duration + kInkFollowSettle);
    if (sg_inkFollowing) return;
    sg_inkFollowing = YES;
    followStep();
}

static void inkTick(void) {
    if (!sourceShows(sg_inkSource)) { SGRBackdropInkSetSource(nil); return; }
    sg_inkTicks++;
    if (NSProcessInfo.processInfo.lowPowerModeEnabled && sg_inkTicks % 4) return;
    if (sg_inkFollowing) return;
    readField();
}

static void scheduleInkTree(void);

void SGRBackdropInkSetSource(UIView *source) {
    if (source == sg_inkSource && (source ? sg_inkTimer.valid : !sg_inkTimer)) return;
    if (source) scheduleInkTree();
    sg_inkSource = source;
    sg_inkHave = NO;
    sg_inkFollowUntil = 0;
    [sg_inkTimer invalidate];
    sg_inkTimer = nil;
    if (!source) return;
    sg_inkTimer = [NSTimer timerWithTimeInterval:kInkEvery repeats:YES block:^(NSTimer *timer) { inkTick(); }];
    sg_inkTimer.tolerance = kInkEvery / 2;
    [NSRunLoop.mainRunLoop addTimer:sg_inkTimer forMode:NSRunLoopCommonModes];
}

// Where a label's text stands in it: a leading-aligned label is often laid out wider than its text, and what is behind
// the empty rest of it is not what the text is read against. Any other view, or alignment, is taken whole.
static CGRect textBounds(UIView *view) {
    CGRect bounds = view.bounds;
    if (![view isKindOfClass:UILabel.class]) return bounds;
    UILabel *label = (UILabel *)view;
    BOOL rtl = view.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    NSTextAlignment alignment = label.textAlignment;
    BOOL leading = alignment == NSTextAlignmentNatural || alignment == (rtl ? NSTextAlignmentRight : NSTextAlignmentLeft);
    if (!leading || !label.text.length) return bounds;
    CGFloat width = [label textRectForBounds:bounds limitedToNumberOfLines:label.numberOfLines].size.width;
    if (width <= 0 || width >= bounds.size.width) return bounds;
    return CGRectMake(rtl ? CGRectGetMaxX(bounds) - width : bounds.origin.x, bounds.origin.y, width, bounds.size.height);
}

CGFloat SGRBackdropLightnessBehind(UIView *view) {
    UIView *source = sg_inkSource;
    if (!sg_inkHave || !view || !source || !view.window || view.window != source.window) return -1;
    CGSize size = source.bounds.size;
    if (size.width < 1 || size.height < 1) return -1;
    CGRect rect = [view convertRect:textBounds(view) toView:source];
    CGFloat top = MAX(0, MIN(1, CGRectGetMinY(rect) / size.height)), bottom = MAX(0, MIN(1, CGRectGetMaxY(rect) / size.height));
    int from = MIN(kInkRows - 1, (int)floor(top * kInkRows)), to = MIN(kInkRows - 1, MAX(from, (int)ceil(bottom * kInkRows) - 1));
    // The columns the view spans; a label's frame is often wider than its text, which starts at its leading edge, so
    // the cells are weighed by how much of each the view covers.
    CGFloat left = MAX(0, MIN(1, CGRectGetMinX(rect) / size.width)) * kInkColumns;
    CGFloat right = MAX(0, MIN(1, CGRectGetMaxX(rect) / size.width)) * kInkColumns;
    if (right - left < 0.5) {
        CGFloat middle = (left + right) / 2;
        left = MAX(0, middle - 0.25);
        right = MIN(kInkColumns, middle + 0.25);
    }
    CGFloat sum = 0, weights = 0;
    for (int x = (int)floor(left); x < kInkColumns && x < right; x++) {
        CGFloat w = MIN(right, x + 1) - MAX(left, x);
        if (w <= 0) continue;
        for (int y = from; y <= to; y++) sum += w * sg_inkCells[y][x];
        weights += w * (to - from + 1);
    }
    if (weights <= 0) {
        for (int y = from; y <= to; y++) sum += sg_inkRows[y];
        return sum / (to - from + 1);
    }
    return sum / weights;
}

BOOL SGRInkIsolated(UIView *view) {
    for (UIView *v = view; v; v = v.superview) {
        CALayer *layer = v.layer;
        if (layer.mask || layer.shouldRasterize || layer.filters.count) return YES;
    }
    return NO;
}

static void noteInkView(UIView *view);

UIColor *SGRInkFor(UIView *view, CGFloat alpha, CGFloat lightAlpha, BOOL *plusL) {
    // The Music app adds a fixed amount of white to whatever is behind, so over a light backdrop its text goes to white.
    // In Spotify's player plusL does not reach the backdrop, although the ink tree log on 9.2.0 shows no mask, filter or
    // rasterizing between the ink and the field: over a light cover the ink came out as plain white of that alpha (the
    // times at 0.265 all but vanished over Wish You Were Here's gray). So the ink is drawn plain at the alpha that lands
    // on the same value over the measured backdrop, alpha / (1 - luma): the Music app's lightness, whatever is behind.
    // With no reading yet it is the alpha as it is. Measured side by side with the Music app over Wish You Were Here's
    // light gray and a blue cover: its artist, times, badge text and footer glyphs stand a fixed 123, 68, 108 and 118
    // of 255 above the backdrop, to white over the light one, where these drawn as plain white stood 28, 24, 33 and 73.
    (void)lightAlpha;
    noteInkView(view);
    if (plusL) *plusL = NO;
    CGFloat light = SGRBackdropLightnessBehind(view);
    if (light < 0) return [UIColor colorWithWhite:1 alpha:alpha];
    return [UIColor colorWithWhite:1 alpha:MIN(1, alpha / MAX(1 - light, kInkLeastHeadroom))];
}

CGFloat SGRInkPlainAlpha(UIView *view, CGFloat floorAlpha, CGFloat add) {
    noteInkView(view);
    CGFloat light = SGRBackdropLightnessBehind(view);
    if (light < 0 || UIAccessibilityDarkerSystemColorsEnabled()) return floorAlpha;
    CGFloat plain = MIN(1, add / MAX(1 - light, kInkLeastHeadroom));
    return MIN(1, MAX(floorAlpha, round(plain / 0.05) * 0.05));
}

#pragma mark - ink tree (diagnostics)

// What the ink sits in, logged a second and a half after the player's field is laid out (at most every 20 s, 6 times a
// launch, so a static and an animated cover can both be caught): for each inked view, its chain
// of superviews up to the window (each one's place among its siblings, layer class, mask, filters, compositing filter,
// background and opacity), and the siblings along the field's own chain. It decides where a backdrop capture would have
// to lie to hold everything the ink is read against. Logging only: nothing is changed.
static NSHashTable<UIView *> *sg_inkViews;

static void noteInkView(UIView *view) {
#if SG_DRIVER
    if (!view) return;
    if (!sg_inkViews) sg_inkViews = [NSHashTable weakObjectsHashTable];
    [sg_inkViews addObject:view];
#endif
}

static NSString *shortClass(id object) {
    NSString *name = NSStringFromClass([object class]);
    return name.length > 72 ? [NSString stringWithFormat:@"...%@", [name substringFromIndex:name.length - 72]] : name;
}

static NSString *layerTraits(UIView *view) {
    CALayer *layer = view.layer;
    NSMutableString *traits = [NSMutableString stringWithFormat:@"%@ %@ a=%.2f", shortClass(view),
                               NSStringFromCGRect(view.frame), view.alpha];
    if (view.hidden) [traits appendString:@" hidden"];
    if (![layer isMemberOfClass:CALayer.class]) [traits appendFormat:@" layer=%@", shortClass(layer)];
    if (layer.mask) [traits appendFormat:@" mask=%@", shortClass(layer.mask)];
    if (view.maskView) [traits appendFormat:@" maskView=%@", shortClass(view.maskView)];
    if (layer.filters.count) {
        NSMutableArray *names = [NSMutableArray array];
        for (id filter in layer.filters) {
            id name = [filter respondsToSelector:NSSelectorFromString(@"name")] ? [filter valueForKey:@"name"] : nil;
            [names addObject:name ?: shortClass(filter)];
        }
        [traits appendFormat:@" filters=%@", [names componentsJoinedByString:@","]];
    }
    if (layer.compositingFilter) [traits appendFormat:@" comp=%@", layer.compositingFilter];
    if (layer.shouldRasterize) [traits appendString:@" raster"];
    if (layer.cornerRadius > 0) [traits appendFormat:@" r=%.0f", layer.cornerRadius];
    if (view.clipsToBounds) [traits appendString:@" clips"];
    if (view.backgroundColor) {
        CGFloat white = 0, alpha = 0;
        [view.backgroundColor getWhite:&white alpha:&alpha];
        if (alpha > 0) [traits appendFormat:@" bg=%.2f/%.2f", white, alpha];
    }
    if (layer.sublayers.count > view.subviews.count) {
        NSMutableArray *own = [NSMutableArray array];
        for (CALayer *sub in layer.sublayers) {
            if ([sub.delegate isKindOfClass:UIView.class]) continue;
            [own addObject:[NSString stringWithFormat:@"%@%@%@", shortClass(sub), sub.hidden ? @"(hidden)" : @"",
                            sub.compositingFilter ? [NSString stringWithFormat:@"(%@)", sub.compositingFilter] : @""]];
            if (own.count >= 6) break;
        }
        if (own.count) [traits appendFormat:@" layers=[%@]", [own componentsJoinedByString:@", "]];
    }
    return traits;
}

static NSString *inkChain(UIView *view, UIView *stop) {
    NSMutableString *text = [NSMutableString string];
    int depth = 0;
    for (UIView *v = view; v && depth < 24; v = v.superview, depth++) {
        UIView *up = v.superview;
        NSUInteger at = up ? [up.subviews indexOfObjectIdenticalTo:v] : 0;
        [text appendFormat:@"  %d [%lu/%lu] %@%@\n", depth, (unsigned long)at, (unsigned long)up.subviews.count, layerTraits(v),
                           v == stop ? @"  <- field" : @""];
    }
    return text;
}

static void logInkTree(void) {
    UIView *field = sg_inkSource;
    if (!field.window) return;
    NSMutableString *text = [NSMutableString string];
    [text appendString:@"field chain (siblings in order, back to front)\n"];
    int depth = 0;
    for (UIView *v = field; v && depth < 24; v = v.superview, depth++) {
        UIView *up = v.superview;
        if (!up) break;
        NSUInteger at = [up.subviews indexOfObjectIdenticalTo:v];
        [text appendFormat:@" %d %@ at %lu of %lu in %@\n", depth, shortClass(v), (unsigned long)at, (unsigned long)up.subviews.count, layerTraits(up)];
        NSUInteger shown = 0;
        for (UIView *sibling in up.subviews) {
            if (shown++ >= 10) { [text appendString:@"    ...\n"]; break; }
            [text appendFormat:@"    %@%@\n", sibling == v ? @"* " : @"", layerTraits(sibling)];
        }
    }
    [text appendString:@"field's own\n"];
    for (UIView *sub in field.subviews) [text appendFormat:@"    %@\n", layerTraits(sub)];
    for (UIView *view in sg_inkViews.allObjects) {
        if (view.window != field.window) continue;
        NSString *what = [view isKindOfClass:UILabel.class] ? [NSString stringWithFormat:@"%@ %.0fpt", shortClass(view), ((UILabel *)view).font.pointSize] : shortClass(view);
        [text appendFormat:@"ink %@ in field %@\n", what, NSStringFromCGRect([view convertRect:view.bounds toView:field])];
        [text appendString:inkChain(view, field)];
    }
    SGLogLong(@"ink tree", text);
}

static void scheduleInkTree(void) {
#if !SG_DRIVER
    return;
#endif
    static NSUInteger logged;
    static CFTimeInterval last;
    CFTimeInterval now = CACurrentMediaTime();
    if (logged >= 6 || (logged && now - last < 20)) return;
    logged++;
    last = now;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ logInkTree(); });
}

void SGRBackdropInkObserve(UIView *view, void (^changed)(void)) {
    if (!view) return;
    if (!sg_inkObservers) sg_inkObservers = [NSHashTable weakObjectsHashTable];
    [sg_inkObservers addObject:view];
    objc_setAssociatedObject(view, &kInkObserverKey, changed, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

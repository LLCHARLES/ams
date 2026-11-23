#import <objc/message.h>
#import <CoreText/SFNTLayoutTypes.h>
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "SGRRestyle.h"
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

static void applyMonospaced(UILabel *label, Class original) {
    NSAttributedString *text = label.attributedText;
    struct objc_super parent = {label, original};
    if (!text.length) {
        UIFont *font = label.font;
        if (font && !hasMonospacedDigits(font)) {
            ((void (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&parent, @selector(setFont:), SGMonospacedDigitsFont(font));
        }
        return;
    }
    __block NSMutableAttributedString *mapped = nil;
    [text enumerateAttribute:NSFontAttributeName inRange:NSMakeRange(0, text.length) options:0 usingBlock:^(UIFont *font, NSRange range, BOOL *stop) {
        if (!font || hasMonospacedDigits(font)) return;
        if (!mapped) mapped = [text mutableCopy];
        [mapped addAttribute:NSFontAttributeName value:SGMonospacedDigitsFont(font) range:range];
    }];
    if (mapped) ((void (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&parent, @selector(setAttributedText:), mapped);
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

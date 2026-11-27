#import "SGViewTree.h"
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <os/lock.h>

static NSString *fileprivateKey(const char *name) {
    const char *marker = strstr(name, "P33_");
    if (!marker) return nil;
    const char *hash = marker + strlen("P33_");
    if (strspn(hash, "0123456789abcdefABCDEF") < 32 || hash[32] < '0' || hash[32] > '9') return nil;
    return [NSString stringWithFormat:@"%.*s%s", (int)(hash - name), name, hash + 32];
}

static BOOL inherits(Class cls, Class base) {
    for (Class ancestor = cls; ancestor; ancestor = class_getSuperclass(ancestor))
        if (ancestor == base) return YES;
    return NO;
}

Class SGFileprivateViewClass(const char *exactName, Class base) {
    Class cls = objc_lookUpClass(exactName);
    if (cls) return inherits(cls, base) ? cls : Nil;
    // All these Swift views live in Spotify's main executable. Do not realize the
    // system's classes or rescan the image for each hook that needs the fallback.
    static NSDictionary<NSString *, NSArray<NSString *> *> *index;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *names = [NSMutableDictionary dictionary];
        unsigned count = 0;
        const char **list = objc_copyClassNamesForImage(_dyld_get_image_name(0), &count);
        for (unsigned i = 0; i < count; ++i) {
            NSString *key = fileprivateKey(list[i]);
            if (!key) continue;
            if (!names[key]) names[key] = [NSMutableArray array];
            [names[key] addObject:@(list[i])];
        }
        free(list);
        index = names;
    });
    // Same-named classes can sit in other files; only one of the expected kind may stand in.
    Class found = Nil;
    for (NSString *name in index[fileprivateKey(exactName)]) {
        Class candidate = objc_lookUpClass(name.UTF8String);
        if (!inherits(candidate, base)) continue;
        if (found) return Nil;
        found = candidate;
    }
    return found;
}

void SGForEachView(UIView *view, void (^fn)(UIView *)) {
    fn(view);
    for (UIView *sub in view.subviews) SGForEachView(sub, fn);
}

CGRect SGFrameIn(UIView *view, UIView *target) {
    return [view.superview convertRect:view.frame toView:target];
}

UITableView *SGTableIn(UIView *view, NSInteger remainingDepth) {
    if ([view isKindOfClass:UITableView.class]) return (UITableView *)view;
    if (remainingDepth < 0) return nil;
    for (UIView *child in view.subviews) {
        UITableView *table = SGTableIn(child, remainingDepth - 1);
        if (table) return table;
    }
    return nil;
}

BOOL SGIsInside(UIView *view, UIView *root) {
    if (!root) return NO;
    for (UIView *v = view; v; v = v.superview) {
        if ([v isKindOfClass:UIVisualEffectView.class]) return NO;
        if (v == root) return YES;
    }
    return NO;
}

BOOL SGShownUnder(UIView *view, UIView *root) {
    for (UIView *v = view; v && v != root; v = v.superview) {
        if (v.hidden) return NO;
    }
    return YES;
}

BOOL SGIsRow(UIView *view) {
    return [view isKindOfClass:UIStackView.class] && view.bounds.size.width > 200 && ((UIStackView *)view).arrangedSubviews.count >= 2;
}

// Depth first, as SGForEachView walks, stopping at the first view `match` accepts.
static UIView *firstMatch(UIView *view, BOOL (^match)(UIView *view)) {
    if (match(view)) return view;
    for (UIView *sub in view.subviews) {
        UIView *found = firstMatch(sub, match);
        if (found) return found;
    }
    return nil;
}

UIStackView *SGRowIn(UIView *host) {
    return (UIStackView *)firstMatch(host, ^BOOL(UIView *v) { return SGIsRow(v); });
}

BOOL SGClassNamed(Class cls, NSString *marker) {
    if (!cls || !marker) return NO;
    // Markers are literals, so the outer level goes by the pointer and never hashes the string.
    static NSMapTable<NSString *, NSMutableDictionary *> *cache;
    static os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;
    os_unfair_lock_lock(&lock);
    if (!cache) cache = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsOpaqueMemory | NSPointerFunctionsOpaquePersonality
                                              valueOptions:NSPointerFunctionsStrongMemory];
    NSMutableDictionary *answers = [cache objectForKey:marker];
    if (!answers) [cache setObject:(answers = [NSMutableDictionary dictionary]) forKey:marker];
    NSNumber *answer = answers[(id<NSCopying>)cls];
    if (!answer) answers[(id<NSCopying>)cls] = answer = @([NSStringFromClass(cls) containsString:marker]);
    BOOL matches = answer.boolValue;
    os_unfair_lock_unlock(&lock);
    return matches;
}

BOOL SGHasClass(UIView *root, NSString *marker) {
    return firstMatch(root, ^BOOL(UIView *v) { return SGClassNamed(v.class, marker); }) != nil;
}

@interface SGWeakBox : NSObject
@property (nonatomic, weak) UIView *value;
@end

@implementation SGWeakBox
@end

UIView *SGFindRemembered(UIView *root, const void *key, BOOL (^match)(UIView *view)) {
    if (!root) return nil;
    SGWeakBox *box = objc_getAssociatedObject(root, key);
    UIView *cached = box.value;
    if (cached && match(cached) && [cached isDescendantOfView:root]) return cached;
    UIView *found = firstMatch(root, match);
    if (!found) return nil;
    if (!box) {
        box = [SGWeakBox new];
        objc_setAssociatedObject(root, key, box, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    box.value = found;
    return found;
}

UIView *SGFindIdentifier(UIView *root, NSString *prefix, const void *key) {
    return SGFindRemembered(root, key, ^BOOL(UIView *v) { return [v.accessibilityIdentifier hasPrefix:prefix]; });
}

BOOL SGKeepsColor(UIView *view) {
    return [view isKindOfClass:UIImageView.class] || [view isKindOfClass:UILabel.class] || view.bounds.size.height <= 4;
}

void SGStripBackgrounds(UIView *view) {
    if ([view isKindOfClass:UIVisualEffectView.class]) return;
    Class cls = view.class;
    // The karaoke views paint nothing to strip and hold a label for every word in sight.
    if (SGClassNamed(cls, @"SGRKaraoke")) return;
    if (!SGKeepsColor(view)) view.layer.backgroundColor = NULL;
    if ([view.layer isKindOfClass:CAGradientLayer.class] || SGClassNamed(cls, @"GradientView")) view.hidden = YES;
    for (CALayer *layer in view.layer.sublayers) {
        if ([layer isKindOfClass:CAGradientLayer.class]) layer.hidden = YES;
    }
    for (UIView *sub in view.subviews) SGStripBackgrounds(sub);
}

BOOL SGIsVisibleColor(CGColorRef color) {
    if (!color || CGColorGetAlpha(color) < 0.05) return NO;
    const CGFloat *c = CGColorGetComponents(color);
    size_t n = CGColorGetNumberOfComponents(color);
    CGFloat brightest = 0;
    for (size_t i = 0; i + 1 < n; i++) brightest = MAX(brightest, c[i]);
    return brightest > 0.08;
}

BOOL SGIsLightColor(CGColorRef color) {
    if (!color || CGColorGetAlpha(color) < 0.5) return NO;
    const CGFloat *c = CGColorGetComponents(color);
    size_t n = CGColorGetNumberOfComponents(color);
    for (size_t i = 0; i + 1 < n; i++) if (c[i] < 0.85) return NO;
    return YES;
}

// Lighter grays (#1F1F1F placeholders, #292929 cards) and translucent paint stay.
BOOL SGIsBaseSurface(CGColorRef color) {
    if (!color || CFGetTypeID(color) != CGColorGetTypeID() || CGColorGetAlpha(color) < 0.95) return NO;
    const CGFloat *c = CGColorGetComponents(color);
    size_t n = CGColorGetNumberOfComponents(color);
    if (n == 2) return c[0] <= 0.10;
    if (n < 3) return NO;
    return c[0] <= 0.10 && fabs(c[0] - c[1]) < 0.02 && fabs(c[1] - c[2]) < 0.02;
}

BOOL SGLooksLikeCard(UIView *view, CGColorRef color) {
    CGSize size = view.bounds.size;
    return size.height >= 40 && size.height <= 140 && size.width >= 200 && SGIsVisibleColor(color);
}

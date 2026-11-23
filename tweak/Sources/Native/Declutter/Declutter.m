#import "Declutter.h"
#import "Core/SGPrefs.h"
#import "Core/SGViewTree.h"
#import <objc/runtime.h>

BOOL SGNativeSectionHidden(NSString *title, const SGNativeSectionRule *rules, size_t count) {
    for (size_t i = 0; i < count; i++) {
        NSString *wanted = rules[i].title;
        BOOL match = rules[i].prefix
            ? [title.lowercaseString hasPrefix:wanted.lowercaseString]
            : rules[i].suffix ? [title hasSuffix:wanted]
            : [title caseInsensitiveCompare:wanted] == NSOrderedSame;
        if (match) return SGHidden(rules[i].key);
    }
    return NO;
}

BOOL SGNativeAnySectionHidden(const SGNativeSectionRule *rules, size_t count) {
    for (size_t i = 0; i < count; i++) {
        if (SGHidden(rules[i].key)) return YES;
    }
    return NO;
}

NSMutableDictionary<NSIndexPath *, NSString *> *SGNativeHeadings(UICollectionView *list, const void *key) {
    NSMutableDictionary *headings = objc_getAssociatedObject(list, key);
    if (!headings) {
        headings = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(list, key, headings, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return headings;
}

NSString *SGNativeSectionAt(NSIndexPath *path, NSDictionary<NSIndexPath *, NSString *> *headings) {
    for (NSInteger item = path.item; item >= 0; item--) {
        NSString *title = headings[[NSIndexPath indexPathForItem:item inSection:path.section]];
        if (!title) return nil;
        if (title.length) return title;
    }
    return nil;
}

BOOL SGNativeAnyMarkerHidden(const SGNativeMarkerRule *rules, size_t count) {
    for (size_t i = 0; i < count; i++) {
        if (SGHidden(rules[i].key)) return YES;
    }
    return NO;
}

NSString *SGNativeHiddenMarkerIn(UIView *cell, const SGNativeMarkerRule *rules, size_t count) {
    unsigned hidden = 0;   // a bit per switched-on rule (a block cannot capture an array)
    for (size_t i = 0; i < count; i++) if (SGHidden(rules[i].key)) hidden |= 1u << i;
    __block size_t first = count;
    SGForEachView(cell, ^(UIView *v) {
        if (v != cell && [v isKindOfClass:UICollectionView.class]) [v layoutIfNeeded];
        for (size_t i = 0; i < first; i++) {
            if ((hidden & 1u << i) && SGClassNamed(v.class, rules[i].marker)) first = i;
        }
    });
    return first < count ? rules[first].key : nil;
}

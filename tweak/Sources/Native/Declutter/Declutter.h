// Classification shared by the native pages; each page keeps its rules and view treatment.
#import <UIKit/UIKit.h>

typedef struct {
    __unsafe_unretained NSString *title, *key;
    BOOL prefix;
    BOOL suffix;
} SGNativeSectionRule;

typedef struct {
    __unsafe_unretained NSString *marker, *key;
} SGNativeMarkerRule;

BOOL SGNativeSectionHidden(NSString *title, const SGNativeSectionRule *rules, size_t count);
BOOL SGNativeAnySectionHidden(const SGNativeSectionRule *rules, size_t count);
// Each caller supplies its own key: album and artist histories must not share a namespace.
NSMutableDictionary<NSIndexPath *, NSString *> *SGNativeHeadings(UICollectionView *list, const void *key);
// nil means an unsized cell or no preceding heading; @"" records a sized nonheading cell.
NSString *SGNativeSectionAt(NSIndexPath *path, NSDictionary<NSIndexPath *, NSString *> *headings);
BOOL SGNativeAnyMarkerHidden(const SGNativeMarkerRule *rules, size_t count);
// Snapshots switches before traversal; lowest rule index wins, not the first matching view.
NSString *SGNativeHiddenMarkerIn(UIView *cell, const SGNativeMarkerRule *rules, size_t count);

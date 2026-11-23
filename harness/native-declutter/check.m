#import "Native/Declutter/Declutter.h"
#import "Core/SGPrefs.h"
#import "Core/SGViewTree.h"

@implementation UICollectionView
- (void)layoutIfNeeded { if (self.layout) self.layout(); }
@end
@implementation NSIndexPath (NativeDeclutterUIKit)
- (NSInteger)item { return [self indexAtPosition:1]; }
- (NSInteger)section { return [self indexAtPosition:0]; }
+ (instancetype)indexPathForItem:(NSInteger)item inSection:(NSInteger)section {
    NSUInteger indexes[] = {(NSUInteger)section, (NSUInteger)item};
    return [self indexPathWithIndexes:indexes length:2];
}
@end

@interface FirstMarker : UIView @end
@implementation FirstMarker @end
@interface SecondMarker : UIView @end
@implementation SecondMarker @end

static NSDictionary<NSString *, NSNumber *> *switches;
#include "album-rules.inc"
BOOL SGHidden(NSString *key) { return [switches[key] boolValue]; }
BOOL SGClassNamed(Class cls, NSString *marker) {
    return [NSStringFromClass(cls) containsString:marker];
}
void SGForEachView(UIView *view, void (^visit)(UIView *)) {
    visit(view);
    for (UIView *child in view.subviews) SGForEachView(child, visit);
}

static NSUInteger checks;
static void check(BOOL ok, NSString *name) {
    if (!ok) {
        NSLog(@"FAIL native declutter: %@", name);
        exit(1);
    }
    checks++;
}

static NSIndexPath *path(NSInteger item, NSInteger section) {
    return [NSIndexPath indexPathForItem:item inSection:section];
}

static void checkAlbumHeadings(void) {
    for (NSArray *row in @[
        @[@"The Weeknd의 곡 더 보기", SGHideAlbumMoreBy, SGRKeyAlbumHideMoreBy],
        @[@"콘서트", SGHideAlbumConcerts, SGRKeyAlbumHideConcerts],
        @[@"굿즈", SGHideAlbumMerch, SGRKeyAlbumHideMerch],
        @[@"이건 어떠세요", SGHideAlbumYouMightLike, SGRKeyAlbumHideYouMightLike],
        @[@"MORE BY The Weeknd", SGHideAlbumMoreBy, SGRKeyAlbumHideMoreBy],
        @[@"의 곡 더 보기 extra", @"", SGRKeyAlbumHideOther],
        @[@"굿즈 extra", @"", SGRKeyAlbumHideOther],
        @[@"unknown", @"", SGRKeyAlbumHideOther],
    ]) {
        NSString *title = row[0];
        NSInteger i = sectionTitled(title);
        check([(i == kOther ? SGRKeyAlbumHideOther : kSections[i].key) isEqual:row[2]], title);
        for (NSString *key in @[SGHideAlbumMoreBy, SGHideAlbumMerch, SGHideAlbumYouMightLike,
                                SGHideAlbumVideos, SGHideAlbumConcerts]) {
            switches = @{key: @YES};
            check(SGNativeSectionHidden(title, sections, sizeof(sections)/sizeof(*sections)) == [key isEqual:row[1]], title);
        }
    }
}

int main(void) {
    @autoreleasepool {
        checkAlbumHeadings();
        const SGNativeSectionRule sections[] = {
            {@"Popular", @"popular", NO},
            {@"Featuring ", @"featuring", YES},
            {@"Popular", @"duplicate", NO},
        };
        switches = @{@"popular": @NO, @"featuring": @YES, @"duplicate": @YES};
        check(!SGNativeSectionHidden(@"POPULAR", sections, 3), @"first matching rule owns the switch even when off");
        check(SGNativeSectionHidden(@"FEATURING Artist", sections, 3), @"prefix matching ignores case");
        check(!SGNativeSectionHidden(@"Popular releases", sections, 3), @"exact headings do not match a longer title");
        check(!SGNativeSectionHidden(@"Merch", sections, 3), @"unlisted heading stays visible");
        check(SGNativeAnySectionHidden(sections, 3), @"a later section switch can enable classification");
        switches = @{};
        check(!SGNativeAnySectionHidden(sections, 3), @"unset section switches are off");
        switches = @{@"popular": @YES};
        check(SGNativeSectionHidden(@"POPULAR", sections, 3), @"exact heading matching ignores case");

        UICollectionView *list = [UICollectionView new];
        static char albumKey, artistKey;
        NSMutableDictionary *headings = SGNativeHeadings(list, &albumKey);
        headings[path(0, 0)] = @"Popular";
        headings[path(1, 0)] = @"";
        check([SGNativeSectionAt(path(1, 0), headings) isEqual:@"Popular"], @"sized nonheading inherits the preceding heading");
        headings[path(3, 0)] = @"";
        check(SGNativeSectionAt(path(3, 0), headings) == nil, @"an unsized gap stops heading inheritance");
        headings[path(0, 1)] = @"";
        check(SGNativeSectionAt(path(0, 1), headings) == nil, @"headings never cross collection sections");
        headings[path(2, 0)] = @"Merch";
        check([SGNativeSectionAt(path(3, 0), headings) isEqual:@"Merch"], @"a new heading supersedes the earlier heading");
        check([SGNativeSectionAt(path(1, 0), SGNativeHeadings(list, &albumKey)) isEqual:@"Popular"], @"history persists on the same list and key");
        check(SGNativeSectionAt(path(1, 0), SGNativeHeadings(list, &artistKey)) == nil, @"caller cache namespaces stay separate");
        check(SGNativeSectionAt(path(1, 0), SGNativeHeadings([UICollectionView new], &albumKey)) == nil, @"different lists have separate history");

        const SGNativeMarkerRule markers[] = {
            {@"FirstMarker", @"first"}, {@"SecondMarker", @"second"},
        };
        UIView *cell = [UIView new];
        cell.subviews = @[[SecondMarker new], [FirstMarker new]];
        switches = @{@"first": @YES, @"second": @YES};
        check([SGNativeHiddenMarkerIn(cell, markers, 2) isEqual:@"first"], @"rule priority wins over view traversal order");
        switches = @{@"second": @YES};
        check([SGNativeHiddenMarkerIn(cell, markers, 2) isEqual:@"second"], @"disabled higher-priority rule is ignored");
        check(SGNativeAnyMarkerHidden(markers, 2), @"later marker switch enables scanning");
        switches = @{};
        check(!SGNativeAnyMarkerHidden(markers, 2), @"unset marker switches are off");
        check(SGNativeHiddenMarkerIn(cell, markers, 2) == nil, @"no enabled matching marker returns nil");
        switches = @{@"first": @YES};
        check([SGNativeHiddenMarkerIn([FirstMarker new], markers, 2) isEqual:@"first"], @"the root itself can name a marker");

        UICollectionView *nested = [UICollectionView new];
        __weak UICollectionView *weakNested = nested;
        nested.layout = ^{ weakNested.subviews = @[[FirstMarker new]]; };
        cell.subviews = @[nested];
        check([SGNativeHiddenMarkerIn(cell, markers, 2) isEqual:@"first"], @"nested layout publishes children before they are classified");
        nested.layout = ^{
            switches = @{@"first": @NO, @"second": @YES};
            weakNested.subviews = @[[FirstMarker new], [SecondMarker new]];
        };
        check([SGNativeHiddenMarkerIn(cell, markers, 2) isEqual:@"first"], @"switch snapshot survives changes during nested layout");

        __block BOOL laidOut = NO;
        nested.layout = ^{ laidOut = YES; };
        cell.subviews = @[[FirstMarker new], nested];
        switches = @{@"first": @YES};
        SGNativeHiddenMarkerIn(cell, markers, 2);
        check(laidOut, @"nested layout still runs after the highest-priority match");
        laidOut = NO;
        SGNativeHiddenMarkerIn(nested, markers, 2);
        check(!laidOut, @"the root collection is not laid out by classification");
        NSLog(@"PASS native declutter: %lu checks", (unsigned long)checks);
    }
    return 0;
}

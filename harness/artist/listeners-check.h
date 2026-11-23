#import "Redesigned/Kit/SGRRestyle.h"

// The first header must not depend on an About cell ever being configured.
static NSArray *listenersItems(BOOL about) {
    return about ? @[@[@"Components.UI.CreatorBiographyCard", @180]]
                 : @[@[@"Components.UI.RetrievalRowElementUI", @64, @"A song"]];
}

static void listenersExpect(UIView *header, UIView *info, NSString *text, BOOL shown) {
    [header layoutIfNeeded];
    [info layoutIfNeeded];
    UILabel *line = [info valueForKey:@"_length"];
    HARNESS_CHECK(line);
    if (shown ? (line.hidden || ![line.text isEqualToString:text]) : !line.hidden)
        HARNESS_FAIL(@"listeners: expected %@ for %@, got text=%@ hidden=%d",
                     shown ? @"visible" : @"hidden", text, line.text, line.hidden);
}

static void verifyListeners(UIViewController *root, UIView *header, UICollectionView *list, SGRListSource *source) {
    BOOL shown = [NSProcessInfo.processInfo.arguments containsObject:@"expect-listeners"];
    UIView *info = veilFind(root.view, @"SGRHeaderInfo");
    HARNESS_CHECK(info);
    listenersExpect(header, info, @"58,4M monthly listeners", shown);

    UIView *more = SGRFindByIdentifier(header, @"Components.UI.ContextMenuButton*", NULL);
    UILabel *metadata = (UILabel *)SGRFindByIdentifier(header, @"Components.Header.UI.Metadata-internal", NULL);
    HARNESS_CHECK(more && metadata);
    more.accessibilityIdentifier = @"Components.UI.ContextMenuButton-artist-B";
    metadata.text = @"월별 리스너 123,456명";
    [header setNeedsLayout];
    listenersExpect(header, info, metadata.text, shown);
    NSLog(@"[harness] PASS artist listeners: initial layout and artist switch");
    exit(0);
}

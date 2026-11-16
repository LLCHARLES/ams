// The saved composition of the redesign's bar, as NSUserDefaults property lists, apart from the native look's.
#import "Navbar.h"
#import "Shared/Navigation/Links.h"

NSString *const SGRNavbarID = @"id";
NSString *const SGRNavbarTitle = @"title";
NSString *const SGRNavbarURI = @"uri";
NSString *const SGRNavbarIcon = @"icon";
NSString *const SGRNavbarIconSet = @"iconSet";
NSString *const SGRNavbarHidden = @"hidden";

static NSString *const kNavbarLayout = @"spotifyglass.redesign.navbar.layout";
static NSString *const kNavbarStock = @"spotifyglass.redesign.navbar.stock";
static NSString *const kNavbarSplit = @"spotifyglass.redesign.navbar.apart";
static NSString *const kNavbarSplitWas = @"spotifyglass.redesign.navbar.split";

// Only property list types go in, so a corrupt read cannot be anything but an array of dictionaries.
static NSArray *listOfKind(NSString *key, Class kind) {
    NSArray *list = [NSUserDefaults.standardUserDefaults arrayForKey:key];
    for (id item in list) if (![item isKindOfClass:kind]) return @[];
    return list ?: @[];
}

NSArray<NSDictionary *> *SGRNavbarLayout(void) {
    return listOfKind(kNavbarLayout, NSDictionary.class);
}

void SGRSetNavbarLayout(NSArray<NSDictionary *> *layout) {
    [NSUserDefaults.standardUserDefaults setObject:layout ?: @[] forKey:kNavbarLayout];
}

void SGRFoldNavbarSplit(void) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    // The list before Split tabs had one of its own named entries the bar's list still held, so nothing moves for it.
    [store removeObjectForKey:kNavbarSplitWas];
    if (![store objectForKey:kNavbarSplit]) return;
    NSMutableArray<NSDictionary *> *layout = [SGRNavbarLayout() mutableCopy];
    // No list is Spotify's order, which a list naming one tab would put after it: written out first.
    if (!layout.count) for (NSString *ident in SGRNavbarStock()) [layout addObject:@{SGRNavbarID: ident, SGRNavbarTitle: ident}];
    for (NSDictionary *entry in listOfKind(kNavbarSplit, NSDictionary.class)) {
        NSString *ident = entry[SGRNavbarID];
        if (![ident isKindOfClass:NSString.class]) continue;
        // A tab of Spotify's stood in one place, on the right, so it leaves wherever the bar's list had it.
        NSIndexSet *there = [layout indexesOfObjectsPassingTest:^BOOL(NSDictionary *other, NSUInteger i, BOOL *stop) {
            return [other[SGRNavbarID] isEqual:ident];
        }];
        if (entry[SGRNavbarURI] && there.count) continue;
        [layout removeObjectsAtIndexes:there];
        NSMutableDictionary *shown = [entry mutableCopy];
        [shown removeObjectForKey:SGRNavbarHidden];
        [layout addObject:shown];
    }
    SGRSetNavbarLayout(layout);
    [store removeObjectForKey:kNavbarSplit];
}

void SGRMigrateNavbarSplit(void) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    if (![store objectForKey:kNavbarSplitWas]) return;
    if ([store objectForKey:kNavbarSplit]) {
        [store removeObjectForKey:kNavbarSplitWas];
        return;
    }
    NSMutableOrderedSet<NSString *> *split = [NSMutableOrderedSet orderedSetWithArray:listOfKind(kNavbarSplitWas, NSString.class)];
    NSMutableArray<NSDictionary *> *layout = [NSMutableArray array], *apart = [NSMutableArray array];
    for (NSDictionary *entry in SGRNavbarLayout()) {
        NSString *ident = entry[SGRNavbarID];
        BOOL listed = [ident isKindOfClass:NSString.class] && [split containsObject:ident];
        if (listed) [split removeObject:ident];
        if (!listed || [entry[SGRNavbarHidden] boolValue]) {
            [layout addObject:entry];
            continue;
        }
        if (entry[SGRNavbarURI]) [apart addObject:entry];
        else {
            [layout addObject:entry];
            [apart addObject:@{SGRNavbarID: ident, SGRNavbarTitle: entry[SGRNavbarTitle] ?: ident}];
        }
    }
    // Spotify's tabs the bar's list never named stood where Spotify put them: in Spotify's order, not the old list's,
    // which was saved from a set and so in none.
    NSArray<NSString *> *stock = SGRNavbarStock();
    NSArray<NSString *> *rest = [split.array sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSUInteger ia = [stock indexOfObject:a], ib = [stock indexOfObject:b];
        return ia < ib ? NSOrderedAscending : ia > ib ? NSOrderedDescending : NSOrderedSame;
    }];
    for (NSString *ident in rest) [apart addObject:@{SGRNavbarID: ident, SGRNavbarTitle: ident}];
    SGRSetNavbarLayout(layout);
    SGRSetNavbarSplit(apart);
    [store removeObjectForKey:kNavbarSplitWas];
}

NSArray<NSDictionary *> *SGRNavbarSplit(void) {
    return listOfKind(kNavbarSplit, NSDictionary.class);
}

// Below iOS 26 the capsule bar has one round button for the split tab, so it shows the last one set apart. Only the
// bar reads it this way: the Split tabs page reads and writes the whole list, so an edit below iOS 26 keeps the rest
// for iOS 26.
NSArray<NSDictionary *> *SGRNavbarSplitShown(void) {
    NSArray<NSDictionary *> *split = SGRNavbarSplit();
    if (split.count > 1 && SGRLegacyTabBarOn()) return @[split.lastObject];
    return split;
}

void SGRSetNavbarSplit(NSArray<NSDictionary *> *split) {
    [NSUserDefaults.standardUserDefaults setObject:split ?: @[] forKey:kNavbarSplit];
}

NSArray<NSString *> *SGRNavbarStock(void) {
    return listOfKind(kNavbarStock, NSString.class);
}

void SGRSetNavbarStock(NSArray<NSString *> *stock) {
    [NSUserDefaults.standardUserDefaults setObject:stock ?: @[] forKey:kNavbarStock];
}

NSURL *SGRNavbarTabURL(NSString *uri) {
    NSURL *url = SGSpotifyURIFromText(uri);
    if ([url.absoluteString isEqualToString:@"spotify:collection:playlists"]) return [NSURL URLWithString:@"spotify:playlists"];
    return url;
}

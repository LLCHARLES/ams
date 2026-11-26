#import "SGSettingsIndex.h"
#import <objc/runtime.h>

static const NSUInteger kDepth = 3;
static const NSUInteger kMostHits = 60;
static const NSUInteger kMostRecents = 6;

#pragma mark - folding

NSString *SGSearchFold(NSString *text) {
    return [text ?: @"" stringByFoldingWithOptions:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch
                                            locale:NSLocale.currentLocale];
}

static NSString *const kInitials[19] = {@"ㄱ", @"ㄲ", @"ㄴ", @"ㄷ", @"ㄸ", @"ㄹ", @"ㅁ", @"ㅂ", @"ㅃ", @"ㅅ",
                                        @"ㅆ", @"ㅇ", @"ㅈ", @"ㅉ", @"ㅊ", @"ㅋ", @"ㅌ", @"ㅍ", @"ㅎ"};

static NSInteger initialsIndex(unichar c) {
    for (NSInteger i = 0; i < 19; i++) {
        if ([kInitials[i] characterAtIndex:0] == c) return i;
    }
    return NSNotFound;
}

static BOOL hasSyllable(NSString *text) {
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if (c >= 0xAC00 && c <= 0xD7A3) return YES;
    }
    return NO;
}

// Each precomposed syllable becomes its initial consonant; the rest is the folded text. Folding normally keeps
// syllables precomposed, but if it decomposed them, the raw text supplies the syllables and the rest is folded
// character by character.
NSString *SGSearchInitials(NSString *text) {
    NSString *folded = SGSearchFold(text);
    BOOL raw = !hasSyllable(folded) && hasSyllable(text);
    NSString *base = raw ? text : folded;
    NSMutableString *initials = [NSMutableString string];
    for (NSUInteger i = 0; i < base.length; i++) {
        unichar c = [base characterAtIndex:i];
        if (c >= 0xAC00 && c <= 0xD7A3) [initials appendString:kInitials[(c - 0xAC00) / 588]];
        else if (raw) [initials appendString:SGSearchFold([base substringWithRange:NSMakeRange(i, 1)])];
        else [initials appendFormat:@"%C", c];
    }
    return initials;
}

// A word of only the 19 compatibility consonants a syllable can start with, so it is compared to initials.
BOOL SGSearchIsInitialsWord(NSString *word) {
    if (!word.length) return NO;
    for (NSUInteger i = 0; i < word.length; i++) {
        if (initialsIndex([word characterAtIndex:i]) == NSNotFound) return NO;
    }
    return YES;
}

// A query of initials words, which may be separated by spaces, also compares its start to the title's initials.
static BOOL isInitialsQuery(NSString *query) {
    BOOL any = NO;
    for (NSUInteger i = 0; i < query.length; i++) {
        unichar c = [query characterAtIndex:i];
        if ([[NSCharacterSet whitespaceCharacterSet] characterIsMember:c]) continue;
        if (initialsIndex(c) == NSNotFound) return NO;
        any = YES;
    }
    return any;
}

BOOL SGSearchWordMatches(NSString *word, NSString *folded, NSString *initials) {
    return [(SGSearchIsInitialsWord(word) ? initials : folded) containsString:word];
}

BOOL SGSearchStartsTitle(NSString *query, NSString *foldedTitle, NSString *initialsTitle) {
    if (isInitialsQuery(query) && [initialsTitle hasPrefix:query]) return YES;
    return [foldedTitle hasPrefix:query];
}

#pragma mark - the settings opened before

// A place is an array of the setting names the results led through, the searched page's row first and the row last:
// what the search remembers so the same setting is found again in any language and in the look it belongs to. It is
// never a title (those are translated and change with the language) and never what was typed.
static BOOL isPlace(id value) {
    if (![value isKindOfClass:NSArray.class] || ![value count]) return NO;
    for (id name in (NSArray *)value) {
        if (![name isKindOfClass:NSString.class] || ![name length]) return NO;
    }
    return YES;
}

static NSArray<NSArray<NSString *> *> *recentPlaces(NSArray *newest, NSArray *(^resolve)(NSArray *)) {
    NSMutableArray<NSArray<NSString *> *> *places = [NSMutableArray array];
    if (newest) [places addObject:resolve ? resolve(newest) : newest];
    for (id entry in [NSUserDefaults.standardUserDefaults arrayForKey:SGKeySearchRecents] ?: @[]) {
        if (places.count == kMostRecents) break;
        if (!isPlace(entry)) continue;
        NSArray *place = resolve ? resolve(entry) : entry;
        if (![places containsObject:place]) [places addObject:place];
    }
    return places;
}

NSArray<NSArray<NSString *> *> *SGSearchRecents(void) {
    return recentPlaces(nil, nil);
}

void SGSearchForgetRecents(void) {
    [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeySearchRecents];
}

#pragma mark - a row the search finds

@interface SGSettingsHit ()
@property (nonatomic, copy) NSString *title, *subtitle;
@property (nonatomic, copy) NSArray<NSString *> *trail, *place;
@property (nonatomic, copy) NSString *symbol;
@property (nonatomic, strong) UIColor *tint;
@property (nonatomic, copy) UIViewController *(^open)(void);
@property (nonatomic) BOOL opens;
// The whole text a word may be found in, and the title on its own, folded; and the same with each syllable as its
// initial, kept from the raw text in case folding decomposes Hangul.
@property (nonatomic, copy) NSString *folded, *foldedTitle, *initials, *initialsTitle;
@end

@implementation SGSettingsHit
@end

// What a row is remembered as: its own name, else its key, which the switch it stores under already gives it. A row
// with neither is not one the search can lead back to, and nor is a row under a page row with neither.
static NSString *nameOf(SGModRow *row) {
    return row.searchIdentifier.length ? row.searchIdentifier : row.key.length ? row.key : nil;
}

// The text a row is found by, in the order the trail reads: keyword last, so a row is found by a word its owner
// supplied even when its title and the pages above it do not hold it.
static NSString *searchableText(SGModRow *row, NSArray<NSString *> *trail) {
    return [@[row.title, row.subtitle ?: @"", [trail componentsJoinedByString:@" "], row.searchKeywords ?: @""] componentsJoinedByString:@"\n"];
}

static SGSettingsHit *hitFor(SGModRow *row, SGModRow *lead, NSArray<NSString *> *trail, NSArray<NSString *> *names,
                             UIViewController *(^opener)(void)) {
    SGSettingsHit *hit = [SGSettingsHit new];
    hit.title = row.title;
    hit.subtitle = row.subtitle;
    hit.trail = trail;
    // A name of its own, or one the page above gave it; a chain with a gap in it is no place at all.
    NSString *name = nameOf(row);
    hit.place = name && names ? [names arrayByAddingObject:name] : nil;
    hit.symbol = lead.symbol;
    hit.tint = lead.tint;
    // A row that opens a page is found as that page, whatever kind it is; a choice row's list is not one, and the
    // row itself is what is found.
    hit.opens = row.page && !row.choice;
    hit.open = hit.opens ? row.page : opener;
    NSString *text = searchableText(row, trail);
    hit.foldedTitle = SGSearchFold(row.title);
    hit.folded = SGSearchFold(text);
    hit.initialsTitle = SGSearchInitials(row.title);
    hit.initials = SGSearchInitials(text);
    return hit;
}

#pragma mark - the pages read so far

// A page still to be read: what builds it, the pages above its rows, the names of the settings those pages are, what
// picking one of its rows opens, and the searched page's row its tile comes from. It is built in the pass that reads
// it, so one pass builds one page.
@interface SGSettingsPending : NSObject
@property (nonatomic, copy) UIViewController *(^factory)(void);
@property (nonatomic, copy) NSArray<NSString *> *trail;
@property (nonatomic, copy) NSArray<NSString *> *names;   // the place's names so far; nil when the chain has a gap
@property (nonatomic, copy) UIViewController *(^opener)(void);
@property (nonatomic, strong) SGModRow *top;
@property (nonatomic) NSUInteger depth;
@end

@implementation SGSettingsPending
@end

static char kRenameKey, kPlacesKey;

void SGSettingsIndexRenamesWith(SGModPage *page, void (^rename)(void)) {
    objc_setAssociatedObject(page, &kRenameKey, rename, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

void SGSettingsIndexMovesWith(SGModPage *page, NSArray *(^resolve)(NSArray *)) {
    objc_setAssociatedObject(page, &kPlacesKey, resolve, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

@implementation SGSettingsIndex {
    NSMutableArray<SGSettingsHit *> *_all;
    NSMutableArray<SGSettingsPending *> *_todo;
    NSArray *(^_resolve)(NSArray *);
}

- (void)startWithRoot:(SGModPage *)root {
    _generation++;
    _all = [NSMutableArray array];
    _todo = [NSMutableArray array];
    _resolve = objc_getAssociatedObject(root, &kPlacesKey);
    if (!root) return;
    void (^rename)(void) = objc_getAssociatedObject(root, &kRenameKey);
    if (rename) rename();
    [self read:root.sections trail:@[] names:@[] opener:nil top:nil depth:0];
}

- (BOOL)running {
    return _todo != nil;
}

- (void)stop {
    _generation++;
    _all = nil;
    _todo = nil;
}

// Runs the pass the index was asked for, then asks for the one after it. A scheduled selector is given an object, so
// the generation travels in a number and is unboxed here; a pass of a build the index left (started again, or
// stopped) builds nothing.
- (void)stepScheduled:(NSNumber *)generation {
    if (generation.unsignedIntegerValue != _generation || ![self step]) return;
    [self performSelector:@selector(stepScheduled:) withObject:generation afterDelay:0];
}

- (void)scheduleStep {
    [self performSelector:@selector(stepScheduled:) withObject:@(_generation) afterDelay:0];
}

- (BOOL)step {
    if (!_todo) return NO;
    if (!_todo.count) {
        // Read to the end: the passes are over, and what was read stays.
        _todo = nil;
        if (_grew) _grew();   // so the results can say there are none
        return NO;
    }
    SGSettingsPending *pending = _todo.firstObject;
    [_todo removeObjectAtIndex:0];
    [self readPending:pending];
    if (_grew) _grew();
    return YES;
}

- (void)readPending:(SGSettingsPending *)pending {
    UIViewController *child = pending.factory ? pending.factory() : nil;
    NSArray *sections;
    if ([child isKindOfClass:SGModPage.class]) sections = ((SGModPage *)child).sections;
    else if ([child conformsToProtocol:@protocol(SGSettingsSearchPages)])
        sections = @[SGSection(nil, [(id<SGSettingsSearchPages>)child sg_searchPageRows])];
    else return;
    [self read:sections trail:pending.trail names:pending.names opener:pending.opener top:pending.top depth:pending.depth];
}

// Reads a page's rows, adds their hits, and puts the page each of them opens in line to be read, within reach.
- (void)read:(NSArray<SGModSection *> *)sections trail:(NSArray<NSString *> *)trail names:(NSArray<NSString *> *)names opener:(UIViewController *(^)(void))opener
         top:(SGModRow *)top depth:(NSUInteger)depth {
    for (SGModSection *section in sections) {
        for (SGModRow *row in section.rows) {
            // A row that shows only under some other setting is left out while it would not show.
            if (!row.title.length || (row.visible && !row.visible())) continue;
            SGModRow *lead = top ?: row;
            NSString *name = nameOf(row);
            [_all addObject:hitFor(row, lead, trail, names, opener)];
            if (row.page && !row.choice && depth < kDepth) {
                SGSettingsPending *pending = [SGSettingsPending new];
                pending.factory = row.page;
                pending.trail = [trail arrayByAddingObject:row.title];
                // A page whose own row has no name keeps the chain broken, so none of its rows is remembered.
                pending.names = name && names ? [names arrayByAddingObject:name] : nil;
                pending.opener = row.page;
                pending.top = lead;
                pending.depth = depth + 1;
                [_todo addObject:pending];
            }
        }
    }
}

- (NSArray<SGSettingsHit *> *)hitsForQuery:(NSString *)query {
    query = [SGSearchFold(query) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (!query.length || !_all) return @[];
    NSArray<NSString *> *words = [query componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSMutableArray<SGSettingsHit *> *ranks[3] = {[NSMutableArray array], [NSMutableArray array], [NSMutableArray array]};
    for (SGSettingsHit *hit in _all) {
        BOOL found = YES, inTitle = YES;
        for (NSString *word in words) {
            if (!word.length) continue;
            if (!SGSearchWordMatches(word, hit.folded, hit.initials)) { found = NO; break; }
            inTitle = inTitle && SGSearchWordMatches(word, hit.foldedTitle, hit.initialsTitle);
        }
        if (!found) continue;
        [ranks[SGSearchStartsTitle(query, hit.foldedTitle, hit.initialsTitle) ? 0 : inTitle ? 1 : 2] addObject:hit];
    }
    NSMutableArray<SGSettingsHit *> *hits = [NSMutableArray array];
    for (int i = 0; i < 3; i++) [hits addObjectsFromArray:ranks[i]];
    return hits.count > kMostHits ? [hits subarrayWithRange:NSMakeRange(0, kMostHits)] : hits;
}

- (void)rememberPlace:(NSArray<NSString *> *)place {
    if (isPlace(place)) [NSUserDefaults.standardUserDefaults setObject:recentPlaces(place, _resolve) forKey:SGKeySearchRecents];
}

- (NSArray<SGSettingsHit *> *)recentHits {
    NSMutableArray<SGSettingsHit *> *hits = [NSMutableArray array];
    for (NSArray<NSString *> *place in recentPlaces(nil, _resolve)) {
        for (SGSettingsHit *hit in _all) {
            if (![hit.place isEqualToArray:place]) continue;
            [hits addObject:hit];
            break;
        }
    }
    return hits;
}

@end

// Mod Settings' search index (Settings/SGSettingsIndex.m) against pages of plain rows: the whole path a query takes
// from the page it was typed on to the rows two pages down, with no simulator and no UIKit view to lay out.
//
// The pages are the real SGModPage.h row model and the real index; the pages themselves are built by blocks of this
// check's own that count their builds, so a page built by a pass is told from one built when its row was read.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "Core/SGPrefs.h"
#import "Settings/SGModPage.h"
#import "Settings/SGSettingsIndex.h"
#import "Settings/SGSettingsSearch.h"

static NSUInteger checks, failures;

static void check(BOOL ok, NSString *label) {
    fprintf(stdout, "%s %s\n", ok ? "PASS" : "FAIL", label.UTF8String);
    checks++;
    if (!ok) failures++;
}

// How many pages the index built, in all: one per pass, so a pass that builds nothing is a pass that did nothing.
static NSUInteger built;
static NSString *const kGate = @"spotifyglass.harness.searchgate";

static SGModRow *row(NSString *title, NSString *subtitle) {
    SGModRow *r = [SGModRow new];
    r.title = title;
    r.subtitle = subtitle;
    // Rows stand in for real settings, which are remembered by their key; a row of this check is given the title as
    // its name, so the check can say which row a place leads to.
    r.searchIdentifier = [NSString stringWithFormat:@"row.%@", title];
    return r;
}

static SGModRow *pageRow(NSString *title, UIViewController *(^page)(void)) {
    SGModRow *r = row(title, nil);
    r.page = page;
    return r;
}

static SGModPage *pageOf(NSString *title, NSArray<SGModRow *> *rows) {
    return [[SGModPage alloc] initWithTitle:title intro:nil sections:@[SGSection(nil, rows)] footer:nil];
}

// The page the search is typed on: a switch that hides a row, rows of its own, pages under it, and a page three
// levels down, which is out of reach.
static UIViewController *tooFarPage(void);

static UIViewController *deeperPage(void) {
    built++;
    return pageOf(@"Deeper", @[row(@"Deeper row", nil), pageRow(@"Too far", ^UIViewController *{ return tooFarPage(); })]);
}

static UIViewController *deepPage(void) {
    built++;
    return pageOf(@"Deep", @[row(@"Deep row", nil), pageRow(@"Deeper", ^UIViewController *{ return deeperPage(); })]);
}

static UIViewController *tooFarPage(void) {
    built++;
    return pageOf(@"Too far", @[row(@"Out of reach", nil)]);
}

static UIViewController *carPlayPage(void) {
    built++;
    return pageOf(@"Live Activity", @[SGSearchKeywords(row(@"Artwork", nil), @"dynamic island carplay")]);
}

static UIViewController *appearancePage(void) {
    built++;
    return pageOf(@"Appearance", @[SGSearchKeywords(row(@"Font", nil), @"typeface"), row(@"Accent color", @"Colour")]);
}

static SGModPage *rootPage(void) {
    SGModRow *gate = SGOptionRow(@"Show the hidden rows", nil, kGate);
    SGModRow *hidden = row(@"Concealed setting", nil);
    hidden.visible = ^BOOL { return SGFlag(kGate, NO); };
    return [[SGModPage alloc] initWithTitle:@"Retrine" intro:nil
                                   sections:@[
        SGSection(nil, @[gate, hidden, row(@"Plain title", @"Plain subtitle")]),
        SGSection(nil, @[pageRow(@"Live Activity", ^UIViewController *{ return carPlayPage(); }),
                         pageRow(@"Appearance", ^UIViewController *{ return appearancePage(); }),
                         pageRow(@"Deep", ^UIViewController *{ return deepPage(); })]),
    ] footer:nil];
}

static NSArray<NSString *> *titles(NSArray<SGSettingsHit *> *hits) {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (SGSettingsHit *hit in hits) [names addObject:hit.title];
    return names;
}

// One pass at a time, as the run loop does it.
static void pass(SGSettingsIndex *index) {
    [index step];
}

static SGSettingsIndex *started(void) {
    SGSettingsIndex *index = [SGSettingsIndex new];
    [index startWithRoot:rootPage()];
    return index;
}

static void checkEveryHitIsUnique(NSArray<SGSettingsHit *> *hits, NSString *label) {
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (SGSettingsHit *hit in hits) {
        NSString *place = [hit.place componentsJoinedByString:@" › "];
        if ([seen containsObject:place]) {
            check(NO, [NSString stringWithFormat:@"%@: %@ listed twice", label, place]);
            return;
        }
        [seen addObject:place];
    }
    check(YES, [NSString stringWithFormat:@"%@: every row once", label]);
}

static void runChecks(void) {
    [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeySearchRecents];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:kGate];

    // The page itself is read as the field opens, so its own rows are found before a single page under it is built.
    built = 0;
    SGSettingsIndex *index = started();
    check([titles([index hitsForQuery:@"plain"]) isEqual:@[@"Plain title"]], @"the page's own rows are found at once");
    check(built == 0, @"opening the field builds no page under the page");
    check(index.running, @"the pages under the page are still to be read");

    // The first pass builds one page, and its rows join the ones found before it: the pages after it are still to be
    // read, so a row of the page the pass did not build is not found yet.
    pass(index);
    check(built == 1, @"a pass builds one page");
    check([titles([index hitsForQuery:@"carplay"]) isEqual:@[@"Artwork"]], @"a row's keywords are found once its page is read");
    check([index hitsForQuery:@"typeface"].count == 0, @"a page no pass has built yet is not found");
    check([titles([index hitsForQuery:@"plain"]) isEqual:@[@"Plain title"]], @"the rows found before are still found");

    // The next pass adds the page after it.
    pass(index);
    check(built == 2 && [titles([index hitsForQuery:@"typeface"]) isEqual:@[@"Font"]], @"the next pass's page joins the rows found before it");

    // The rows of the pages already read are matched against a new query as they are; nothing is read again.
    NSUInteger before = built;
    check([titles([index hitsForQuery:@"colour"]) isEqual:@[@"Accent color"]], @"a later query matches the rows already read");
    check([titles([index hitsForQuery:@"subtitle"]) isEqual:@[@"Plain title"]], @"a row's subtitle is found");
    check([titles([index hitsForQuery:@"live activity"]) isEqual:(@[@"Live Activity", @"Artwork"])], @"the page above a row is found by its name, and the page itself too");
    check(built == before, @"a new query builds nothing again");

    // Within reach: the pages the page's rows open, then the pages theirs open. The third level is not read.
    while (index.running) pass(index);
    check([titles([index hitsForQuery:@"deeper row"]) isEqual:@[@"Deeper row"]], @"the second level's rows are found");
    check([index hitsForQuery:@"out of reach"].count == 0, @"a page three levels down is out of reach");

    // A title the query starts lands over a row only its keywords hold.
    SGSettingsIndex *ranked = started();
    while (ranked.running) pass(ranked);
    check([titles([ranked hitsForQuery:@"carplay"]) isEqual:@[@"Artwork"]], @"a keyword-only row is found under the word it was given");
    check([titles([ranked hitsForQuery:@"appearance"]).firstObject isEqual:@"Appearance"], @"a title hit leads the page's own row");
    check([titles([ranked hitsForQuery:@"typeface"]).firstObject isEqual:@"Font"], @"a keyword hit holds the word");
    NSArray<SGSettingsHit *> *accent = [ranked hitsForQuery:@"accent"];
    check(accent.count == 1 && [accent.firstObject.place isEqualToArray:@[@"row.Appearance", @"row.Accent color"]],
          @"a nested row's place is the names of its page and of itself, not their titles");

    // A word a row's title holds lands over the same word a row only its keywords hold.
    SGModPage *titled = pageOf(@"Titled", @[SGSearchKeywords(row(@"Island living", nil), @"carplay"),
                                           SGSearchKeywords(row(@"CarPlay", nil), @"island living")]);
    SGSettingsIndex *order = [SGSettingsIndex new];
    [order startWithRoot:titled];
    check([titles([order hitsForQuery:@"carplay"]) isEqual:(@[@"CarPlay", @"Island living"])], @"a title hit leads a keyword-only hit");
    check([titles([order hitsForQuery:@"island"]) isEqual:(@[@"Island living", @"CarPlay"])], @"and a keyword hit follows a title hit");

    // Width and diacritics fold away, and Korean initials still match.
    check([titles([ranked hitsForQuery:@"ＣＯＬＯＵＲ"]) isEqual:@[@"Accent color"]], @"a full-width query finds the row");
    check([titles([ranked hitsForQuery:@"colôur"]) isEqual:@[@"Accent color"]], @"a diacritic in the query still finds the row");
    check([titles([ranked hitsForQuery:@"ㅇㅍ"]) isEqual:@[]], @"Latin titles have no Korean initials to match");
    SGModPage *korean = pageOf(@"Korean", @[row(@"가사 설정", nil)]);
    SGSettingsIndex *initials = [SGSettingsIndex new];
    [initials startWithRoot:korean];
    check([titles([initials hitsForQuery:@"ㄱㅅ ㅅㅈ"]) isEqual:@[@"가사 설정"]], @"a Korean initial's query finds the row");
    check([titles([initials hitsForQuery:@"가사"]) isEqual:@[@"가사 설정"]], @"a Korean syllable finds the row");

    // A row that would not show is left out, and a switch that brings it in needs the pages read again.
    SGSettingsIndex *gated = started();
    while (gated.running) pass(gated);
    check([gated hitsForQuery:@"concealed"].count == 0, @"a row that would not show is not found");
    SGSetEnabled(kGate, YES);
    SGSettingsIndex *shown = started();
    while (shown.running) pass(shown);
    check([titles([shown hitsForQuery:@"concealed"]) isEqual:@[@"Concealed setting"]], @"a row the switch brings in is found");
    SGSetEnabled(kGate, NO);
    [NSUserDefaults.standardUserDefaults removeObjectForKey:kGate];

    // The cap: 60 rows found at most, the page's own rows first.
    NSMutableArray<SGModRow *> *many = [NSMutableArray array];
    NSMutableArray<SGModRow *> *under = [NSMutableArray array];
    for (int i = 0; i < 70; i++) [many addObject:row([NSString stringWithFormat:@"Match %02d", i], nil)];
    for (int i = 0; i < 70; i++) [under addObject:row([NSString stringWithFormat:@"Match under %02d", i], nil)];
    SGModPage *capped = [[SGModPage alloc] initWithTitle:@"Capped" intro:nil sections:@[
        SGSection(nil, many),
        SGSection(nil, @[pageRow(@"Under", ^UIViewController *{ return pageOf(@"Under", under); })]),
    ] footer:nil];
    SGSettingsIndex *cap = [SGSettingsIndex new];
    [cap startWithRoot:capped];
    while (cap.running) pass(cap);
    NSArray<SGSettingsHit *> *all = [cap hitsForQuery:@"match"];
    check(all.count == 60, @"60 rows are found at most");
    check([all.firstObject.title isEqual:@"Match 00"] && [all.lastObject.title isEqual:@"Match 59"], @"the cap keeps the first 60 the pages read");

    // What picking a hit opens: a row that opens a page opens that page, and a row of a page opens the page it sits
    // on. A choice row's list is not a page of rows, so the choice row itself is what is found.
    SGSettingsIndex *opening = started();
    while (opening.running) pass(opening);
    SGSettingsHit *pageHit = [opening hitsForQuery:@"live activity"].firstObject;
    check(pageHit.opens && pageHit.open != nil && [[pageHit.open() title] isEqualToString:@"Live Activity"],
          @"a row that opens a page is found as that page");
    NSArray<SGSettingsHit *> *rowHits = [opening hitsForQuery:@"artwork"];
    check(rowHits.count == 1 && !rowHits.firstObject.opens && rowHits.firstObject.open != nil &&
          [[rowHits.firstObject.open() title] isEqualToString:@"Live Activity"],
          @"a row of a page opens the page it sits on");

    // A build is stepped one page at a time, and the pass after each of them is asked for through the run loop, not
    // run here: one call builds one page, so the field and the page under it stay answerable between them.
    built = 0;
    SGSettingsIndex *paced = started();
    NSUInteger pacedGeneration = paced.generation;
    [paced stepScheduled:@(pacedGeneration)];
    check(built == 1, @"a pass asked for builds one page and leaves the rest to the run loop");
    [paced stepScheduled:@(pacedGeneration)];
    check(built == 2, @"the pass after it builds the page after that");
    // The paced build asked the run loop for a pass of its own; it is done with, so it is stopped before the run
    // loop below runs, or its pass would build a page there too.
    [paced stop];

    // The real run loop carries the build to the end: `scheduleStep` parks it on the main queue, and each pass asks
    // for the next one, so every page within reach is read and `running` goes false without anything else calling
    // `step`. A pass given its generation as an object is compared as one (a number read as a pointer would never
    // match, and the build would stop after the first page).
    built = 0;
    SGSettingsIndex *walked = started();
    [walked scheduleStep];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (walked.running && deadline.timeIntervalSinceNow > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
    check(!walked.running, @"the run loop reads every page and the build ends by itself");
    check(built == 4, [NSString stringWithFormat:@"the run loop built all four pages (%lu)", (unsigned long)built]);
    check([titles([walked hitsForQuery:@"deeper row"]) isEqual:@[@"Deeper row"]], @"a row of the second level down is found after the run loop's passes");
    check([titles([walked hitsForQuery:@"typeface"]) isEqual:@[@"Font"]], @"and so is a row of the first page under the page");

    // The index tells the results when its rows changed, so they show without waiting for the next keystroke: once per
    // pass that read a page, and once more when the last pass finds nothing left, so "No Results" can be put up. The
    // root's rows open three pages, and one of theirs opens a fourth.
    __block NSUInteger grew = 0;
    SGSettingsIndex *watched = started();
    watched.grew = ^{ grew++; };
    while (watched.running) pass(watched);
    check(grew == 5, [NSString stringWithFormat:@"the results are told once per pass that read a page, and once when the pages end (%lu)", (unsigned long)grew]);

    // A build that is stopped is not continued by a pass already asked for.
    built = 0;
    SGSettingsIndex *stopped = started();
    pass(stopped);
    NSUInteger generation = stopped.generation;
    [stopped stop];
    [stopped stepScheduled:@(generation)];
    check(built == 1, @"a pass of a stopped build builds nothing");
    check([stopped hitsForQuery:@"plain"].count == 0, @"a stopped build keeps no rows");

    // A second build over the same index counts the generation up, so the first build's pass leaves it alone.
    [stopped startWithRoot:rootPage()];
    check(stopped.generation > generation, @"a new build counts the generation up");
    [stopped stepScheduled:@(generation)];
    check(built == 1, @"the old build's pass leaves the new one alone");

    // Recents: the newest first, once each, six at most. A place is the setting names the results led through, not
    // the titles on screen.
    SGSearchForgetRecents();
    check(SGSearchRecents().count == 0, @"nothing is stored to begin with");
    NSArray<NSString *> *art = @[@"row.Live Activity", @"row.Artwork"];
    NSArray<NSString *> *accentPlace = @[@"row.Appearance", @"row.Accent color"];
    SGSearchRememberPlace(art);
    SGSearchRememberPlace(accentPlace);
    check([SGSearchRecents() isEqualToArray:@[accentPlace, art]], @"a place opened after another comes first");
    SGSearchRememberPlace(art);
    check([SGSearchRecents() isEqualToArray:@[art, accentPlace]], @"a place opened again moves to the front, once");
    for (int i = 0; i < 8; i++) SGSearchRememberPlace(@[[NSString stringWithFormat:@"Place %d", i]]);
    check(SGSearchRecents().count == 6, @"six places are kept at most");
    check([[NSUserDefaults.standardUserDefaults arrayForKey:SGKeySearchRecents] count] == 6, @"six places are stored at most");
    check([SGSearchRecents().firstObject isEqualToArray:@[@"Place 7"]], @"the newest place leads and the oldest goes");
    SGSearchRememberPlace(@[]);
    SGSearchRememberPlace(@[@"Place 7", @""]);
    SGSearchRememberPlace(nil);
    check(SGSearchRecents().count == 6 && [SGSearchRecents().firstObject isEqualToArray:@[@"Place 7"]],
          @"a place that is not a list of names is not stored");

    // A place the current look no longer has is left out of what the index shows.
    SGSearchForgetRecents();
    SGSearchRememberPlace(@[@"row.Search"]);
    SGSearchRememberPlace(art);
    SGSettingsIndex *recents = started();
    while (recents.running) pass(recents);
    check([titles([recents recentHits]) isEqual:@[@"Artwork"]], @"a place the current look does not have is skipped");

    // What is stored is setting names, never a title and never what was typed.
    NSArray *stored = [NSUserDefaults.standardUserDefaults arrayForKey:SGKeySearchRecents];
    BOOL onlyPlaces = YES;
    for (id entry in stored) for (id name in entry) onlyPlaces = onlyPlaces && [name isKindOfClass:NSString.class];
    check(onlyPlaces && [stored containsObject:art], @"what is stored is the names of the settings the results led to");
    check(![stored containsObject:@[@"Live Activity", @"Artwork"]], @"no title is stored in a place");

    // The places are read from the defaults each time, not kept in memory, so what one run stored the next one reads
    // and what Clear removes stays removed.
    SGSearchForgetRecents();
    [NSUserDefaults.standardUserDefaults setObject:@[@[@"Written elsewhere", @"Row"]] forKey:SGKeySearchRecents];
    check([SGSearchRecents() isEqualToArray:@[@[@"Written elsewhere", @"Row"]]], @"a place written outside the search is read back");
    SGSearchForgetRecents();
    check([NSUserDefaults.standardUserDefaults arrayForKey:SGKeySearchRecents] == nil && SGSearchRecents().count == 0,
          @"Clear removes the stored places, not just what is shown");

    // A look switch: two rows of one title, each remembered in the look it belongs to, and the places never cross
    // looks even though the title is the same, so opening one look's setting never leads to the other look's.
    SGModPage *(^lookPage)(NSString *look) = ^SGModPage *(NSString *look) {
        SGModRow *accent = row(@"Accent color", nil);
        accent.searchIdentifier = [NSString stringWithFormat:@"row.%@.accentcolor", look];
        SGModRow *appearance = pageRow(@"Appearance", ^UIViewController *{ return nil; });
        appearance.searchIdentifier = [NSString stringWithFormat:@"row.%@.appearance", look];
        return pageOf(@"Look", @[accent, appearance]);
    };
    SGModPage *nativeLook = lookPage(@"appearance.native");
    SGModPage *redesignedLook = lookPage(@"appearance.redesigned");

    SGSearchForgetRecents();
    SGSettingsIndex *nativeIndex = [SGSettingsIndex new];
    [nativeIndex startWithRoot:nativeLook];
    while (nativeIndex.running) pass(nativeIndex);
    SGSettingsHit *nativeAccent = [nativeIndex hitsForQuery:@"accent color"].firstObject;
    check([nativeAccent.place isEqualToArray:@[@"row.appearance.native.accentcolor"]], @"the native look's setting is named the native look's");
    SGSearchRememberPlace(nativeAccent.place);
    // The look switches: the same titles are there, and the design's rows are named the design's.
    SGSettingsIndex *redesignedIndex = [SGSettingsIndex new];
    [redesignedIndex startWithRoot:redesignedLook];
    while (redesignedIndex.running) pass(redesignedIndex);
    check([redesignedIndex recentHits].count == 0, @"after a look switch the other look's place leads nowhere");
    SGSettingsHit *redesignedAccent = [redesignedIndex hitsForQuery:@"accent color"].firstObject;
    check([redesignedAccent.place isEqualToArray:@[@"row.appearance.redesigned.accentcolor"]] &&
          ![redesignedAccent.place isEqualToArray:nativeAccent.place],
          @"the redesign's setting of the same title is a place of its own");

    // A look that changes under one page that stays open (Redesigned UI flipped, restart put off): the rows are named
    // again by the page's own block each time the index starts, so a place made after the flip is the new look's and
    // a recent of the old look leads nowhere.
    __block NSString *storedLook = @"native";
    SGModRow *lookedRow = pageRow(@"Home", ^UIViewController *{ return pageOf(@"Home", @[row(@"Gradient", nil)]); });
    SGModPage *openRoot = pageOf(@"Retrine", @[lookedRow]);
    SGSettingsIndexRenamesWith(openRoot, ^{ lookedRow.searchIdentifier = [@"page.home." stringByAppendingString:storedLook]; });
    SGSearchForgetRecents();
    SGSettingsIndex *beforeFlip = [SGSettingsIndex new];
    [beforeFlip startWithRoot:openRoot];
    while (beforeFlip.running) pass(beforeFlip);
    SGSettingsHit *homeBefore = [beforeFlip hitsForQuery:@"home"].firstObject;
    check([homeBefore.place isEqualToArray:@[@"page.home.native"]], @"the page row is named for the look stored when the index starts");
    SGSearchRememberPlace(homeBefore.place);
    storedLook = @"redesigned";
    SGSettingsIndex *afterFlip = [SGSettingsIndex new];
    [afterFlip startWithRoot:openRoot];
    while (afterFlip.running) pass(afterFlip);
    SGSettingsHit *homeAfter = [afterFlip hitsForQuery:@"home"].firstObject;
    check([homeAfter.place isEqualToArray:@[@"page.home.redesigned"]], @"after the stored look changes the same page row is named for the new look");
    check([[afterFlip hitsForQuery:@"gradient"].firstObject.place isEqualToArray:(@[@"page.home.redesigned", @"row.Gradient"])],
          @"and so are the rows under it");
    check([afterFlip recentHits].count == 0, @"a recent of the other look does not open this look's page");
    SGSearchRememberPlace(homeAfter.place);
    check([afterFlip recentHits].count == 1 && [afterFlip recentHits].firstObject == homeAfter, @"a recent of this look opens it");

    // A language switch: the titles are translated, and the stored place still finds its row, because it holds names.
    SGModPage *translated = pageOf(@"외관", @[row(@"강조 색", nil)]);
    translated.sections[0].rows[0].searchIdentifier = @"row.appearance.native.accentcolor";
    SGSearchForgetRecents();
    SGSearchRememberPlace(nativeAccent.place);
    SGSettingsIndex *koreanIndex = [SGSettingsIndex new];
    [koreanIndex startWithRoot:translated];
    while (koreanIndex.running) pass(koreanIndex);
    check([titles([koreanIndex recentHits]) isEqual:@[@"강조 색"]], @"after a language switch the place finds the translated row");

    // A title two pages share: each row's own name tells them apart, so a recent opens the one it was.
    SGModRow *first = row(@"Volume", nil);
    first.searchIdentifier = @"row.a.volume";
    SGModRow *second = row(@"Volume", nil);
    second.searchIdentifier = @"row.b.volume";
    SGModPage *twins = [[SGModPage alloc] initWithTitle:@"Twins" intro:nil sections:@[
        SGSection(nil, @[first]),
        SGSection(nil, @[pageRow(@"Other", ^UIViewController *{ return pageOf(@"Other", @[second]); })]),
    ] footer:nil];
    SGSettingsIndex *twin = [SGSettingsIndex new];
    [twin startWithRoot:twins];
    while (twin.running) pass(twin);
    NSArray<SGSettingsHit *> *volumes = [twin hitsForQuery:@"volume"];
    check(volumes.count == 2, @"two rows of one title are both found");
    check(![volumes[0].place isEqualToArray:volumes[1].place], @"their places tell them apart");
    checkEveryHitIsUnique(volumes, @"two rows of one title");
    SGSearchForgetRecents();
    SGSearchRememberPlace(volumes[1].place);
    check([twin recentHits].count == 1 && [twin recentHits].firstObject == volumes[1],
          @"a place of one of two rows of a title finds that row, not the other");

    // A row the search cannot name is not remembered at all, and neither is a row under a page row it cannot name:
    // a place that guessed would open the wrong page after a change.
    SGModRow *anonymous = [SGModRow new];
    anonymous.title = @"Unnamed action";
    SGModRow *namelessPageRow = pageRow(@"Unnamed page", ^UIViewController *{ return pageOf(@"Under", @[row(@"Named row", nil)]); });
    namelessPageRow.searchIdentifier = nil;   // a page row has to be given one; take it away again
    SGModPage *unnamed = [[SGModPage alloc] initWithTitle:@"Unnamed" intro:nil sections:@[
        SGSection(nil, @[anonymous]),
        SGSection(nil, @[namelessPageRow]),
    ] footer:nil];
    SGSettingsIndex *nameless = [SGSettingsIndex new];
    [nameless startWithRoot:unnamed];
    while (nameless.running) pass(nameless);
    SGSettingsHit *unnamedHit = [nameless hitsForQuery:@"unnamed action"].firstObject;
    check(unnamedHit && unnamedHit.place == nil, @"a row with no name has no place");
    NSArray<SGSettingsHit *> *beneath = [nameless hitsForQuery:@"named row"];
    check(beneath.count == 1 && beneath.firstObject.place == nil, @"a row under a page row with no name has no place either");

    // A switch row is named by its key without being told one.
    SGModRow *switchRow = SGSwitchRow(@"Some switch", nil, @"spotifyglass.harness.someswitch");
    SGModPage *keyed = pageOf(@"Keyed", @[switchRow]);
    SGSettingsIndex *keyedIndex = [SGSettingsIndex new];
    [keyedIndex startWithRoot:keyed];
    SGSettingsHit *switchHit = [keyedIndex hitsForQuery:@"some switch"].firstObject;
    check([switchHit.place isEqual:@[@"spotifyglass.harness.someswitch"]],
          @"a switch row is remembered under the key it stores");

    printf("settings search: %lu/%lu passed\n", (unsigned long)(checks - failures), (unsigned long)checks);
    exit(failures ? 1 : 0);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        check([SGSearchInitials(@"번역") isEqual:@"ㅂㅇ"], @"syllable initials");
        check([SGSearchInitials(@"가사 설정") isEqual:@"ㄱㅅ ㅅㅈ"], @"initials retain spaces");
        check([SGSearchInitials(@"Font 번역") isEqual:@"font ㅂㅇ"], @"Latin folds around initials");
        check(SGSearchWordMatches(@"ㅂㅇ", @"번역", @"ㅂㅇ"), @"initials match");
        check(!SGSearchWordMatches(@"ㅂㅇ", @"가사 설정", @"ㄱㅅ ㅅㅈ"), @"different initials miss");
        check([SGSearchInitials(@"꿀") isEqual:@"ㄲ"], @"double consonant");
        check(SGSearchWordMatches(@"ㄲ", @"꿀", @"ㄲ"), @"double consonant matches");
        check(!SGSearchWordMatches(@"ㄱ", @"꿀", @"ㄲ"), @"single consonant does not match double");
        check(SGSearchWordMatches(@"ㄱㅅ", @"가사 font", @"ㄱㅅ font") &&
              SGSearchWordMatches(@"font", @"가사 font", @"ㄱㅅ font"), @"mixed query");
        check(!SGSearchWordMatches(@"ㄱㅅ", @"가사 font", @"가사 font"), @"initials do not read plain text");
        check(!SGSearchIsInitialsWord(@"font"), @"Latin query is not initials");
        check(!SGSearchStartsTitle(@"font", @"번역", @"ㅂㅇ"), @"unrelated Latin prefix misses");
        check(!SGSearchIsInitialsWord(@"ㅏ"), @"vowel is not an initial");
        check(SGSearchWordMatches(@"ㅏ", @"ㅏ", SGSearchInitials(@"ㅏ")), @"vowel matches literal text");
        check(SGSearchStartsTitle(@"ㅂㅇ", @"번역", @"ㅂㅇ"), @"initial title prefix");
        check(SGSearchStartsTitle(@"ㄱㅅ ㅅㅈ", @"가사 설정", @"ㄱㅅ ㅅㅈ"), @"spaced initial title prefix");
        check(SGSearchStartsTitle(@"번", @"번역", @"ㅂㅇ"), @"plain title prefix");
        check(!SGSearchStartsTitle(@"ㅂㅇ", @"가사 설정", @"ㄱㅅ ㅅㅈ"), @"unrelated initial prefix misses");
        // UIKit is only linked for FGModPage's own types; nothing here draws.
        runChecks();
    }
    return 0;
}

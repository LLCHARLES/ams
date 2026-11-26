// What Mod Settings' search reads and matches, apart from the field and its table (SGSettingsSearch.m): the rows of
// the searched page and of the pages its rows open, three pages deep, read a page at a time, and the words a row is
// found by. Threading: main thread only, like the pages it builds.
#import "SGModPage.h"

// Custom tables expose just their navigable destinations, without loading the table's view.
@protocol SGSettingsSearchPages <NSObject>
- (NSArray<SGModRow *> *)sg_searchPageRows;
@end

#pragma mark - matching

// The text folded for comparison: case, diacritics and width alike, so "café", "CAFE" and "ＣＡＦＥ" are one word.
NSString *SGSearchFold(NSString *text);
// Each precomposed syllable becomes its initial consonant; the rest is the folded text.
NSString *SGSearchInitials(NSString *text);
// A word of only the 19 compatibility consonants a syllable can start with, so it is compared to initials.
BOOL SGSearchIsInitialsWord(NSString *word);
BOOL SGSearchWordMatches(NSString *word, NSString *folded, NSString *initials);
BOOL SGSearchStartsTitle(NSString *query, NSString *foldedTitle, NSString *initialsTitle);

#pragma mark - the settings opened before

// A place is an array of the setting names the results led through, the searched page's row's first and the row's
// last: each a row's own SGModRow.searchIdentifier or its key, never a title (those are translated) and never the
// text typed. A look's own setting names its look in it, so the native and the redesign's settings of one name are
// two places. A place with a page row in it that has no name is not stored at all.
#define SGKeySearchRecents @"spotifyglass.search.recents"
NSArray<NSArray<NSString *> *> *SGSearchRecents(void);
void SGSearchForgetRecents(void);

// A page whose rows are named by something that can change while the page stays open (the stored look) gives the
// search the block that names them again; every start of the index runs it before reading the page, so a place is
// always made of the names the rows have now.
void SGSettingsIndexRenamesWith(SGModPage *page, void (^rename)(void));
// Resolve moved trails by identifier, both on lookup and when the next selection saves recents.
void SGSettingsIndexMovesWith(SGModPage *page, NSArray *(^resolve)(NSArray *));

#pragma mark - a row the search finds

@interface SGSettingsHit : NSObject
@property (nonatomic, readonly, copy) NSString *title, *subtitle;
@property (nonatomic, readonly, copy) NSArray<NSString *> *trail;   // the pages above the row, the searched page's row first
// The names of the trail's pages and of the row, which is what a recent destination is stored as; nil when one of
// them has no name, and then the row is not remembered.
@property (nonatomic, readonly, copy) NSArray<NSString *> *place;
@property (nonatomic, readonly, copy) NSString *symbol;             // the tile of the searched page's row the trail starts from
@property (nonatomic, readonly, strong) UIColor *tint;
// What picking it opens: the page the row sits on (nil for a row of the searched page itself), or the row's own
// page when `opens`.
@property (nonatomic, readonly, copy) UIViewController *(^open)(void);
@property (nonatomic, readonly) BOOL opens;
@end

#pragma mark - the pages read so far

@interface SGSettingsIndex : NSObject
// Reads the page itself now, and lines up the pages its rows open.
- (void)startWithRoot:(SGModPage *)root;
// Builds and reads the next page in line, then asks for the pass after it at once; NO when none is left.
- (BOOL)step;
@property (nonatomic, readonly) BOOL running;   // started, and pages are still to be read
// Runs after each pass that read a page, so the rows just read are shown.
@property (nonatomic, copy) void (^grew)(void);
// Nothing more is built, and the steps of the build before this call do nothing. Counts up on every start and stop.
- (void)stop;
@property (nonatomic, readonly) NSUInteger generation;
// The pass the run loop is asked for, of the build the receiver was in: `generation` is the number scheduleStep
// carried, so a pass of a build the index left builds nothing.
- (void)stepScheduled:(NSNumber *)generation;
// Asks the run loop for the first pass, which asks for the next one after it until the pages are read.
- (void)scheduleStep;
// The rows read so far whose title, subtitle, keywords or trail hold every word of `query`: the best 60, a title
// starting with it first, then a title holding it, then the rest, each in the order of the pages. The query is the
// text as typed; it is folded here, so width, diacritics and case do not tell two words apart.
- (NSArray<SGSettingsHit *> *)hitsForQuery:(NSString *)query;
// The stored places the rows read so far hold, in the stored order, at most six.
- (NSArray<SGSettingsHit *> *)recentHits;
- (void)rememberPlace:(NSArray<NSString *> *)place;
@end

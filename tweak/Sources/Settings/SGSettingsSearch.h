// Mod Settings' search: a field heading the page finds rows by their title, subtitle, the names of the pages they
// sit on and the words their owner adds (SGModRow.searchKeywords), on the page and on the pages its rows open, two
// pages deep, the way Settings' own search finds its rows. The pages are read a page at a time on the main run
// loop (SGSettingsIndex.h), so what the pages read so far hold shows at once and the rest joins it. Picking a row
// opens the page it is on, scrolled to it and lit for a moment; picking a row that opens a page opens that page. An
// empty field shows the settings opened from the results before (SGSearchRecents), never what was typed.
#import "SGModPage.h"

void SGSettingsSearchAttach(SGModPage *page);
// The field the page heads itself with, nil before the page loads; the search's own tests take it up.
UISearchController *SGSettingsSearchField(SGModPage *page);

// The places of the settings opened from the results before, newest first, at most six: each an array of the row
// titles from the searched page's row down to the row. Query text is never stored.
#define SGKeySearchRecents @"spotifyglass.search.recents"
NSArray<NSArray<NSString *> *> *SGSearchRecents(void);
void SGSearchForgetRecents(void);

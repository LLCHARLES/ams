// The Library redesign: Spotify's Your Library kept, with its controllers, its list and its rows, decluttered
// to a library on black and restyled from the Kit.
//
//     LibraryHeader.x   the header the way Home and Search have theirs: a large title at the leading edge, the
//                       avatar at the trailing edge, Spotify's filter chips kept under the row. A folder opened
//                       from the library is the same header, its back button, its own controls and its chips
//                       kept. With Compact library on, the root's chips go and the header closes up by what they
//                       leave, while the header's menu (LibraryMenu.m) can reach what they and the list's sort
//                       row offered
//     LibraryMenu.m     Compact library's menu: Spotify's own sort, list or grid and clear-filter controls,
//                       found live and fired the way a tap fires them
//     LibraryRows.x     every row and grid card: the artwork at the Kit's radius with continuous corners, a
//                       circular one left round, and a hairline between the rows
//     LibrarySearch.x   the search inside the library: its field a glass capsule, the way the Search tab's is
//                       (Redesigned/Navbar/SearchField.x)
//     LibrarySettings.m the Library page of Mod Settings, led by a preview of the page
//
// Every hook installs only while Redesigned UI is on (SGRedesignedUI).
// Threading: main thread only.
#import <UIKit/UIKit.h>

// Compact library: the root's filter chips hidden and the header's menu in their place. Off unless set; read at
// launch.
#define SGRKeyLibraryHideChips @"spotifyglass.redesign.library.hideChips"
BOOL SGRLibraryCompact(void);

@class SGRPagePreview, SGModSection;
SGRPagePreview *SGRLibraryPreview(void);
SGModSection *SGRLibrarySection(void);

// LibraryMenu.m. The menu button the root header shows while Compact library is on, made once per header and
// kept on it; LibraryHeader.x places it. Its menu is built as it opens, from the library page the header is in then
// (SGRLibraryPageAbove), whatever stands between them (9.2.0's stack).
UIButton *SGRLibraryMenuButton(UIView *header);
// What the menu offers on `page` as it opens, in order: Sort, with the order the sort row shows under it while the
// row is on screen; the list and grid views, the current one checked (Spotify's own toggle under its own name when
// the current one cannot be told); and Clear filter while a filter is on. Each fires Spotify's own control: in place
// while it is on screen, else once the list, taken to its top, has brought it back. The page lays out first, so the
// chips come back at once when the menu can no longer stand in for them. Empty while the page has none of them.
NSArray<UIMenuElement *> *SGRLibraryMenuElements(UIView *page);
// Whether the menu can stand in for the root's chips on `page` now, `filters` being Spotify's chips
// (YourLibraryHeaderContentFiltersView): the chips are the collection the menu reads, the page's sort and view
// controls have been seen, a filter that is on has Spotify's clear chip to clear it, and nothing the menu fired on
// the page has failed.
BOOL SGRLibraryMenuStandsIn(UIView *page, UIView *filters);
// LibraryMenu.m, after every layoutSubviews of a collection view while Compact library is on. The root's chips have
// the page look again when whether a filter of theirs can be cleared changes; the list fires what the menu left for
// it once it is back at its top. Any other collection view is passed over at the cost of a lookup.
void SGRLibraryCollectionLaidOut(UICollectionView *view);

// LibraryHeader.x. The scrim Spotify lays behind a library header taken out, so the soft scroll edge
// (Kit/SGREdgeEffect.x) is what keeps the header clear of the list under it. A header without one is left
// alone; the folder's has none.
void SGRLibraryClearScrim(UIView *header);
// LibraryHeader.x. The root page's header (YourLibraryHeaderView): a child of `page` through 9.1.90, the child of a
// plain UIStackView child of it from 9.2.0. nil while the page has none.
UIView *SGRLibraryRootHeaderIn(UIView *page);
// LibraryHeader.x. The root page's list (YourLibraryContent.collectionView), nil until it is there.
UIScrollView *SGRLibraryListIn(UIView *page);
// LibraryHeader.x. The root page `view` is in, nil outside one.
UIView *SGRLibraryPageAbove(UIView *view);

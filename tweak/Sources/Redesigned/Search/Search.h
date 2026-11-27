// The Search redesign: Spotify's Browse page (the Search tab before anything is typed) kept, with its controllers,
// list and cards, decluttered to the categories on black and restyled from the Kit. The glass search field is the
// Navbar part's (Redesigned/Navbar/SearchField.x).
//
//     SearchSections.x  an allow list of the page's cells: the category cards stay; the watch feed carousels
//                       (Playlists you can watch, Explore episodes for you), promos and any new kind collapse, and the
//                       cards below move up by the spacing the collapsed ones leave
//     SearchPage.x      the header the way Home has it: a large title, the avatar at the trailing edge, no camera, no
//                       scrim; and the page's layout pass, which measures that spacing
//     SearchCards.x     each category card as Liquid Glass tinted by its own color, at the card radius, giving under a press
//     SearchSettings.m  the redesign's Search page, a switch for each of the three below
//
// Every hook installs only while Redesigned UI is on (SGRedesignedUI).
// Threading: main thread only.
#import <UIKit/UIKit.h>

// Read at launch, each on until switched off (SearchSettings.m). SearchSections.x: the watch feed carousels collapse,
// and every other kind but the category cards (promos, showcases, anything new) does.
#define SGRKeySearchHideWatchFeeds @"spotifyglass.redesign.search.hide.watchFeeds"
#define SGRKeySearchHideOther @"spotifyglass.redesign.search.hide.other"
// SearchCards.x: the category cards on tinted glass; off, they are Spotify's own.
#define SGRKeySearchGlassCards @"spotifyglass.redesign.search.glassCards"
@class SGRPagePreview, SGModSection;
SGRPagePreview *SGRSearchPreview(void);
NSArray<SGModSection *> *SGRSearchSections(void);

// The page's list (trees/clean/search/01.txt:24).
extern NSString *const SGRSearchListIdentifier;

// SearchSections.x: measures how far the cards sit below the top of the list because of the sections collapsed above
// them, and moves every cell of the list up by that much and the end of its content with them. Cheap to call on every
// layout pass of the page.
void SGRSearchCloseGap(UICollectionView *list);

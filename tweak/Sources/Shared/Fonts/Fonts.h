// One font for the whole app (Fonts.x), chosen on the Appearance page under either look, and a font file
// of the user's own as one of the choices (FontImport.m).
#import <UIKit/UIKit.h>

#define SGKeyAppFont @"spotifyglass.font"
// The imported family: its files' names in Application Support/Retrine/Font, and the family name read from them.
// SGKeyAppFontFile is the single file of an import from before families, moved to the list on first use.
#define SGKeyAppFontFiles @"spotifyglass.font.files"
#define SGKeyAppFontName @"spotifyglass.font.name"
#define SGKeyAppFontFile @"spotifyglass.font.file"
// The family chosen under More fonts, by its name ("Avenir Next").
#define SGKeyAppFontFamily @"spotifyglass.font.family"
// The free family chosen, by its identifier in FontLibrary.h's catalog ("nanumgothic").
#define SGKeyAppFontLibrary @"spotifyglass.font.library"

typedef NS_ENUM(NSInteger, SGAppFont) {
    SGAppFontSpotify,   // Spotify's own, untouched
    SGAppFontSystem,    // San Francisco
    SGAppFontRounded,   // SF Rounded
    SGAppFontSerif,     // New York
    SGAppFontMono,      // SF Mono
    SGAppFontCustom,    // the family imported from Files
    SGAppFontFamily,    // a family iOS carries, named by SGKeyAppFontFamily
    SGAppFontLibrary,   // a free family downloaded from FontLibrary.h's catalog, named by SGKeyAppFontLibrary
};

// The stored choice; with none, Spotify's font in the native look and San Francisco in the redesign (SGRedesignedUI).
// A font that goes away (FontImport.m, FontLibrary.m) removes the stored choice, so that default applies again.
SGAppFont SGAppFontChosen(void);
// The font the app draws in for this launch (Fonts.x reads the choice once): the choice, or Spotify's when a family it
// names was not there. Text the mod sets in the system font is drawn in it, except when this is Spotify's.
SGAppFont SGAppFontDrawn(void);
NSArray<NSString *> *SGAppFontNames(void);   // the five built in, by SGAppFont
NSArray<NSString *> *SGAppFontFamilies(void);   // More fonts: the families this iPhone has of a fixed few
// Main-thread async font choices: raw enum/family/library values, including absence. Completion may
// auto-select only if this snapshot is unchanged and no process restart has been requested.
NSArray *SGFontSelectionSnapshot(void);
BOOL SGFontSelectionUnchanged(NSArray *snapshot);
// Registers the imported files with Core Text for this process and answers the family name, or nil when no
// file is left or Core Text will not take them, and publishes it for SGRegisteredCustomFont. It waits for Core
// Text, so it is for the main thread's launch path (Fonts.x) and an import's own commit; anything that is
// drawn while the person waits uses SGRegisterCustomFontAsync.
NSString *SGRegisterCustomFont(void);
// What SGRegisterCustomFont answered, or SGRegisterCustomFontAsync once it has landed, for the family now
// imported; nil until then and when the import is gone. Main thread. Reads no file and registers nothing.
NSString *SGRegisteredCustomFont(void);
// SGRegisterCustomFont on a queue of its own (one registration at a time). Returns at once, and does nothing
// when SGRegisteredCustomFont has the family already; else on the main thread it publishes the name and, when it
// is new, posts SGFontLibraryChangedNotification (FontLibrary.h) for @"custom".
void SGRegisterCustomFontAsync(void);
// The family name the faces share, or nil when they differ, one has none, or there are none.
NSString *SGFontSingleFamily(NSArray<NSString *> *names);

@class SGModRow;
NSArray<SGModRow *> *SGAppFontRows(void);   // the Font row, opening the page of choices
// The free families to download (FontLibraryPage.m), for Workshop and the Font page.
UIViewController *SGFontLibraryPage(void);

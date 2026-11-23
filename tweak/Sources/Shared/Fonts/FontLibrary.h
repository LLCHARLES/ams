// Free fonts to download (FontLibrary.m): families under the SIL Open Font License, from Google Fonts' own
// repository (github.com/google/fonts) pinned to one commit, so a file is the one this build was made with. Each
// file is checked against its size and SHA-256 before it is kept, and the family's OFL.txt is kept beside it.
// A downloaded family lives in Application Support/Retrine/Font Library/<identifier>/ and is one of the app
// font's choices (SGAppFontLibrary, Fonts.h); Fonts.x registers its files again at each launch.
//
// Main thread, except where a function says otherwise.
#import <Foundation/Foundation.h>

// Posted on the main thread when a download moves on, ends, or a family is removed, and when the imported
// family (Fonts.h) becomes registered (identifier @"custom"). userInfo: @"identifier".
#define SGFontLibraryChangedNotification @"SGFontLibraryChangedNotification"

@interface SGLibraryFont : NSObject
@property (nonatomic, readonly, copy) NSString *identifier;   // Google Fonts' folder name: "nanumgothic"
@property (nonatomic, readonly, copy) NSString *name;         // the name shown: "Nanum Gothic"
@property (nonatomic, readonly) BOOL korean;                  // it has Hangul
@property (nonatomic, readonly) NSUInteger styles;            // how many files, one per weight
@property (nonatomic, readonly) long long bytes;              // the files together
@property (nonatomic, readonly, copy) NSURL *licenseURL;      // its OFL.txt on GitHub, at the pinned commit
@end

// The catalog: Korean families first, then the others, each list in the order it is shown.
NSArray<SGLibraryFont *> *SGFontLibrary(void);
SGLibraryFont *SGFontLibraryFont(NSString *identifier);

// Every file of the family is in its folder at its catalog size.
BOOL SGFontLibraryInstalled(NSString *identifier);
// Registers the installed family's files with Core Text for this process and answers the family name the files
// carry, or nil when the family is not installed or Core Text takes none of it. Calling it again is harmless.
// It waits for the registration queue, so it is for the launch path (Fonts.x), which needs the family before
// any hook runs; a page uses SGFontLibraryRegisterAsync.
NSString *SGFontLibraryRegister(NSString *identifier);
// What SGFontLibraryRegister answered, published on the main thread by it or by SGFontLibraryRegisterInstalled;
// nil until then. Reads nothing from disk and registers nothing, so a page can ask on every row.
NSString *SGFontLibraryRegisteredFamily(NSString *identifier);
// Registers the family on a queue of its own (the same one SGFontLibraryRegister and SGFontLibraryRemove run
// on), then on the main thread publishes its name, posts the change notification for it when the name is new,
// and runs `done` (may be nil) with the family name, or nil when the family is not installed (any more) or Core
// Text takes none of it. Returns at once; nothing registers on the calling thread.
void SGFontLibraryRegisterAsync(NSString *identifier, void (^done)(NSString *family));
// SGFontLibraryRegisterAsync for every family in the catalog.
void SGFontLibraryRegisterInstalled(void);

// One family downloads at a time. While it does, SGFontLibraryDownloading names it and SGFontLibraryProgress
// reads 0...1; the notification above is posted as it moves on (at most every tenth of a second) and once
// when it ends. `done` runs once on the main queue: nil when every file arrived and checked out, an empty string
// when it was cancelled, else why not, in the person's language. Nothing is kept from a download that fails or is
// cancelled. Starting one while another runs answers at once with why not.
NSString *SGFontLibraryDownloading(void);
double SGFontLibraryProgress(void);
void SGFontLibraryDownload(NSString *identifier, void (^done)(NSString *error));
void SGFontLibraryCancel(void);
// Unregisters and deletes the family's files. When it was the app's font, Spotify's comes back.
void SGFontLibraryRemove(NSString *identifier);

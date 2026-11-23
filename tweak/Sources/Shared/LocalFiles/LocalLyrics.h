// Imported lyrics files: the user's own lyrics for any song, under either look. What a file holds is
// decided by its content rather than its extension: a TTML document with timed lines, else LRC stamped
// lines, else one untimed line after another. Kept in Documents/Retrine/Lyrics as UTF-8, by the name it
// came with under the extension of what it holds. A file is linked to the song's URI ("Import for
// current track"), and that file is the track's whatever its tags say; an unlinked local track is matched against
// every file by title and artist, folded (case, diacritics, width and everything but letters and digits
// ignored). Lyrics pasted from the clipboard are kept as a plain text file and linked the same way.
//
//     LocalLyrics.m       the files, the links, each kind read into lines and the match
//     LocalLyricsPage.m   the Imported lyrics files page on the Lyrics page
//
// The lyrics engine asks for a local file's imported lines before any source (Shared/Lyrics/KaraokeSource.x).
#import <UIKit/UIKit.h>
#import "Shared/LyricsSources/LyricsSources.h"

// Song URI -> the name of the file linked to it.
#define SGKeyImportedLRCLinks @"spotifyglass.localFiles.lrcLinks"
// The names of the files an import replaced, which a launch may remove: see SGRetireImportedLyrics.
#define SGKeyRetiredImportedLyrics @"spotifyglass.localFiles.retiredLyrics"

// Why data could not be imported, as the code of an SGLyricsImportErrorDomain error.
typedef NS_ENUM(NSInteger, SGLyricsImportError) {
    SGLyricsImportErrorNothing = 1,       // no data at all, or a paste with nothing in it
    SGLyricsImportErrorTooLarge,          // more than 1 MB of encoded text
    SGLyricsImportErrorUnreadable,        // not text this reads (UTF-8, or UTF-16 with a BOM), or no line it could show
    SGLyricsImportErrorUnreadableFile,    // the picked file itself could not be read
    SGLyricsImportErrorStorage,           // the new lyrics could not be written; the old ones are still there
    SGLyricsImportErrorType,
};
extern NSString *const SGLyricsImportErrorDomain;
enum { SGLyricsImportMaxBytes = 1048576 };
// Bound the sheet after refrain expansion, before allocating line/word timing objects.
enum { SGFileLyricsMaxLines = 4096, SGFileLyricsMaxCharacters = 128 * 1024 };

// What a lyrics file holds, decided by its content: a TTML document, LRC, or plain text.
typedef NS_ENUM(NSInteger, SGLyricsImportKind) {
    SGLyricsImportKindTTML = 0,
    SGLyricsImportKindLRC,
    SGLyricsImportKindText,
};

// Data or text read as lyrics: its kind, the lines it gave and the text to keep.
@interface SGImportedLyrics : NSObject
@property (nonatomic, readonly) SGLyricsImportKind kind;
@property (nonatomic, readonly, copy) NSString *title, *artist;   // [ti:] and [ar:], nil without them
@property (nonatomic, readonly, copy) NSString *text;            // as it was read, kept as UTF-8
@property (nonatomic, readonly, copy) NSArray<SGKaraokeLine *> *lines;
@property (nonatomic, readonly, copy) NSArray<NSNumber *> *starts;   // as Spotify's own page takes them
@property (nonatomic, readonly, copy) NSArray<NSString *> *texts;
@property (nonatomic, readonly) BOOL synced;
@end

// A file's or a paste's data as lyrics, nil and an SGLyricsImportErrorDomain error for data with nothing
// in it, more than 1 MB of it, no text this reads (UTF-8, or UTF-16 with a BOM), or no line at all. A
// document that looks like TTML or LRC but gives no line is read as plain text, and only then refused.
// Safe from any thread.
SGImportedLyrics *SGImportedLyricsFromData(NSData *data, NSError **error);
// The same for text already decoded. Safe from any thread.
SGImportedLyrics *SGImportedLyricsFromText(NSString *text, NSError **error);

// The source's key in the lyrics sources order, and its ask: it needs no name, since a linked file is
// found by the track's URI. The order moves it to the top at the first import and at every link, once
// LyricsSources lists a provider by this key.
extern NSString *const SGImportedLRCKey;
extern SGLyricsAsk SGImportedLRCAsk;

// The imported files' names, sorted. Safe from any thread.
NSArray<NSString *> *SGImportedLRCFiles(void);
// Copies a lyrics file in, whatever kind its content is (see SGImportedLyricsFromData for what is
// refused, with an error to show), linked to `uri` when supplied, and kept under the
// extension of what it holds. The name it is kept under, nil on a refusal. Reads at most 1 MB + 1 off
// main. Entry and completion on main; completion gives the name or error.
void SGImportLRC(NSURL *url, NSString *uri, void (^completion)(NSString *name, NSError *error));
// The same for lyrics pasted in full, with the same validation, under the extension of what the paste
// turned out to hold (a plain text paste as "Pasted lyrics.txt") and linked to `uri`. Main thread.
void SGImportPastedLyrics(NSString *text, NSString *uri, void (^completion)(NSString *name, NSError *error));
// Removes the file and any link to it, on the store's own queue; the answer comes back on the main queue.
// NO, without asking the store, only for a name that is not a file name at all.
BOOL SGDeleteImportedLRC(NSString *name, void (^completion)(BOOL deleted));
// The files an import replaced, deleted at the next launch. A replacement writes its new file, links it,
// and puts the replaced name on a list of its own; nothing is deleted in that step. The step runs once per
// launch, first in the store's queue, before any change that launch asks for, and removes only a name on
// the list that no link names as the defaults hold it, is directly in the lyrics directory, and is a
// regular file there. A name still linked stays on the list; a name whose file is gone leaves it. A by-name
// import and a hand-copied file are never on the list, so they are never touched. The removed names come
// back on the main queue; this never runs synchronously on the caller's.
void SGRetireImportedLyrics(void (^completion)(NSArray<NSString *> *removed));
// The file linked to a song, by its URI or its engine key; nil for none. Safe from any thread.
NSString *SGImportedLRCLinkedTo(NSString *uri);
// The lines for a track: its linked file, else the first file whose title and artist match the names
// given (for a local file, nil names are read from the file's URI and the player's track). nil when no
// file has it. Synchronous: callers on the UI thread use SGImportedLRCFetch instead.
SGLyricsResult *SGImportedLRCFor(NSString *trackID, NSString *title, NSString *artist);
// Entry/completion on main; snapshot names there, then scan and parse files on a serial worker.
// An import/delete during lookup restarts against the new library before completing.
void SGImportedLRCFetch(NSString *trackID, NSString *title, NSString *artist, void (^done)(SGLyricsResult *result));
// Automatic playback only (not the Imported provider): linked sheet, embedded lyrics at the
// player's observed local_file_path, then local title/artist matches. Main entry and callback.
void SGPlaybackLyricsFetch(NSString *trackID, NSString *path, void (^done)(SGLyricsResult *result));
// Posted on main after import/delete. Object: array of affected linked URIs; name matches may also change.
extern NSNotificationName const SGImportedLRCDidChangeNotification;

// LocalLyricsPage.m
UIViewController *SGImportedLRCPage(void);

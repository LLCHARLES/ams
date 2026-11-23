// LocalLyrics.h says what is kept and how a track finds its file.
//
// Playback snapshots names on main and reads files on a serial worker. The native lyrics page also
// reads off main, so links and the bounded cache of files read are protected across both readers.
#import <os/lock.h>
#import "Core/SGCore.h"
#import "Core/SGDataRoot.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Headers/SPTPlayer.h"
#import "LocalFiles.h"
#import "LocalLyrics.h"
#import "LyricRetirement.h"
#import "EmbeddedLyrics.h"

NSString *const SGImportedLRCKey = @"importedLRC";
NSString *const SGLyricsImportErrorDomain = @"spotifyglass.lrc";
NSNotificationName const SGImportedLRCDidChangeNotification = @"spotifyglass.localFiles.lrcDidChange";

static NSString *const kCredit = @"Imported LRC";
// A song's lyrics are a few kilobytes; anything near this is not one.
static const NSUInteger kMostBytes = SGLyricsImportMaxBytes;

// The retired list, read and written in the defaults beside the links (SGKeyRetiredImportedLyrics).
static NSString *const linkedIdentities = @"spotifyglass.localFiles.linkedLyricIdentities";
static void unretire(NSString *name);
static NSString *directory(void);

#pragma mark - the files

// What is kept goes under the extension of the kind its content turned out to be, so a file in
// Documents says what it holds. What it holds is read again on every load, never taken from the name.
static NSArray<NSString *> *const kLyricsExtensions = @[@"ttml", @"lrc", @"txt"];

static NSString *extensionOfKind(SGLyricsImportKind kind) {
    return kLyricsExtensions[(NSUInteger)kind];
}

static NSString *directory(void) {
    return [SGDataRoot(NSDocumentDirectory).path stringByAppendingPathComponent:@"Lyrics"];
}

// The store has one owner: every change to it runs on this one serial queue, in the order the calls came
// in. That is a name's allocation, the file it is written to, the links and the retired list, a user's
// delete, and the launch's retire step. So a retire step can never run beside an import that reuses a
// name it is about to delete, and it always sees the store as it stood before this launch touched it.
// Callers hand in work and get their answer back on the main queue.
static dispatch_queue_t storeQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("app.retrine.imported-lyrics-store", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

// Reading and parsing what an import or a paste holds runs on this one serial queue, off main, before the
// store is touched. Imports and pastes therefore reach the store in the order they were asked for, so a slow
// one cannot be overtaken by, and then overwrite the link of, a later one for the same track.
static dispatch_queue_t importQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("app.retrine.imported-lyrics-parse", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0));
    });
    return queue;
}

NSArray<NSString *> *SGImportedLRCFiles(void) {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:directory() error:nil]) {
        if ([kLyricsExtensions containsObject:name.pathExtension.lowercaseString]) [names addObject:name];
    }
    return [names sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

#pragma mark - the links

static NSDictionary<NSString *, NSString *> *sg_links;
static os_unfair_lock sg_linksLock = OS_UNFAIR_LOCK_INIT;

static NSDictionary<NSString *, NSString *> *allLinks(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        id stored = [NSUserDefaults.standardUserDefaults dictionaryForKey:SGKeyImportedLRCLinks];
        os_unfair_lock_lock(&sg_linksLock);
        sg_links = [stored isKindOfClass:NSDictionary.class] ? stored : @{};
        os_unfair_lock_unlock(&sg_linksLock);
    });
    os_unfair_lock_lock(&sg_linksLock);
    NSDictionary *links = sg_links;
    os_unfair_lock_unlock(&sg_linksLock);
    return links;
}

static void storeLinks(NSDictionary<NSString *, NSString *> *links) {
    os_unfair_lock_lock(&sg_linksLock);
    sg_links = [links copy];
    os_unfair_lock_unlock(&sg_linksLock);
    if (links.count) [NSUserDefaults.standardUserDefaults setObject:links forKey:SGKeyImportedLRCLinks];
    else [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyImportedLRCLinks];
}

// A lyrics key carries "#<number>" after the URI once the file's names are edited (LocalFiles.h); the
// link is to the file, so it holds through a rename.
static NSString *bareURI(NSString *uri) {
    if (!SGLocalFileIs(uri)) {
        if ([uri hasPrefix:@"spotify:track:"]) return uri;
        // The engine and the source picker use the catalogue ID, not the full URI.
        return uri.length && [uri rangeOfString:@":"].location == NSNotFound
            ? [@"spotify:track:" stringByAppendingString:uri] : nil;
    }
    NSRange mark = [uri rangeOfString:@"#" options:NSBackwardsSearch];
    return mark.location == NSNotFound ? uri : [uri substringToIndex:mark.location];
}

NSString *SGImportedLRCLinkedTo(NSString *uri) {
    NSString *bare = bareURI(uri);
    if (!bare) return nil;
    id name = allLinks()[bare];
    return [name isKindOfClass:NSString.class] ? name : nil;
}

#pragma mark - reading a file

@interface SGImportedLyrics ()
@property (nonatomic) SGLyricsImportKind kind;
@property (nonatomic, copy) NSString *title, *artist, *text;
@property (nonatomic, copy) NSArray<SGKaraokeLine *> *lines;
@property (nonatomic, copy) NSArray<NSNumber *> *starts;
@property (nonatomic, copy) NSArray<NSString *> *texts;
@property (nonatomic) BOOL synced;
@end

@implementation SGImportedLyrics
@end

static NSError *refusal(SGLyricsImportError code) {
    // The page shows the reason from the code, so the same refusal reads the same everywhere.
    return [NSError errorWithDomain:SGLyricsImportErrorDomain code:code userInfo:nil];
}

static NSString *trimmed(NSString *text) {
    return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

// The lines as Spotify's own page takes them, and whether they are timed at all. Lines with no time are
// handed over as they are, one a row starting at 0: that is how the mod shows unsynced lyrics.
static void finish(SGImportedLyrics *lyrics) {
    for (SGKaraokeLine *line in lyrics.lines) line.fileOwned = YES;
    lyrics.synced = SGKaraokeLinesTiming(lyrics.lines) != SGKaraokeTimingNone;
    if (lyrics.synced) {
        NSArray<NSNumber *> *starts;
        NSArray<NSString *> *texts;
        SGLyricsPageLines(lyrics.lines, &starts, &texts);
        lyrics.starts = starts;
        lyrics.texts = texts;
        return;
    }
    NSMutableArray<NSNumber *> *starts = [NSMutableArray array];
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    for (SGKaraokeLine *line in lyrics.lines) {
        [starts addObject:@0];
        [texts addObject:SGKaraokeLineText(line)];
    }
    lyrics.starts = starts;
    lyrics.texts = texts;
}

// A document holding an XML `tt` element, which is what a TTML document is. Read before parsing: a
// document that looks like one and gives no line is read as plain text instead.
static BOOL looksLikeTTML(NSString *text) {
    NSRange head = [text rangeOfString:@"<" options:0 range:NSMakeRange(0, MIN(text.length, (NSUInteger)4096))];
    if (head.location == NSNotFound) return NO;
    static NSRegularExpression *tag;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // `<tt>`, `<tt …>`, and the same with whatever namespace prefix the document declares.
        tag = [NSRegularExpression regularExpressionWithPattern:@"<(?:[A-Za-z_][-A-Za-z0-9_.]*:)?tt[\\s/>]"
                                                        options:NSRegularExpressionCaseInsensitive error:nil];
    });
    return [tag firstMatchInString:text options:0 range:NSMakeRange(0, text.length)] != nil;
}

// A file that is LRC: a stamp on a line, or a tag ("[ti:...]", "[by:...]"), which is what its reader is
// written for. Anything else is plain text, and every line of it is a line of the song, brackets and all.
static BOOL looksLikeLRC(NSString *text) {
    static NSRegularExpression *tag;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // LRC's tags: a name and a value in brackets, which a line sung with a bracketed word is not.
        tag = [NSRegularExpression regularExpressionWithPattern:@"^\\[[A-Za-z#][^\\]:]*:[^\\]]*\\]" options:0 error:nil];
    });
    NSRegularExpression *stamp = SGLyricsLRCStamp();
    for (NSString *raw in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *row = trimmed(raw);
        if (row.length < 3 || ![row hasPrefix:@"["]) continue;
        if ([tag firstMatchInString:row options:0 range:NSMakeRange(0, row.length)]) return YES;
        if ([stamp firstMatchInString:row options:0 range:NSMakeRange(0, row.length)]) return YES;
    }
    return NO;
}

// [01:02], [01:02.3], [01:02.34], [01:02.345], [101:02:34]: a stamp as SGLyricsLRCStamp in
// LyricsSources.h reads it. A line sung more than once carries a stamp per time. A file with no stamp
// keeps its lines as they are; one that is LRC drops the lines in brackets, which are its tags and
// comments rather than something sung. Either way a line is trimmed, and an empty one is not a line.
static SGImportedLyrics *sheetFrom(NSString *lrc) {
    static NSRegularExpression *tag, *leadingBrackets;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        tag = [NSRegularExpression regularExpressionWithPattern:@"^\\[(ti|ar|offset)\\s*:([^\\]]*)\\]" options:NSRegularExpressionCaseInsensitive error:nil];
        // A row's opening brackets, one after another: "[ti:...]", "[00:bad]", "[ar:x][00:bad]".
        leadingBrackets = [NSRegularExpression regularExpressionWithPattern:@"^(?:\\[[^\\]]*\\])+" options:0 error:nil];
    });
    BOOL lrcKind = looksLikeLRC(lrc);
    NSRegularExpression *stamp = SGLyricsLRCStamp();
    SGImportedLyrics *sheet = [SGImportedLyrics new];
    NSInteger offset = 0;
    NSMutableArray<NSArray *> *stamped = [NSMutableArray array];   // [ms, text]
    NSMutableArray<NSString *> *plain = [NSMutableArray array];
    NSUInteger plainChars = 0, stampedChars = 0;
    for (NSString *raw in [lrc componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *row = trimmed([raw stringByReplacingOccurrencesOfString:@"﻿" withString:@""]);
        NSTextCheckingResult *named = [tag firstMatchInString:row options:0 range:NSMakeRange(0, row.length)];
        if (named) {
            NSString *which = [row substringWithRange:[named rangeAtIndex:1]].lowercaseString;
            NSString *value = trimmed([row substringWithRange:[named rangeAtIndex:2]]);
            if ([which isEqualToString:@"ti"] && value.length) sheet.title = value;
            else if ([which isEqualToString:@"ar"] && value.length) sheet.artist = value;
            else if ([which isEqualToString:@"offset"]) offset = value.integerValue;   // "+250" and "-250" both read
            continue;
        }
        NSArray<NSTextCheckingResult *> *found = [stamp matchesInString:row options:0 range:NSMakeRange(0, row.length)];
        if (!found.count) {
            // No stamp this reads. In plain text the row stands as it was written, brackets and all. In
            // LRC the row is one whose timestamp the file got wrong, or one of its tags or a comment:
            // what is left once its brackets are off is the line's text, and a row of tags alone has none.
            NSString *rest = lrcKind ? trimmed([leadingBrackets stringByReplacingMatchesInString:row options:0
                                                                                          range:NSMakeRange(0, row.length) withTemplate:@""])
                                     : row;
            if (rest.length) {
                if (plain.count >= SGFileLyricsMaxLines || rest.length > SGFileLyricsMaxCharacters - plainChars) return nil;
                plainChars += rest.length;
                [plain addObject:rest];
            }
            continue;
        }
        NSString *text = trimmed([stamp stringByReplacingMatchesInString:row options:0 range:NSMakeRange(0, row.length) withTemplate:@""]);
        if (!text.length) continue;
        if (found.count > SGFileLyricsMaxLines - stamped.count ||
            text.length > (SGFileLyricsMaxCharacters - stampedChars) / found.count) return nil;
        stampedChars += text.length * found.count;
        for (NSTextCheckingResult *match in found) {
            [stamped addObject:@[@(SGLyricsLRCStampMs(row, match)), text]];
        }
    }
    if (stamped.count) {
        sheet.kind = SGLyricsImportKindLRC;
        [stamped sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
            return [a[0] compare:b[0]];
        }];
        NSMutableArray<NSNumber *> *starts = [NSMutableArray array];
        NSMutableArray<NSString *> *texts = [NSMutableArray array];
        // A positive offset brings the lyrics in sooner.
        for (NSArray *line in stamped) {
            [starts addObject:@(MAX([line[0] integerValue] - offset, 0))];
            [texts addObject:line[1]];
        }
        sheet.lines = SGKaraokeEstimatedLines(starts, texts);
        finish(sheet);
    } else if (plain.count) {
        sheet.kind = SGLyricsImportKindText;
        sheet.lines = SGKaraokeStaticLines(plain);
        finish(sheet);
    }
    return sheet;
}

// What a TTML document says in plain words, for one the reader could not make lines of: its elements go,
// and what is left between them is its text.
static NSString *tagless(NSString *xml) {
    static NSRegularExpression *element, *comments;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        comments = [NSRegularExpression regularExpressionWithPattern:@"<!--.*?-->" options:NSRegularExpressionDotMatchesLineSeparators error:nil];
        element = [NSRegularExpression regularExpressionWithPattern:@"<[^>]*>" options:0 error:nil];
    });
    NSString *text = [comments stringByReplacingMatchesInString:xml options:0 range:NSMakeRange(0, xml.length) withTemplate:@" "];
    return [element stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0, text.length) withTemplate:@"\n"];
}

// The order LyricsSources.h promises: TTML first, then LRC, then plain text. A document that looks like
// TTML but gives no line is read for the words between its elements, and one that looks like LRC but has
// no stamp for its lines; with no line either way it is refused.
static SGImportedLyrics *sheetFromText(NSString *text) {
    if (looksLikeTTML(text)) {
        NSArray<SGKaraokeLine *> *lines = SGTTMLLines(text);
        if (lines.count) {
            if (lines.count > SGFileLyricsMaxLines) return nil;
            NSUInteger chars = 0;
            for (SGKaraokeLine *line in lines) {
                chars += SGKaraokeLineText(line).length + SGKaraokeLineText(line.backing).length;
                if (chars > SGFileLyricsMaxCharacters) return nil;
            }
            SGImportedLyrics *sheet = [SGImportedLyrics new];
            sheet.kind = SGLyricsImportKindTTML;
            sheet.lines = lines;
            finish(sheet);
            return sheet;
        }
        return sheetFrom(tagless(text));
    }
    return sheetFrom(text);
}

SGImportedLyrics *SGImportedLyricsFromText(NSString *text, NSError **error) {
    NSError *reason = nil;
    SGImportedLyrics *sheet = nil;
    if (![text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) {
        reason = refusal(SGLyricsImportErrorNothing);
    } else if ((sheet = sheetFromText(text)).lines.count) {
        sheet.text = text;
        return sheet;
    } else {
        reason = refusal(SGLyricsImportErrorUnreadable);
    }
    if (error) *error = reason;
    return nil;
}

SGImportedLyrics *SGImportedLyricsFromData(NSData *data, NSError **error) {
    if (!data.length) {
        if (error) *error = refusal(SGLyricsImportErrorNothing);
        return nil;
    }
    if (data.length > kMostBytes) {
        if (error) *error = refusal(SGLyricsImportErrorTooLarge);
        return nil;
    }
    // UTF-8 first: a BOM in front of it is dropped. UTF-16 only with a BOM, which is the only way a
    // byte order is known; anything else that fails both is not text this reads.
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text) {
        NSData *bom = [data subdataWithRange:NSMakeRange(0, MIN(data.length, (NSUInteger)2))];
        if ([bom isEqualToData:[NSData dataWithBytes:"\xFF\xFE" length:2]] || [bom isEqualToData:[NSData dataWithBytes:"\xFE\xFF" length:2]]) {
            text = [[NSString alloc] initWithData:data encoding:NSUTF16StringEncoding];
        }
    }
    if (!text) {
        if (error) *error = refusal(SGLyricsImportErrorUnreadable);
        return nil;
    }
    return SGImportedLyricsFromText(text, error);
}

// Read sheets are bounded independently of the number of imported files.
static NSMutableDictionary<NSString *, SGImportedLyrics *> *sg_sheets;
static NSUInteger sg_sheetGeneration;
static const NSUInteger kKeptSheets = 40;

static SGImportedLyrics *sheetNamed(NSString *name) {
    NSUInteger generation;
    @synchronized (SGImportedLyrics.class) {
        if (!sg_sheets) sg_sheets = [NSMutableDictionary dictionary];
        SGImportedLyrics *kept = sg_sheets[name];
        if (kept) return kept;
        generation = sg_sheetGeneration;
    }
    NSString *text = [NSString stringWithContentsOfFile:[directory() stringByAppendingPathComponent:name] encoding:NSUTF8StringEncoding error:nil];
    SGImportedLyrics *sheet = text ? sheetFromText(text) : nil;
    if (!sheet.lines.count) return nil;
    @synchronized (SGImportedLyrics.class) {
        if (generation != sg_sheetGeneration) return nil;
        if (sg_sheets.count >= kKeptSheets && !sg_sheets[name]) [sg_sheets removeAllObjects];
        sg_sheets[name] = sheet;
    }
    return sheet;
}

static void forgetSheets(void) {
    @synchronized (SGImportedLyrics.class) {
        sg_sheetGeneration++;
        [sg_sheets removeAllObjects];
    }
}

#pragma mark - matching

// Case, diacritics and width ignored, and anything but letters and digits: "Beyoncé – Halo (Live)"
// and "beyonce halo live" fold the same.
static NSString *folded(NSString *text) {
    if (![text isKindOfClass:NSString.class]) return @"";
    NSString *plain = [text stringByFoldingWithOptions:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch locale:nil].lowercaseString;
    return [[plain componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet] componentsJoinedByString:@""];
}

static NSString *nonEmpty(id value) {
    return [value isKindOfClass:NSString.class] && [value length] ? value : nil;
}

// A file named "Artist - Title" or "Title - Artist" (a hyphen, en dash or em dash between spaces) with no
// [ti:]: the side equal to the track's title is the title and the other the artist.
static BOOL sheetMatches(SGImportedLyrics *sheet, NSString *name, NSString *title, NSArray<NSString *> *artists) {
    NSString *wanted = folded(title);
    if (!wanted.length) return NO;
    NSString *fileTitle = sheet.title, *fileArtist = sheet.artist;
    if (!fileTitle) {
        NSString *base = name.stringByDeletingPathExtension;
        fileTitle = base;
        for (NSString *dash in @[@" - ", @" – ", @" — "]) {
            NSRange split = [base rangeOfString:dash];
            if (split.location == NSNotFound) continue;
            NSString *left = [base substringToIndex:split.location], *right = [base substringFromIndex:NSMaxRange(split)];
            if ([folded(right) isEqualToString:wanted]) {
                fileTitle = right;
                fileArtist = fileArtist ?: left;
            } else if ([folded(left) isEqualToString:wanted]) {
                fileTitle = left;
                fileArtist = fileArtist ?: right;
            }
            break;
        }
    }
    if (![folded(fileTitle) isEqualToString:wanted]) return NO;
    if (!fileArtist.length) return YES;
    NSString *artist = folded(fileArtist);
    for (NSString *one in artists) {
        if ([folded(one) isEqualToString:artist]) return YES;
    }
    return NO;
}

// What a local file is called when no names were given: the player's track model, the tags its metadata
// may carry under other keys when the model's are empty, and last the parts of its URI.
static void localNames(NSString *trackID, NSString **title, NSMutableArray<NSString *> *artists) {
    SPTPlayerTrack *track = SGKaraokeTrackFor(trackID);
    NSDictionary *metadata = [track.metadata isKindOfClass:NSDictionary.class] ? track.metadata : nil;
    NSString *named = nonEmpty(track.trackTitle);
    for (NSString *key in @[@"track_title", @"title", @"name"]) named = named ?: nonEmpty(metadata[key]);
    *title = named ?: SGLocalFileInfo(trackID)[@"title"];

    NSString *artist = nonEmpty(track.artistName);
    for (NSString *key in @[@"artist_name", @"artist"]) artist = artist ?: nonEmpty(metadata[key]);
    if (artist) [artists addObject:artist];
    id listed = metadata[@"artists"];
    for (id one in [listed isKindOfClass:NSArray.class] ? listed : @[]) {
        NSString *each = nonEmpty(one) ?: ([one isKindOfClass:NSDictionary.class] ? nonEmpty(one[@"name"]) : nil);
        if (each) [artists addObject:each];
    }
    for (NSUInteger i = 1; nonEmpty(metadata[[NSString stringWithFormat:@"artist_name:%lu", (unsigned long)i]]); i++) {
        [artists addObject:metadata[[NSString stringWithFormat:@"artist_name:%lu", (unsigned long)i]]];
    }
    NSString *tagged = SGLocalFileInfo(trackID)[@"artist"];
    if (!artists.count && tagged) [artists addObject:tagged];
}

static SGLyricsResult *resultOf(SGImportedLyrics *sheet, NSString *title, NSString *artist) {
    if (!sheet.lines.count) return nil;
    SGLyricsResult *result = [SGLyricsResult new];
    result.provider = kCredit;
    result.synced = sheet.synced;
    result.karaokeLines = sheet.lines;
    result.starts = sheet.starts;
    result.texts = sheet.texts;
    result.title = sheet.title ?: title;
    result.artist = sheet.artist ?: artist;
    return result;
}

// The file a link names, or nil when it is not there: the one a launch that ended between an import's
// link and its file's write left behind is one such, and it gives no lines rather than a stuck answer.
static SGImportedLyrics *linkedSheet(NSString *name) {
    if (!name.length) return nil;
    if (![NSFileManager.defaultManager fileExistsAtPath:[directory() stringByAppendingPathComponent:name]]) {
        SGLog(@"lyrics: %@ is linked but not stored", name);
        return nil;
    }
    return sheetNamed(name);
}

static SGLyricsResult *lookup(NSString *linked, NSString *title, NSArray<NSString *> *artists) {
    // A track with a file linked to it has that file's lines and no other: a link that points at nothing
    // leaves the track with none, rather than with another song's.
    if (linked) return resultOf(linkedSheet(linked), title, artists.firstObject);
    for (NSString *name in SGImportedLRCFiles()) {
        @autoreleasepool {
            SGImportedLyrics *sheet = sheetNamed(name);
            if (sheet.lines.count && sheetMatches(sheet, name, title, artists)) return resultOf(sheet, nil, nil);
        }
    }
    return nil;
}

SGLyricsResult *SGImportedLRCFor(NSString *trackID, NSString *title, NSString *artist) {
    NSString *linked = SGImportedLRCLinkedTo(trackID);
    if (!SGLocalFileIs(trackID) && !linked) return nil;
    NSMutableArray<NSString *> *artists = [NSMutableArray array];
    if (SGLocalFileIs(trackID) && !title.length) localNames(trackID, &title, artists);
    else if (artist.length) [artists addObject:artist];
    return lookup(linked, title, artists);
}

static void fetch(NSString *trackID, NSString *title, NSString *artist, NSString *path, void (^done)(SGLyricsResult *)) {
    NSUInteger generation;
    @synchronized (SGImportedLyrics.class) { generation = sg_sheetGeneration; }
    NSString *resolved = title, *linked = SGImportedLRCLinkedTo(trackID);
    if (!linked && !SGLocalFileIs(trackID)) { done(nil); return; }
    NSMutableArray<NSString *> *artists = [NSMutableArray array];
    if (SGLocalFileIs(trackID) && !resolved.length) localNames(trackID, &resolved, artists);
    else if (artist.length) [artists addObject:artist];
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("app.retrine.imported-lyrics", DISPATCH_QUEUE_SERIAL); });
    dispatch_async(queue, ^{
        @autoreleasepool {
            SGLyricsResult *result = linked ? resultOf(linkedSheet(linked), resolved, artists.firstObject) : nil;
            if (!result && path) result = SGEmbeddedLyrics(path);
            if (!result && !linked) result = lookup(nil, resolved, artists);
            dispatch_async(dispatch_get_main_queue(), ^{
                BOOL changed;
                @synchronized (SGImportedLyrics.class) { changed = generation != sg_sheetGeneration; }
                if (changed) { fetch(trackID, title, artist, path, done); return; }
                done(result);
            });
        }
    });
}

void SGImportedLRCFetch(NSString *trackID, NSString *title, NSString *artist, void (^done)(SGLyricsResult *)) {
    fetch(trackID, title, artist, nil, done);
}

void SGPlaybackLyricsFetch(NSString *trackID, NSString *path, void (^done)(SGLyricsResult *)) {
    fetch(trackID, nil, nil, SGLocalFileIs(trackID) && [path isKindOfClass:NSString.class] ? path : nil, done);
}

SGLyricsAsk SGImportedLRCAsk = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *result)) {
    SGImportedLRCFetch(query.trackID, query.title, query.artist, done);
};

#pragma mark - importing and deleting

// Once LyricsSources lists the source, the first import and every link put it first in the order.
static void moveToTop(void) {
    if (!SGLyricsProviderFor(SGImportedLRCKey)) return;
    NSMutableArray<NSString *> *order = [SGLyricsOrder() mutableCopy];
    [order removeObject:SGImportedLRCKey];
    [order insertObject:SGImportedLRCKey atIndex:0];
    SGLyricsSetOrder(order);
}

// The store changed: the lines read so far are dropped, and every listener is told on the main queue,
// which is where the ones that touch UIKit and the lyrics state run.
static void changed(NSArray<NSString *> *uris) {
    forgetSheets();
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:SGImportedLRCDidChangeNotification object:uris];
    });
}

// The name it came with, "/" made safe, and " (2)", " (3)" and on when one by that name is kept. The
// extension is the one what it holds goes under, so the file the page lists and Documents hold say what
// kind of lyrics they are.
static NSString *freeName(NSString *given, SGLyricsImportKind kind) {
    NSString *name = [given stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
    NSString *base = name.stringByDeletingPathExtension, *extension = extensionOfKind(kind);
    if (!base.length || [base hasPrefix:@"."]) base = [@"Lyrics" stringByAppendingString:base];
    name = [base stringByAppendingPathExtension:extension];
    for (NSUInteger n = 2; [NSFileManager.defaultManager fileExistsAtPath:[directory() stringByAppendingPathComponent:name]]; n++) {
        name = [[NSString stringWithFormat:@"%@ (%lu)", base, (unsigned long)n] stringByAppendingPathExtension:extension];
    }
    return name;
}

// What a file or a paste leaves behind: the new file written and linked, and the one it replaced left on
// disk with its name on the retired list. Runs on storeQueue and on nothing else. Deleting the replaced
// file here would lose the lyrics: the link lives in NSUserDefaults, which is written out later, so a
// launch that ends in between would find no link and no old file either. SGRetireImportedLyrics decides at
// the next launch, when it knows which link was kept.
static NSString *storeLyrics(SGImportedLyrics *lyrics, NSString *given, NSString *uri, NSError **error) {
    if (!directory()) {
        if (error) *error = refusal(SGLyricsImportErrorStorage);
        return nil;
    }
    BOOL first = SGImportedLRCFiles().count == 0;
    NSString *name = freeName(given, lyrics.kind);
    NSString *bare = bareURI(uri);
    NSString *replaced = bare ? allLinks()[bare] : nil;
    NSError *writeError = nil;
    NSDictionary *receipt = nil;
    [NSFileManager.defaultManager createDirectoryAtPath:directory() withIntermediateDirectories:YES attributes:nil error:&writeError];
    if (!SGWriteImportedLyric(lyrics.text, [NSURL fileURLWithPath:[directory() stringByAppendingPathComponent:name]], &receipt, &writeError)) {
        SGLog(@"lyrics: %@ not written: %@", name, writeError);
        if (error) *error = refusal(SGLyricsImportErrorStorage);
        return nil;
    }
    if (bare) {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        NSMutableDictionary *proofs = [[defaults dictionaryForKey:linkedIdentities] mutableCopy] ?: [NSMutableDictionary dictionary];
        NSDictionary *old = proofs[bare];
        if (replaced && [old[@"name"] isEqual:replaced] && ![replaced isEqual:name]) {
            NSArray *pending = [defaults arrayForKey:SGKeyRetiredImportedLyrics] ?: @[];
            [defaults setObject:[pending arrayByAddingObject:old] forKey:SGKeyRetiredImportedLyrics];
        }
        proofs[bare] = receipt;
        [defaults setObject:proofs forKey:linkedIdentities];
        NSMutableDictionary *links = [allLinks() mutableCopy];
        links[bare] = name;
        storeLinks(links);
    }
    if (first || bare) moveToTop();
    SGLog(@"lyrics: imported %@%@", name, bare ? [@" for " stringByAppendingString:bare] : @"");
    changed(bare ? @[bare] : @[]);
    return name;
}

void SGImportLRC(NSURL *url, NSString *uri, void (^completion)(NSString *, NSError *)) {
    NSString *ext = url.pathExtension.lowercaseString;
    if (![kLyricsExtensions containsObject:ext] && ![ext isEqual:@"xml"]) {
        completion(nil, refusal(SGLyricsImportErrorType));
        return;
    }
    // The file's bytes and its lines are read before the store is touched, off the store queue.
    dispatch_async(importQueue(), ^{
        BOOL scoped = [url startAccessingSecurityScopedResource];
        NSError *readError;
        NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:url error:&readError];
        NSData *data = [handle readDataUpToLength:kMostBytes + 1 error:&readError];
        NSError *closeError;
        if (handle && ![handle closeAndReturnError:&closeError]) readError = readError ?: closeError;
        if (scoped) [url stopAccessingSecurityScopedResource];
        NSError *failure = nil;
        SGImportedLyrics *lyrics = (!handle || readError || !data) ? nil : SGImportedLyricsFromData(data, &failure);
        if (!lyrics && !failure) {
            SGLog(@"lyrics: %@ not read: %@", url.lastPathComponent, readError);
            failure = refusal(SGLyricsImportErrorUnreadableFile);
        }
        // The store itself is written on its own queue, after every change already asked for.
        dispatch_async(storeQueue(), ^{
            @autoreleasepool {
                NSError *error = failure;
                NSString *name = error ? nil : storeLyrics(lyrics, url.lastPathComponent, uri, &error);
                dispatch_async(dispatch_get_main_queue(), ^{ completion(name, error); });
            }
        });
    });
}

void SGImportPastedLyrics(NSString *text, NSString *uri, void (^completion)(NSString *, NSError *)) {
    // The text, the URI and the name are captured here on main; the document is encoded and parsed on a
    // worker queue shared with file imports, and only then handed to the store queue.
    NSString *pasted = [text copy], *linkedURI = [uri copy], *given = SGL(@"settings.locallyrics.paste.name", @"Pasted lyrics");
    dispatch_async(importQueue(), ^{
        // Through the data path, so a paste is held to the same size and content rules as a file.
        NSError *parseError = nil;
        SGImportedLyrics *lyrics = nil;
        if ([pasted lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > kMostBytes) parseError = refusal(SGLyricsImportErrorTooLarge);
        else if (pasted.length && ![pasted canBeConvertedToEncoding:NSUTF8StringEncoding]) parseError = refusal(SGLyricsImportErrorUnreadable);
        else lyrics = SGImportedLyricsFromText(pasted, &parseError);
        dispatch_async(storeQueue(), ^{
            @autoreleasepool {
                NSError *error = parseError;
                NSString *name = error ? nil : storeLyrics(lyrics, given, linkedURI, &error);
                dispatch_async(dispatch_get_main_queue(), ^{ completion(name, error); });
            }
        });
    });
}

BOOL SGDeleteImportedLRC(NSString *name, void (^completion)(BOOL deleted)) {
    if (!name.length || name.pathComponents.count != 1) {
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
        return NO;
    }
    // Deleting a file has to happen where the rest of the store changes do, or it can race the launch's
    // retire step into deleting a file an import has just taken the name of. The answer comes back on main.
    if (completion) completion = [completion copy];
    dispatch_async(storeQueue(), ^{
        @autoreleasepool {
            NSError *error = nil;
            BOOL deleted = [NSFileManager.defaultManager removeItemAtPath:[directory() stringByAppendingPathComponent:name] error:&error];
            if (!deleted && [error.domain isEqual:NSCocoaErrorDomain] && error.code == NSFileNoSuchFileError &&
                [allLinks() allKeysForObject:name].count) deleted = YES;
            if (deleted) {
                NSMutableDictionary *links = [allLinks() mutableCopy];
                NSArray *uris = [links allKeysForObject:name];
                NSMutableDictionary *proofs = [[NSUserDefaults.standardUserDefaults dictionaryForKey:linkedIdentities] mutableCopy];
                [proofs removeObjectsForKeys:uris];
                if (proofs) [NSUserDefaults.standardUserDefaults setObject:proofs forKey:linkedIdentities];
                [links removeObjectsForKeys:uris];
                storeLinks(links);
                unretire(name);
                changed(uris);
            } else {
                SGLog(@"lyrics: %@ not deleted: %@", name, error);
            }
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(deleted); });
        }
    });
    return YES;
}

#pragma mark - the retired files

// The files an import replaced, by name, in the defaults beside the links: a file gets here the moment it
// stops being a track's lyrics, and only SGRetireImportedLyrics takes it away again. Nothing else ever
// deletes a file for not being linked: a by-name import ("Import lyrics…", matched by its tags or its
// name) and a file copied into the folder by hand are nobody's links, and they stay until the user
// deletes them.
static NSArray *retired(void) {
    return [NSUserDefaults.standardUserDefaults arrayForKey:SGKeyRetiredImportedLyrics] ?: @[];
}

static void storeRetired(NSArray *names) {
    if (names.count) [NSUserDefaults.standardUserDefaults setObject:names forKey:SGKeyRetiredImportedLyrics];
    else [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyRetiredImportedLyrics];
}

static void unretire(NSString *name) {
    NSMutableArray *names = [NSMutableArray array];
    for (id record in retired())
        if ([record isKindOfClass:NSDictionary.class] && ![record[@"name"] isEqual:name]) [names addObject:record];
    storeRetired(names);
}

// The launch's one retire step, enqueued first so it runs before any change this launch asks for. Runs on
// storeQueue and on nothing else. It only ever considers the names the retired list holds, so a by-name
// import, a hand-copied file and anything else nobody linked are never candidates.
static NSArray<NSString *> *retireNow(void) {
    NSArray *names = retired();
    if (!names.count || !directory()) return @[];
    // The links as the defaults hold them now, not as the running app first read them: this runs at launch
    // before any import of the launch, and a name an import retired but whose link update never reached
    // disk is still linked here, so it stays.
    id stored = [NSUserDefaults.standardUserDefaults dictionaryForKey:SGKeyImportedLRCLinks];
    NSSet<NSString *> *linked = [NSSet setWithArray:([stored isKindOfClass:NSDictionary.class] ? [stored allValues] : @[])];
    NSMutableArray *kept = [NSMutableArray array];
    NSMutableArray<NSString *> *removed = [NSMutableArray array];
    NSURL *folder = [NSURL fileURLWithPath:directory() isDirectory:YES];
    for (id record in names) {
        NSString *name = [record isKindOfClass:NSDictionary.class] ? record[@"name"] : nil;
        if (name && [linked containsObject:name]) {
            [kept addObject:record];
            continue;
        }
        BOOL deleted;
        if (!SGRemoveRetiredLyric(folder, record, &deleted)) [kept addObject:record];
        if (deleted) {
            [removed addObject:name];
            SGLog(@"lyrics: retired %@ removed", name);
        }
    }
    storeRetired(kept);
    if (removed.count) changed(@[]);
    return removed;
}

void SGRetireImportedLyrics(void (^completion)(NSArray<NSString *> *removed)) {
    if (completion) completion = [completion copy];
    dispatch_async(storeQueue(), ^{
        @autoreleasepool {
            NSArray<NSString *> *removed = retireNow();
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(removed); });
        }
    });
}

// Once per launch, early, and first in the store's queue: this is enqueued before anything this launch can
// ask the store to change, so it reads the store as the launch found it.
__attribute__((constructor)) static void sg_retireImportedLyricsAtLaunch(void) {
    dispatch_async(storeQueue(), ^{ @autoreleasepool { retireNow(); } });
}

// Album redesign: how many times each track of an album was played, from Retrine's own listening history
// (Shared/ListeningStats), for the track rows to show (AlbumRows.x).
//
// A row exposes no track URI that has been proven against the tree, so a play is matched by its album and its
// title: the header's album title and the row's title, both folded (case, diacritics and width) and trimmed.
// A play with no album -- Spotify's basic export carries none -- matches no row.
//
// The counts are added up off the main thread from a snapshot of the log, once when an album row first asks
// and again whenever the log changes. The log only ever grows at its end except when it is erased or read
// again, so an unchanged log generation adds only the plays past the ones already counted.
// Threading: main thread only, but for the adding up.
#import "Core/SGCore.h"
#import "Shared/ListeningStats/ListeningStats.h"
#import "Shared/ListeningStats/SGPlayLog.h"
#import "Album.h"

NSNotificationName const SGRAlbumPlayCountsDidChangeNotification = @"SGRAlbumPlayCountsDidChange";

static NSDictionary<NSString *, NSNumber *> *sgr_counts;
static NSUInteger sgr_generation;     // the log generation the counts were taken from
static NSUInteger sgr_counted;          // how many of its plays they cover
static BOOL sgr_started, sgr_busy, sgr_again;

static NSString *folded(NSString *text) {
    NSString *clean = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return [clean stringByFoldingWithOptions:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch
                                      locale:nil];
}

static NSString *keyOf(NSString *album, NSString *title) {
    NSString *a = folded(album), *t = folded(title);
    return a.length && t.length ? [NSString stringWithFormat:@"%@\x1f%@", a, t] : nil;
}

static void refresh(void);

static void counted(NSUInteger generation, NSUInteger total, NSDictionary *counts) {
    sgr_busy = NO;
    BOOL changed = ![counts isEqualToDictionary:sgr_counts ?: @{}];
    sgr_counts = counts;
    sgr_generation = generation;
    sgr_counted = total;
    if (changed) [NSNotificationCenter.defaultCenter postNotificationName:SGRAlbumPlayCountsDidChangeNotification object:nil];
    if (sgr_again) {
        sgr_again = NO;
        refresh();
    }
}

static void refresh(void) {
    if (sgr_busy) {
        sgr_again = YES;
        return;
    }
    sgr_busy = YES;
    SGPlayLog *log = SGListeningLog();
    [log loadWithCompletion:^{
        // A failed load has no complete history to count.
        if (log.loadError) {
            counted(log.playsGeneration, 0, @{});
            return;
        }
        NSUInteger generation = log.playsGeneration;
        BOOL grew = generation == sgr_generation;
        NSUInteger from = grew ? sgr_counted : 0;
        NSArray<SGPlay *> *fresh = [log playsFromIndex:from];
        NSUInteger total = from + fresh.count;
        NSDictionary *base = grew ? sgr_counts : @{};
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            NSMutableDictionary<NSString *, NSNumber *> *counts = [base mutableCopy] ?: [NSMutableDictionary dictionary];
            // The same album and title come round again and again; each is folded once.
            NSMutableDictionary<NSString *, NSString *> *keys = [NSMutableDictionary dictionary];
            for (SGPlay *play in fresh) {
                if (!play.album.length || !play.title.length) continue;
                NSString *raw = [NSString stringWithFormat:@"%@\x1f%@", play.album, play.title];
                NSString *key = keys[raw];
                if (!key) {
                    key = keyOf(play.album, play.title) ?: @"";
                    keys[raw] = key;
                }
                if (key.length) counts[key] = @(counts[key].unsignedIntegerValue + 1);
            }
            NSDictionary *done = [counts copy];
            dispatch_async(dispatch_get_main_queue(), ^{ counted(generation, total, done); });
        });
    }];
}

NSUInteger SGRAlbumPlayCount(NSString *album, NSString *title) {
    if (!sgr_started) {
        sgr_started = YES;
        // queue:nil and over to main: the log is the main thread's, but a notification observed on the main
        // queue makes whoever posts it wait (AGENTS.md).
        [NSNotificationCenter.defaultCenter addObserverForName:SGPlayLogDidChangeNotification object:SGListeningLog()
                                                         queue:nil usingBlock:^(NSNotification *note) {
            dispatch_async(dispatch_get_main_queue(), ^{ refresh(); });
        }];
        refresh();
    }
    NSString *key = keyOf(album, title);
    return key ? sgr_counts[key].unsignedIntegerValue : 0;
}

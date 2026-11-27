// Spotify's now playing info passes through with the artist swapped for the current line, and a timer
// sends it again each time the line changes. Spotify itself only ever sees its own dictionary back.
//
// The timer runs only while the sound moves, and wakes once for the next time the line can change: the
// next displayed piece, lead or rest. A setter, player report or arriving lyric can re-arm it.
#import <MediaPlayer/MediaPlayer.h>
#import <stdatomic.h>
#import "Core/SGCore.h"
#import "LockScreenLyrics.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/SpeedPitch.h"
#import "Shared/LyricsTranslation/LyricsTranslation.h"
#import "Headers/SPTPlayer.h"

// About what the lock screen's artist row fits before it cuts the text off.
static const NSUInteger kMaxChars = 30;

// Spotify may set the info from any thread; the timer reads it on the main one.
static NSObject *sg_lock;
static NSDictionary *sg_spotifyInfo;
// The clock can move before the next MediaPlayer setter. Keep its anchor separate
// from the dictionary the Spotify-facing getter must return unchanged.
typedef struct { double seconds, rate; CFAbsoluteTime at; } SGRowClock;
static SGRowClock sg_clock;
static BOOL sg_refreshPending; // under sg_lock; a background setter burst needs one main refresh
static NSString *sg_shownLine;
static _Thread_local BOOL sg_resending;
static dispatch_source_t sg_timer;
static CFAbsoluteTime sg_due;
static void tick(BOOL force);

// Main-thread publication cache, separate from Romanise's worker-only preparation cache.
static SGKaraokeLine *preparedReading(NSString *track, NSArray<SGKaraokeLine *> *lines, NSInteger index) {
    static NSArray *source, *choices;
    static NSArray<SGLyricsPreparedExtras *> *prepared;
    static NSUInteger generation;
    NSString *language = SGLyricsTrackLanguage(track) ?: SGLyricsDetectedLanguage(lines);
    BOOL hangul = SGFlag(SGKeyLyricsPronunciationHangul, NO), hiragana = SGFlag(SGKeyLyricsJapaneseKana, NO);
    NSArray *key = @[track ?: @"", language ?: @"", @(hangul), @(hiragana)];
    if (source != lines || ![choices isEqual:key]) {
        source = lines;
        choices = key;
        prepared = nil;
        NSUInteger job = ++generation;
        SGLyricsPrepareReadingsAsync(lines, [language isEqual:@"ja"], hangul, hiragana,
                                    ^(NSArray<SGLyricsPreparedExtras *> *result) {
            if (job != generation) return;
            prepared = result;
            [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsReadingsDidChangeNotification object:track];
        });
    }
    return prepared ? prepared[index].pronunciation : nil;
}

SGKaraokeLine *SGLyricsShownLine(NSString *track, NSArray<SGKaraokeLine *> *lines, NSInteger index, SGKaraokeLine **under) {
    if (under) *under = nil;
    if (index < 0 || index >= (NSInteger)lines.count) return nil;
    SGKaraokeLine *line = lines[index];
    BOOL leads = NO;
    SGRLyricsReading shown = SGRLyricsReadingShown(&leads);
    if (shown == SGRLyricsReadingNone) return line;
    SGKaraokeLine *reading = line.pronunciation;
    // Use the same preparation as the lyrics view, without entering its worker cache on main.
    if (!reading && shown == SGRLyricsReadingRomanised) {
        reading = preparedReading(track, lines, index);
    }
    if (!SGKaraokeLineText(reading).length) return line;
    if (under) *under = leads ? line : reading;
    return leads ? reading : line;
}

NSString *SGLyricsShownLineTag(void) {
    BOOL leads = NO;
    SGRLyricsReading shown = SGRLyricsReadingShown(&leads);
    if (shown == SGRLyricsReadingNone) return @"";
    return [NSString stringWithFormat:@"p%ld%d%d%d", (long)shown, leads, SGFlag(SGKeyLyricsPronunciationHangul, NO),
            SGFlag(SGKeyLyricsJapaneseKana, NO)];
}

// The successor must have started AND the lead's backing must have finished.
static NSInteger nextBoundary(NSArray<SGKaraokeLine *> *lines, NSInteger index, NSInteger position) {
    SGKaraokeLine *next = index + 1 < (NSInteger)lines.count ? lines[index + 1] : nil;
    if (index < 0) return next ? next.start - position : -1;
    SGKaraokeLine *line = lines[index];
    NSInteger boundary = next ? MAX(next.start, SGKaraokeSungEnd(line)) : NSIntegerMax;
    NSInteger rest = line.end + SGKaraokeBreakMs + 1;
    NSInteger returnAt = next ? next.start - SGKaraokeBreakMs : NSIntegerMax;
    if (rest < returnAt && position < returnAt)
        boundary = MIN(boundary, position < rest ? rest : returnAt);
    return boundary == NSIntegerMax ? -1 : boundary - position;
}

extern NSNotificationName const SGKaraokeLookupReadyNotification;

static NSString *textOf(NSArray<SGKaraokeWord *> *words) {
    SGKaraokeLine *line = [SGKaraokeLine new];
    line.words = words;
    return SGKaraokeLineText(line);
}

// A line longer than the artist row holds, split into even pieces rather than a full one and a stub.
// Each piece shows from its first word's estimated start.
static NSArray<NSArray<SGKaraokeWord *> *> *piecesOf(SGKaraokeLine *line) {
    NSUInteger length = textOf(line.words).length;
    NSUInteger count = MAX((length + kMaxChars - 1) / kMaxChars, 1);
    NSUInteger target = (length + count - 1) / count;
    NSMutableArray<NSArray<SGKaraokeWord *> *> *pieces = [NSMutableArray array];
    NSMutableArray<SGKaraokeWord *> *piece = [NSMutableArray array];
    NSUInteger pieceLength = 0;
    for (SGKaraokeWord *word in line.words) {
        NSUInteger gap = pieceLength && !word.joined ? 1 : 0;
        NSUInteger withWord = pieceLength ? pieceLength + gap + word.text.length : word.text.length;
        if (pieceLength && (withWord > kMaxChars || (withWord > target && pieces.count + 1 < count))) {
            [pieces addObject:piece];
            piece = [NSMutableArray array];
            withWord = word.text.length;
        }
        [piece addObject:word];
        pieceLength = withWord;
    }
    if (piece.count) [pieces addObject:piece];
    return pieces;
}

// A translation has no word timing, so it is split into even pieces too: at spaces, or between characters for
// text without them (CJK).
static NSArray<NSString *> *translationPieces(NSString *text) {
    if (!text.length) return @[];
    NSUInteger count = MAX((text.length + kMaxChars - 1) / kMaxChars, 1);
    if (count == 1) return @[text];
    BOOL unspaced = SGKaraokeUnspacedScript(text);
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    if (unspaced) {
        [text enumerateSubstringsInRange:NSMakeRange(0, text.length) options:NSStringEnumerationByComposedCharacterSequences
                              usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
            if (substring) [tokens addObject:substring];
        }];
    } else {
        // Split on whitespace rather than by words, so a punctuation mark stays with the word before it.
        NSCharacterSet *spaces = NSCharacterSet.whitespaceAndNewlineCharacterSet;
        for (NSString *token in [text componentsSeparatedByCharactersInSet:spaces]) {
            if (token.length) [tokens addObject:token];
        }
        if (!tokens.count) [tokens addObject:text];
    }
    if (tokens.count <= count) return tokens;
    NSUInteger target = (tokens.count + count - 1) / count;
    NSMutableArray<NSString *> *pieces = [NSMutableArray array];
    NSMutableArray<NSString *> *piece = [NSMutableArray array];
    for (NSString *token in tokens) {
        if (piece.count && piece.count + 1 > target && pieces.count + 1 < count) {
            [pieces addObject:[piece componentsJoinedByString:unspaced ? @"" : @" "]];
            piece = [NSMutableArray array];
        }
        [piece addObject:token];
    }
    if (piece.count) [pieces addObject:[piece componentsJoinedByString:unspaced ? @"" : @" "]];
    return pieces;
}

// Advance the latest player or MediaPlayer anchor, not the time in an older metadata dictionary.
static double elapsedAt(SGRowClock clock, CFAbsoluteTime now) {
    return clock.seconds + clock.rate * (now - clock.at);
}

// nil between lines and for a track without synced lyrics, plain text included. Past a line's end by
// SGKaraokeBreakMs, with the next line at least that far off, the artist comes back. With translations on, a
// line that has one shows it instead. `wait` is in playback seconds; negative waits for an event.
static NSString *lineFor(NSDictionary *info, double elapsed, NSTimeInterval *wait) {
    *wait = -1;
    SPTPlayerState *state = [(id<SPTPlayer>)SGKaraokePlayer() state];
    // The player's track can lag behind the now playing info; its lyrics would then be another song's.
    if (![state.track.trackTitle isEqualToString:info[MPMediaItemPropertyTitle]]) return nil;
    NSString *trackID = SGKaraokePlayingTrack();
    NSArray<SGKaraokeLine *> *lines = SGKaraokeLinesForTrack(trackID);
    if (!lines) {
        SGKaraokeRequestLyrics(trackID);
        return nil;
    }
    // Plain text has no line being sung to show.
    if (SGKaraokeLinesTiming(lines) == SGKaraokeTimingNone) return nil;
    NSInteger position = (NSInteger)(elapsed * 1000) - SGKaraokeDelayMs();
    NSInteger index = SGKaraokeLeadLine(lines, position);
    NSInteger ms = nextBoundary(lines, index, position);
    // A ms on, past the truncation of `position` above.
    if (ms > 0) *wait = (ms + 1) / 1000.0;
    if (index < 0) return nil;
    BOOL nextFarOff = index + 1 == (NSInteger)lines.count || lines[index + 1].start - position > SGKaraokeBreakMs;
    if (position > lines[index].end + SGKaraokeBreakMs && nextFarOff) return nil;
    SGKaraokeLine *current = lines[index];
    BOOL wantTranslation = SGInt(SGKeyLockScreenLyricsLine, SGLockScreenLyricsLineOriginal) == SGLockScreenLyricsLineTranslation;
    // Translations wanted here: asked once a track and language, not every tick. Saved ones are synced first, so
    // a line that has one shows it even when no automatic translation runs.
    static NSString *translatedTrack, *translatedLanguage;
    static NSArray<SGKaraokeLine *> *translatedLines;
    if (wantTranslation) {
        NSString *language = SGLyricsGeminiLanguage();
        // A refined source hands over a new array for the same track: it needs the saved translations too.
        if (![translatedTrack isEqualToString:trackID] || ![translatedLanguage isEqualToString:language] || translatedLines != lines) {
            translatedTrack = trackID;
            translatedLanguage = language;
            translatedLines = lines;
            SGRAutoTranslateWithoutView(trackID, lines, ^BOOL {
                return [trackID isEqualToString:SGKaraokePlayingTrack()]
                    && lines == SGKaraokeLinesForTrack(trackID) && [language isEqual:SGLyricsGeminiLanguage()]
                    && SGInt(SGKeyLockScreenLyricsLine, SGLockScreenLyricsLineOriginal) == SGLockScreenLyricsLineTranslation;
            }, ^{
                sg_shownLine = nil;
                tick(NO);
            });
        }
    } else {
        translatedTrack = nil;
    }
    NSString *shownTranslation = wantTranslation ? SGLyricsShownTranslation(current) : nil;
    if (shownTranslation.length) {
        NSArray<NSString *> *pieces = translationPieces(shownTranslation);
        NSInteger start = current.start, end = MAX(SGKaraokeSungEnd(current), start);
        NSUInteger shownIndex = 0;
        for (NSUInteger i = 0; i < pieces.count; i++) {
            NSInteger boundary = start + (NSInteger)i * (end - start) / (NSInteger)pieces.count;
            if (boundary <= position) shownIndex = i;
            else {
                NSTimeInterval next = (boundary - position + 1) / 1000.0;
                if (*wait < 0 || next < *wait) *wait = next;
                break;
            }
        }
        return pieces[shownIndex];
    }
    // The larger of the line and its pronunciation, as the lyrics show them; the artist row has room for one.
    NSString *shown = nil;
    for (NSArray<SGKaraokeWord *> *piece in piecesOf(SGLyricsShownLine(trackID, lines, index, NULL))) {
        if (!shown || piece.firstObject.start <= position) shown = textOf(piece);
        else {
            NSTimeInterval next = (piece.firstObject.start - position + 1) / 1000.0;
            if (*wait < 0 || next < *wait) *wait = next;
        }
    }
    return shown;
}

// Spotify's info with the line in place of the artist, or its own artist for nil. The clock always moves
// on to `elapsed`: the system takes the elapsed time as now's, so the one Spotify reported a while ago
// would pull the progress bar back.
static NSDictionary *withLine(NSDictionary *info, NSString *line, double elapsed, double rate) {
    NSMutableDictionary *shown = [info mutableCopy];
    if (line) shown[MPMediaItemPropertyArtist] = line;
    shown[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(elapsed);
    if (info[MPNowPlayingInfoPropertyPlaybackRate] || rate != 1)
        shown[MPNowPlayingInfoPropertyPlaybackRate] = @(rate);
    return shown;
}

// Main thread, as everything the timer touches is. Stops the timer, or arms it to look again `wait`
// seconds of the song's time from now; a negative wait leaves it to Spotify's next info.
static void lookIn(NSTimeInterval wait, double rate) {
    if (wait < 0 || rate <= 0) {
        if (sg_timer) dispatch_source_cancel(sg_timer);
        sg_timer = nil;
        return;
    }
    if (!sg_timer) {
        // A strict GCD timer: the main run loop's timers are throttled while the screen is off, and the lines
        // stood still on a locked phone.
        sg_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, DISPATCH_TIMER_STRICT, dispatch_get_main_queue());
        dispatch_source_set_event_handler(sg_timer, ^{
            static int late;
            CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
            if (now - sg_due > 2 && late++ < 5) SGLog(@"%s: ticked %.1f s late", __FILE_NAME__, now - sg_due);
            tick(NO);
        });
        dispatch_resume(sg_timer);
    }
    NSTimeInterval seconds = wait / rate;
    sg_due = CFAbsoluteTimeGetCurrent() + seconds;
    dispatch_source_set_timer(sg_timer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), DISPATCH_TIME_FOREVER, 10 * NSEC_PER_MSEC);
}

static void tick(BOOL force) {
    NSDictionary *info;
    SGRowClock clock;
    @synchronized (sg_lock) {
        info = sg_spotifyInfo;
        clock = sg_clock;
    }
    NSDictionary *shown = info;
    NSString *line = nil;
    NSTimeInterval wait = -1;
    if (info[MPNowPlayingInfoPropertyElapsedPlaybackTime]) {
        double elapsed = elapsedAt(clock, CFAbsoluteTimeGetCurrent());
        line = lineFor(info, elapsed, &wait);
        shown = withLine(info, line, elapsed, clock.rate);
    }
    // A queued setter must restore its latest snapshot even when the line is unchanged
    // (including nil), but refreshing a paused or empty snapshot never starts a timer.
    lookIn(wait, clock.rate);
    if (!force && (line == sg_shownLine || [line isEqualToString:sg_shownLine])) return;
    sg_shownLine = line;
    sg_resending = YES;
    MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = shown;
    sg_resending = NO;
}

// Looks again at once while the sound moves, for something other than the clock that moves the line.
static void lookNow(void) {
    BOOL moving;
    @synchronized (sg_lock) {
        moving = sg_clock.rate > 0 && sg_spotifyInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] != nil;
    }
    if (moving) tick(NO);
}

%hook MPNowPlayingInfoCenter
- (void)setNowPlayingInfo:(NSDictionary *)info {
    if (sg_resending) {
        %orig;
        return;
    }
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    NSNumber *rate = info[MPNowPlayingInfoPropertyPlaybackRate];
    SGRowClock clock = {[info[MPNowPlayingInfoPropertyElapsedPlaybackTime] doubleValue], rate ? rate.doubleValue : 1, now};
    BOOL needsRefresh = !NSThread.isMainThread || !info[MPNowPlayingInfoPropertyElapsedPlaybackTime];
    BOOL enqueueRefresh = NO;
    @synchronized (sg_lock) {
        sg_spotifyInfo = info;
        sg_clock = clock;
        if (needsRefresh && !sg_refreshPending) {
            sg_refreshPending = YES;
            enqueueRefresh = YES;
        }
    }
    // Karaoke's lyrics are main-thread state. Restore the latest snapshot on main even
    // when paused: an older tick may have republished its own snapshot after this setter.
    if (needsRefresh) {
        if (enqueueRefresh) dispatch_async(dispatch_get_main_queue(), ^{
            @synchronized (sg_lock) { sg_refreshPending = NO; }
            tick(YES);
        });
        %orig;
        return;
    }
    double elapsed = clock.seconds;
    NSTimeInterval wait;
    NSString *line = lineFor(info, elapsed, &wait);
    lookIn(wait, clock.rate);
    sg_shownLine = line;
    %orig(withLine(info, line, elapsed, clock.rate));
}

- (NSDictionary *)nowPlayingInfo {
    NSDictionary *info;
    @synchronized (sg_lock) {
        info = sg_spotifyInfo;
    }
    return info ?: %orig;
}
%end

@interface SGLockRowPlayer : NSObject <SGPlayerStateObserver>
@end
@implementation SGLockRowPlayer
- (void)playerStateDidChange:(SPTPlayerState *)state {} // DidReport already ran.
- (void)playerStateDidReport:(SPTPlayerState *)state {
    NSString *title = state.track.trackTitle;
    BOOL paused = state.isPaused;
    SGRowClock clock = {paused ? state.positionAsOfTimestamp : state.position, paused ? 0 : state.playbackSpeed, CFAbsoluteTimeGetCurrent()};
    @synchronized (sg_lock) {
        if (!sg_spotifyInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime]) return;
        if ([title isEqual:sg_spotifyInfo[MPMediaItemPropertyTitle]] && isfinite(clock.seconds) && clock.seconds >= 0 &&
            isfinite(clock.rate) && clock.rate >= 0) sg_clock = clock;
    }
    tick(NO);
}
@end

%ctor {
    if (!SGFlag(SGKeyLockScreenLyrics, NO)) return;
    sg_lock = [NSObject new];
    %init;
    static SGLockRowPlayer *player;
    player = [SGLockRowPlayer new];
    SGAddPlayerStateObserver(player);
    [NSNotificationCenter.defaultCenter addObserverForName:SGPlayerSpeedDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        [player playerStateDidReport:SGPlayerState()];
    }];
    // A translation saved while the player is paused has no tick to pick it up (Shared/LyricsTranslation).
    // Heard on the writing thread and handed to main without waiting (AGENTS.md).
    for (NSNotificationName name in @[SGLyricsTranslationSavedNotification, SGLyricsTranslationsDidChangeNotification]) {
    [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil
                                                usingBlock:^(NSNotification *note) {
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL saved = [note.name isEqual:SGLyricsTranslationSavedNotification];
            NSString *track = saved ? note.object : SGKaraokePlayingTrack();
            if (![track isEqualToString:SGKaraokePlayingTrack()]
                || (saved && ![note.userInfo[@"language"] isEqual:SGLyricsGeminiLanguage()])
                || SGInt(SGKeyLockScreenLyricsLine, SGLockScreenLyricsLineOriginal) != SGLockScreenLyricsLineTranslation) return;
            NSString *language = SGLyricsGeminiLanguage();
            NSArray *lines = SGKaraokeLinesForTrack(track);
            SGLyricsLoadTranslation(track, language, lines, ^BOOL {
                return [track isEqual:SGKaraokePlayingTrack()] && [language isEqual:SGLyricsGeminiLanguage()]
                    && lines == SGKaraokeLinesForTrack(track)
                    && SGInt(SGKeyLockScreenLyricsLine, SGLockScreenLyricsLineOriginal) == SGLockScreenLyricsLineTranslation;
            }, ^{
                sg_shownLine = nil;
                tick(NO);
            });
        });
    }];
    }
    // Lines kept for a track, or replaced by better timed ones, can change the line at once.
    for (NSNotificationName name in @[SGKaraokeLookupReadyNotification, SGKaraokeLinesKeptNotification, SGLyricsReadingsDidChangeNotification,
                                      SGLyricsLanguageDidChangeNotification, SGLyricsOffsetsDidChangeNotification]) {
    [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
        if (!note.object || [note.object isEqual:SGKaraokePlayingTrack()]) tick(NO);
    }];
    }
    // The lyrics' delay applies at once, and moves the next change. Every write in the app posts this, so it is
    // compared on the writing thread and handed to main without waiting only when it moved (AGENTS.md).
    static _Atomic NSInteger delay;
    atomic_store(&delay, SGKaraokeDelayMs());
    static _Atomic NSInteger rowMode;
    atomic_store(&rowMode, SGInt(SGKeyLockScreenLyricsLine, SGLockScreenLyricsLineOriginal));
    // So does the lyrics' choice of pronunciation (SGLyricsShownLine), paused or not.
    static NSString *shownTag;
    shownTag = SGLyricsShownLineTag();
    [NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *note) {
        SGPrefsChanged();
        NSString *tag = SGLyricsShownLineTag();
        BOOL retagged;
        @synchronized (sg_lock) {
            retagged = ![tag isEqualToString:shownTag];
            shownTag = tag;
        }
        NSInteger now = SGKaraokeDelayMs();
        BOOL moved = atomic_exchange(&delay, now) != now;
        NSInteger mode = SGInt(SGKeyLockScreenLyricsLine, SGLockScreenLyricsLineOriginal);
        if (atomic_exchange(&rowMode, mode) != mode || retagged) dispatch_async(dispatch_get_main_queue(), ^{ tick(NO); });
        else if (moved) dispatch_async(dispatch_get_main_queue(), ^{ lookNow(); });
    }];
    // The timer waits for Spotify to report a playing track; nothing before that has a line to show.
    SGLog(@"lock screen lyrics: on");
}

// Clear Downloaded Covers and Artist Photos, through the production store, catalog and settings row. Everything runs
// in a sandbox: Caches is redirected to a temporary folder, the catalog answers through an offline URL protocol and
// the clip transfers are fakes. No network, and no file outside the sandbox is read or written.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <CommonCrypto/CommonDigest.h>
#import "../harness-fail.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Shared/AnimatedArtwork/SGMotionTicket.h"
#import "Shared/AnimatedArtwork/SGMotionCatalog.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"

#define CHECK HARNESS_CHECK
#import "Shared/SpotifyMetadata/SGSpotifyMetadata.h"
#import "../motion/no-recording-lookup.h"

BOOL SGMotionAppleMusicOn(void) { return YES; }
dispatch_block_t SGSpotifyMetadataRequestAllowConstrained(NSString *path, NSData *body, BOOL allow, SGSpotifyMetadataReply done) {
    CHECK(NO); return ^{};
}

#pragma mark - stubs for what the production files take from the rest of the mod

BOOL SGFlag(NSString *key, BOOL fallback) { return fallback; }
NSString *SGL(NSString *key, NSString *english) { return english; }
@implementation SGModRow
@end
SGModRow *SGStatActionRow(NSString *title, NSString *subtitle, NSString *(^value)(void), void (^action)(void)) {
    SGModRow *row = [SGModRow new];
    row.title = title; row.subtitle = subtitle; row.value = value; row.action = action;
    return row;
}
@interface Presenter : UIViewController
@property (nonatomic, strong) UIAlertController *alert;
@end
@implementation Presenter
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion {
    self.alert = (UIAlertController *)controller;
}
@end
static Presenter *presenter;
static NSString *informedTitle, *informedMessage;
UIViewController *SGTopController(void) { return presenter; }
void SGPresentInformation(UIViewController *over, NSString *title, NSString *message) {
    informedTitle = title; informedMessage = message;
}

#pragma mark - sandbox

static NSURL *sandbox, *motion, *support, *answers;
static NSFileManager *files(void) { return NSFileManager.defaultManager; }

@interface NSFileManager (ClearCheck)
- (NSArray *)testURLsForDirectory:(NSSearchPathDirectory)directory inDomains:(NSSearchPathDomainMask)domains;
@end
@implementation NSFileManager (ClearCheck)
- (NSArray *)testURLsForDirectory:(NSSearchPathDirectory)directory inDomains:(NSSearchPathDomainMask)domains {
    return @[directory == NSCachesDirectory ? [sandbox URLByAppendingPathComponent:@"Caches" isDirectory:YES] : support];
}
@end

// The answers file read while `watchReads` is set (main thread reads are the ones that stall the interface).
static BOOL watchReads;
static NSUInteger answerReads;
@interface NSDictionary (ClearCheck)
+ (NSDictionary *)testDictionaryWithContentsOfURL:(NSURL *)url;
@end
@implementation NSDictionary (ClearCheck)
+ (NSDictionary *)testDictionaryWithContentsOfURL:(NSURL *)url {
    if (watchReads && [url.path isEqual:answers.path]) answerReads++;
    return [self testDictionaryWithContentsOfURL:url];
}
@end

#import "../harness-wait.h"
#define waitFor(...) HARNESS_CHECK(HarnessRunUntil(__VA_ARGS__))

static void put(NSURL *file, NSString *text) {
    CHECK([files() createDirectoryAtURL:file.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil]);
    CHECK([text writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:nil]);
}

// Every file under `directory` with its bytes, by path below it.
static NSDictionary<NSString *, NSData *> *snapshot(NSURL *directory) {
    NSMutableDictionary *all = [NSMutableDictionary dictionary];
    for (NSURL *file in [files() enumeratorAtURL:directory includingPropertiesForKeys:nil options:0 errorHandler:nil]) {
        BOOL isDirectory = NO;
        [files() fileExistsAtPath:file.path isDirectory:&isDirectory];
        if (!isDirectory) all[[file.path substringFromIndex:directory.path.length]] = [NSData dataWithContentsOfURL:file];
    }
    return all;
}

// The clips the store owns: a 40 character hash then .mp4.
static NSArray<NSString *> *ownedClipNames(void) {
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *name in [files() contentsOfDirectoryAtPath:motion.path error:nil]) {
        NSRegularExpression *owned = [NSRegularExpression regularExpressionWithPattern:@"^[0-9a-f]{40}\\.mp4$" options:0 error:nil];
        if ([owned numberOfMatchesInString:name options:0 range:NSMakeRange(0, name.length)]) [names addObject:name];
    }
    return [names sortedArrayUsingSelector:@selector(compare:)];
}
static unsigned long long sizeOf(NSURL *file) {
    return [[files() attributesOfItemAtPath:file.path error:nil][NSFileSize] unsignedLongLongValue];
}
static NSString *shown(unsigned long long bytes) {
    return [NSByteCountFormatter stringFromByteCount:(long long)bytes countStyle:NSByteCountFormatterCountStyleFile];
}

#pragma mark - fake clip transfers

@interface FakeTask : NSObject
@property (nonatomic) int64_t countOfBytesExpectedToReceive, countOfBytesReceived;
- (void)resume;
- (void)cancel;
@end
@implementation FakeTask
- (void)resume {}
- (void)cancel {}
@end
@interface FakeSession : NSObject
@property (nonatomic, strong) id<NSURLSessionDataDelegate> delegate;
@property (nonatomic, strong) FakeTask *task;
@property (nonatomic, strong) NSURL *url;
@end
static NSMutableArray<FakeSession *> *sessions;
@implementation FakeSession
- (id)dataTaskWithRequest:(NSURLRequest *)request {
    self.url = request.URL;
    self.task = [FakeTask new];
    return self.task;
}
- (void)finishTasksAndInvalidate {}
- (void)receive:(NSUInteger)bytes {
    NSDictionary *headers = @{@"Content-Length": @(bytes).stringValue};
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.url statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:headers];
    [self.delegate URLSession:(id)self dataTask:(id)self.task didReceiveResponse:response completionHandler:^(NSURLSessionResponseDisposition d) {}];
    [self.delegate URLSession:(id)self dataTask:(id)self.task didReceiveData:[NSMutableData dataWithLength:bytes]];
}
// The transport calls its delegate off main; the store's reply comes back to main before this returns.
- (void)finish {
    __block BOOL finished = NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        [self.delegate URLSession:(id)self task:(id)self.task didCompleteWithError:nil];
        dispatch_async(dispatch_get_main_queue(), ^{ finished = YES; });
    });
    waitFor(^BOOL { return finished; });
    self.delegate = nil;   // a finished session lets its delegate go, as NSURLSession does
}
@end
static id sessionFactory(id self, SEL cmd, id configuration, id delegate, id queue) {
    FakeSession *session = [FakeSession new];
    session.delegate = delegate;
    [sessions addObject:session];
    return session;
}
static FakeSession *sessionAfter(NSUInteger count) {
    waitFor(^BOOL { return sessions.count > count; });
    return sessions.lastObject;
}

#pragma mark - offline catalog

static NSString *edition = @"first";
static BOOL blue;
static NSString *holdTerm;                // a search whose term holds this waits in `held`
static NSArray<NSString *> *holdAddresses; // so does a request whose address holds one of these
static NSUInteger albumSearches, artistSearches, logoFetches;   // main
static NSUInteger discographyFetches, resourceFetches, photoFetches, playlistFetches;
static NSMutableArray<dispatch_block_t> *held;                  // main
static NSData *redLogo, *blueLogo;

@interface CatalogProtocol : NSURLProtocol
@end
@implementation CatalogProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return YES; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSURL *url = self.request.URL;
        NSString *term = nil;
        NSData *data;
        NSString *artistId = nil;
        if ([url.host isEqual:@"amp-api.music.apple.com"] && [url.path hasSuffix:@"/albums"]) {
            discographyFetches++;
            data = [NSJSONSerialization dataWithJSONObject:@{@"data": @[@{@"attributes": @{@"name": @"First Album"}},
                                                                         @{@"attributes": @{@"name": @"Second Album"}}]} options:0 error:nil];
        } else if ([url.host isEqual:@"amp-api.music.apple.com"] && [url.path containsString:@"/artists/"]) {
            resourceFetches++;
            artistId = url.lastPathComponent;
            data = [NSJSONSerialization dataWithJSONObject:@{@"data": @[@{@"id": artistId, @"attributes": @{@"editorialVideo":
                @{@"motionArtistSquare1x1": @{@"video": [NSString stringWithFormat:@"https://fixture.invalid/%@/artist-%@/master.m3u8", edition, artistId]}}}}]}
                options:0 error:nil];
        } else if ([url.host isEqual:@"amp-api.music.apple.com"]) {
            NSURLComponents *parts = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
            NSMutableDictionary *query = [NSMutableDictionary dictionary];
            for (NSURLQueryItem *item in parts.queryItems) query[item.name] = item.value;
            BOOL artist = [query[@"types"] isEqual:@"artists"];
            term = query[@"term"];
            artist ? artistSearches++ : albumSearches++;
            NSString *album = artist ? nil : [term substringFromIndex:@"Artist ".length];
            NSString *identifier = [@"id-" stringByAppendingString:[term.lowercaseString stringByReplacingOccurrencesOfString:@" " withString:@"-"]];
            NSDictionary *attributes = artist
                ? @{@"name": term, @"editorialArtwork": @{@"musicContentColorLogoTrimmed":
                    @{@"url": @"https://fixture.invalid/logo.png", @"width": @1024, @"height": @1024}},
                    @"artwork": @{@"url": [NSString stringWithFormat:@"https://fixture.invalid/photo/%@/{w}x{h}bb.jpg", identifier], @"width": @1000, @"height": @1000}}
                : @{@"name": album, @"artistName": @"Artist", @"editorialVideo": @{@"motionTallVideo3x4": @{@"video":
                    [NSString stringWithFormat:@"https://fixture.invalid/%@/%@/master.m3u8", edition,
                        [album stringByReplacingOccurrencesOfString:@" " withString:@"-"]]}}};
            NSMutableDictionary *record = [@{@"attributes": attributes} mutableCopy];
            if (artist) record[@"id"] = identifier;
            data = [NSJSONSerialization dataWithJSONObject:
                @{@"results": @{artist ? @"artists" : @"albums": @{@"data": @[record]}}} options:0 error:nil];
        } else if ([url.path hasSuffix:@"master.m3u8"]) {
            playlistFetches++;
            data = [@"#EXTM3U\n#EXT-X-STREAM-INF:RESOLUTION=720x960\nmedia.m3u8" dataUsingEncoding:NSUTF8StringEncoding];
        } else if ([url.path hasSuffix:@"media.m3u8"]) {
            playlistFetches++;
            data = [@"#EXTM3U\nclip.mp4" dataUsingEncoding:NSUTF8StringEncoding];
        } else if ([url.path hasPrefix:@"/photo/"]) {
            photoFetches++;
            data = redLogo;
        } else {
            CHECK([url.path isEqual:@"/logo.png"]);
            logoFetches++;
            data = blue ? blueLogo : redLogo;
        }
        dispatch_block_t reply = ^{
            NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:nil];
            [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
            [self.client URLProtocol:self didLoadData:data];
            [self.client URLProtocolDidFinishLoading:self];
        };
        BOOL holds = holdTerm && [term containsString:holdTerm];
        for (NSString *address in holdAddresses) if ([url.absoluteString containsString:address]) holds = YES;
        if (holds) [held addObject:[reply copy]];
        else reply();
    });
}
- (void)stopLoading {}
@end

static NSData *makeLogo(BOOL red) {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1; format.opaque = YES;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(64, 64) format:format]
        PNGDataWithActions:^(UIGraphicsImageRendererContext *context) {
            [(red ? UIColor.redColor : UIColor.blueColor) setFill];
            UIRectFill(CGRectMake(0, 0, 64, 64));
        }];
}
static BOOL isBlue(UIImage *image) {
    uint8_t pixel[4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixel, 1, 1, 8, 4, space, kCGImageAlphaPremultipliedLast);
    CGContextDrawImage(context, CGRectMake(0, 0, 1, 1), image.CGImage);
    CGContextRelease(context); CGColorSpaceRelease(space);
    return pixel[2] > 240 && pixel[0] < 10;
}

#pragma mark - actions

// Whether the album got its clip through the production request, finishing the fake transfer when one starts.
// Only the answer is returned: the file itself is not held, so its lease ends with the call.
// *remote is the address the transfer asked for, nil when the clip was already on disk.
static BOOL album(NSString *name, NSString **remote) {
    __block BOOL result = NO;
    __block BOOL finished = NO;
    NSUInteger before = sessions.count;
    SGMotionAlbumCover(@"Artist", name, 720, ^(NSURL *file) { result = file != nil; finished = YES; });
    waitFor(^BOOL { return finished || sessions.count > before; });
    if (remote) *remote = nil;
    if (!finished) {
        FakeSession *transfer = sessions.lastObject;
        if (remote) *remote = transfer.url.absoluteString;
        [transfer receive:100];
        [transfer finish];
        waitFor(^BOOL { return finished; });
    }
    return result;
}
static UIImage *logo(NSString *artist) {
    __block BOOL finished = NO;
    __block UIImage *value;
    SGMotionArtistLogo(artist, 64, ^(UIImage *image) { value = image; finished = YES; });
    waitFor(^BOOL { return finished; });
    return value;
}
static void makeClip(NSString *key, NSUInteger bytes, NSURL *__strong *keep) {
    __block BOOL done = NO;
    NSURL *file = SGMotionMadeFile(key);
    SGMotionMakeFile(file, ^BOOL { return [[NSMutableData dataWithLength:bytes] writeToURL:file atomically:YES]; },
                     ^(BOOL ok) { CHECK(ok); dispatch_async(dispatch_get_main_queue(), ^{ done = YES; }); });
    waitFor(^BOOL { return done; });
    if (keep) *keep = file;
}
// Waits until the store and the answers file have run everything queued before this call.
static unsigned long long cacheBytes(void) {
    __block BOOL finished = NO;
    __block unsigned long long total = 0;
    SGMotionCacheBytes(^(uint64_t bytes) { total = bytes; finished = YES; });
    waitFor(^BOOL { return finished; });
    return total;
}
static void (^handlerOf(UIAlertAction *action))(UIAlertAction *) { return [action valueForKey:@"handler"]; }


// The artist pipeline (photo and motion), with the clear arriving while a reply is held.
static NSArray<NSString *> *artistTitles(void) { return @[@"First Album", @"Second Album"]; }
static NSArray<NSNumber *> *artistTraffic(void) {
    return @[@(discographyFetches), @(resourceFetches), @(photoFetches), @(sessions.count)];
}
typedef struct { SGMotionArtistArtworkOutcome outcome; BOOL image, file; } ArtistResult;
static ArtistResult artistRun(NSString *artist, void (^whileAsked)(void)) {
    __block ArtistResult result;
    __block BOOL finished = NO;
    NSUInteger before = sessions.count;
    SGMotionArtistArtwork(artist, artistTitles(), 64, YES, YES, ^(UIImage *photo, NSURL *file, SGMotionArtistArtworkOutcome outcome) {
        result = (ArtistResult){outcome, photo != nil, file != nil};
        finished = YES;
    });
    if (whileAsked) whileAsked();
    if (!finished) waitFor(^BOOL { return finished || sessions.count > before; });
    if (!finished) {   // the clip transfer of a request that is allowed to download
        FakeSession *transfer = sessions.lastObject;
        [transfer receive:100];
        [transfer finish];
        waitFor(^BOOL { return finished; });
    }
    return result;
}
// `held` is what the request must be waiting on when the clear comes; the replies are let go after it.
// trafficAfterClear is what the clear left, which the held replies must not add to.
static NSArray<NSNumber *> *trafficAfterClear;
static ArtistResult artistClearedWhile(NSString *artist, NSString *term, NSArray<NSString *> *addresses, NSUInteger waiting) {
    holdTerm = term; holdAddresses = addresses;
    [held removeAllObjects];
    return artistRun(artist, ^{
        waitFor(^BOOL { return held.count == waiting; });
        __block BOOL cleared = NO;
        SGMotionCacheClear(^(BOOL complete) { CHECK(complete); cleared = YES; });
        waitFor(^BOOL { return cleared; });
        trafficAfterClear = artistTraffic();
        holdTerm = nil; holdAddresses = nil;
        NSArray *replies = [held copy];
        [held removeAllObjects];
        for (dispatch_block_t reply in replies) reply();
    });
}

// The alert the row raises, whose Clear button runs the clear.
static UIAlertController *tapRow(SGModRow *row) {
    presenter.alert = nil;
    row.action();
    CHECK(presenter.alert);
    return presenter.alert;
}
static void tapClear(SGModRow *row) {
    UIAlertController *alert = tapRow(row);
    UIAlertAction *clear = alert.actions[1];
    CHECK(handlerOf(clear));
    handlerOf(clear)(clear);
}
// Marks a file immutable, so that removing it fails.
static BOOL locked(NSURL *file, BOOL on) {
    return [file setResourceValue:@(on) forKey:NSURLIsUserImmutableKey error:nil];
}
static NSString *detail(SGModRow *row) { return row.value(); }

int main(void) {
    @autoreleasepool {
        sandbox = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
        CHECK([sandbox.path hasPrefix:NSTemporaryDirectory()]);
        NSURL *caches = [sandbox URLByAppendingPathComponent:@"Caches" isDirectory:YES];
        motion = [caches URLByAppendingPathComponent:@"Retrine/Motion" isDirectory:YES];
        support = [sandbox URLByAppendingPathComponent:@"Application Support" isDirectory:YES];
        answers = [motion URLByAppendingPathComponent:@"album answers.plist"];
        method_exchangeImplementations(class_getInstanceMethod(NSFileManager.class, @selector(URLsForDirectory:inDomains:)),
                                       class_getInstanceMethod(NSFileManager.class, @selector(testURLsForDirectory:inDomains:)));
        CHECK([[files() URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject isEqual:caches]);
        method_exchangeImplementations(class_getClassMethod(NSDictionary.class, @selector(dictionaryWithContentsOfURL:)),
                                       class_getClassMethod(NSDictionary.class, @selector(testDictionaryWithContentsOfURL:)));
        presenter = [Presenter new];
        sessions = [NSMutableArray array];
        held = [NSMutableArray array];
        Method factory = class_getClassMethod(NSURLSession.class, @selector(sessionWithConfiguration:delegate:delegateQueue:));
        method_setImplementation(factory, (IMP)sessionFactory);
        redLogo = makeLogo(YES); blueLogo = makeLogo(NO);

        // What the clear must never touch, next to and away from the cache.
        put([support URLByAppendingPathComponent:@"Retrine/Local file covers/cover.jpg"], @"a chosen cover");
        put([support URLByAppendingPathComponent:@"Retrine/Songs/a.flac"], @"a song");
        put([support URLByAppendingPathComponent:@"Retrine/Edits/edits.json"], @"{\"title\": \"edited\"}");
        put([support URLByAppendingPathComponent:@"Retrine/Lyrics/a.lrc"], @"[00:01.00]imported");
        put([caches URLByAppendingPathComponent:@"Retrine/Other/kept.bin"], @"another cache");
        put([motion URLByAppendingPathComponent:@"notes.txt"], @"not a clip");
        put([motion URLByAppendingPathComponent:@"hand.mp4"], @"a video that is not the store's");
        NSDictionary *protectedFiles = snapshot(support), *protectedOther = snapshot([caches URLByAppendingPathComponent:@"Retrine/Other"]);
        NSData *notes = [NSData dataWithContentsOfURL:[motion URLByAppendingPathComponent:@"notes.txt"]];
        NSData *hand = [NSData dataWithContentsOfURL:[motion URLByAppendingPathComponent:@"hand.mp4"]];
        void (^checkProtected)(void) = ^{
            CHECK([snapshot(support) isEqual:protectedFiles]);
            CHECK([snapshot([caches URLByAppendingPathComponent:@"Retrine/Other"]) isEqual:protectedOther]);
            CHECK([[NSData dataWithContentsOfURL:[motion URLByAppendingPathComponent:@"notes.txt"]] isEqual:notes]);
            CHECK([[NSData dataWithContentsOfURL:[motion URLByAppendingPathComponent:@"hand.mp4"]] isEqual:hand]);
        };

        NSData *token = [NSJSONSerialization dataWithJSONObject:@{@"exp": @4102444800} options:0 error:nil];
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        id priorToken = [defaults objectForKey:@"spotifyglass.motion.token"];
        [defaults setObject:[NSString stringWithFormat:@"e30.%@.test", [token base64EncodedStringWithOptions:0]] forKey:@"spotifyglass.motion.token"];
        CHECK([NSURLProtocol registerClass:CatalogProtocol.class]);

        // A clear before anything was looked up: it does not read the answers file first, and what was saved does not come back.
        CHECK(([@{@"album\n5\nartist\nsaved": @{@"url": @"https://fixture.invalid/saved/clip.mp4", @"at": NSDate.date}} writeToURL:answers atomically:YES]));
        __block BOOL firstDone = NO, firstComplete = NO;
        watchReads = YES;
        SGMotionCacheClear(^(BOOL complete) { firstComplete = complete; firstDone = YES; });
        waitFor(^BOOL { return firstDone; });
        watchReads = NO;
        CHECK(firstComplete && ![files() fileExistsAtPath:answers.path] && answerReads == 0);   // and no read of what it removes
        NSString *remote;
        CHECK(album(@"Saved", &remote) && [remote isEqual:@"https://fixture.invalid/first/Saved/clip.mp4"] && albumSearches == 1);
        waitFor(^BOOL { return [NSDictionary dictionaryWithContentsOfURL:answers][@"album\n5\nartist\nsaved"] != nil; });

        // Owned files: three more clips (one held by a consumer), the Saved clip and the saved answers.
        NSURL *leased = nil;
        makeClip(@"leased", 1000, &leased);
        @autoreleasepool { makeClip(@"second", 2000, NULL); makeClip(@"third", 3000, NULL); }
        CHECK(cacheBytes() == 6000 + 100 + sizeOf(answers));   // the release of the two others has run before the sum did
        CHECK(ownedClipNames().count == 4);

        // Warm the memory: an answer fetched, an artist image.
        CHECK(album(@"Fresh", &remote) && [remote isEqual:@"https://fixture.invalid/first/Fresh/clip.mp4"] && albumSearches == 2);
        CHECK(album(@"Fresh", &remote) && !remote && albumSearches == 2);
        CHECK(!isBlue(logo(@"Singer")) && artistSearches == 1 && logoFetches == 1);
        CHECK(!isBlue(logo(@"Singer")) && artistSearches == 1 && logoFetches == 1);
        waitFor(^BOOL { return [NSDictionary dictionaryWithContentsOfURL:answers][@"album\n5\nartist\nfresh"] != nil; });

        // The row names the size on disk.
        SGModRow *row = SGArtworkCacheRow();
        CHECK([row.title isEqual:@"Clear Downloaded Covers and Artist Photos"]);
        CHECK([detail(row) isEqual:@"Calculating…"]);
        unsigned long long expected = 6000 + 2 * 100 + sizeOf(answers);
        waitFor(^BOOL { return ![detail(row) isEqual:@"Calculating…"]; });
        CHECK([detail(row) isEqual:shown(expected)]);

        // Cancel changes nothing.
        UIAlertController *alert = tapRow(row);
        CHECK([alert.title isEqual:@"Clear Downloaded Covers and Artist Photos?"]);
        CHECK([alert.message isEqual:@"Animated covers and artist photos are fetched again when needed. Your songs are not touched."]);
        CHECK(alert.actions.count == 2);
        CHECK([alert.actions[0].title isEqual:@"Cancel"] && alert.actions[0].style == UIAlertActionStyleCancel);
        CHECK([alert.actions[1].title isEqual:@"Clear"] && alert.actions[1].style == UIAlertActionStyleDestructive);
        NSDictionary *beforeCancel = snapshot(motion);
        if (handlerOf(alert.actions[0])) handlerOf(alert.actions[0])(alert.actions[0]);
        CHECK([snapshot(motion) isEqual:beforeCancel]);
        CHECK([detail(row) isEqual:shown(expected)]);
        CHECK(album(@"Fresh", &remote) && !remote && albumSearches == 2 && !informedMessage);

        // Work started before the clear: a transfer, a lookup and a file queued behind another.
        NSUInteger count = sessions.count;
        __block BOOL transferDone = NO;
        __block NSURL *transferFile = leased;
        NSURL *inflight = [NSURL URLWithString:@"https://fixture.invalid/inflight.mp4"];
        SGMotionRequestFile(inflight, ^(NSURL *file) { transferFile = file; transferDone = YES; });
        FakeSession *transfer = sessionAfter(count);
        [transfer receive:100];
        holdTerm = @"Slow";
        __block BOOL slowDone = NO;
        __block NSURL *slowFile = leased;
        SGMotionAlbumCover(@"Artist", @"Slow", 720, ^(NSURL *file) { slowFile = file; slowDone = YES; });
        waitFor(^BOOL { return held.count == 1; });
        edition = @"second";   // what the old lookup was told differs from what a new one will be
        dispatch_semaphore_t gate = dispatch_semaphore_create(0);
        dispatch_semaphore_t entered = dispatch_semaphore_create(0);
        __block BOOL queuedDone = NO, queuedMade = YES;
        SGMotionMakeFile(SGMotionMadeFile(@"blocker"), ^BOOL {
            dispatch_semaphore_signal(entered);
            return dispatch_semaphore_wait(gate, dispatch_time(DISPATCH_TIME_NOW, HarnessWaitSeconds * NSEC_PER_SEC)) == 0;
        }, ^(BOOL ok) {});
        CHECK(dispatch_semaphore_wait(entered, dispatch_time(DISPATCH_TIME_NOW, HarnessWaitSeconds * NSEC_PER_SEC)) == 0);
        NSURL *queued = SGMotionMadeFile(@"queued before the clear");
        SGMotionMakeFile(queued, ^BOOL { return [@"x" writeToURL:queued atomically:YES encoding:NSUTF8StringEncoding error:nil]; },
                         ^(BOOL ok) { queuedMade = ok; dispatch_async(dispatch_get_main_queue(), ^{ queuedDone = YES; }); });

        // Clear.
        tapClear(row);
        CHECK([detail(row) isEqual:@"Clearing…"]);
        dispatch_semaphore_signal(gate);
        waitFor(^BOOL { return ![detail(row) isEqual:@"Clearing…"] && ![detail(row) isEqual:@"Calculating…"]; });
        CHECK(!informedMessage);
        waitFor(^BOOL { return queuedDone; });
        CHECK(!queuedMade && ![files() fileExistsAtPath:[SGMotionMadeFile(@"queued before the clear") path]]);
        CHECK(transferDone && !transferFile);   // its consumer was answered at the clear
        [transfer finish];                      // a completion from before the clear
        CHECK(cacheBytes() == 1000);
        CHECK(([ownedClipNames() isEqual:@[leased.lastPathComponent]]) && [files() fileExistsAtPath:leased.path]);   // a held clip stays
        CHECK(![files() fileExistsAtPath:answers.path]);
        checkProtected();
        CHECK([detail(row) isEqual:shown(1000)]);

        // The same album asked for after the clear searches again, not joining the old lookup, and the old
        // lookup, finishing last, neither keeps its answer nor starts a download.
        __block BOOL againDone = NO, againGot = NO;
        SGMotionAlbumCover(@"Artist", @"Slow", 720, ^(NSURL *file) { againGot = file != nil; againDone = YES; });
        waitFor(^BOOL { return held.count == 2; });
        holdTerm = nil;
        dispatch_block_t oldReply = held[0], newReply = held[1];
        [held removeAllObjects];
        newReply();
        FakeSession *again = sessionAfter(count + 1);
        CHECK([again.url.absoluteString isEqual:@"https://fixture.invalid/second/Slow/clip.mp4"]);
        [again receive:100];
        [again finish];
        waitFor(^BOOL { return againDone; });
        CHECK(againGot);
        oldReply();
        waitFor(^BOOL { return slowDone; });
        CHECK(!slowFile && sessions.count == count + 2);
        cacheBytes();   // the answers file has written everything queued
        CHECK([[NSDictionary dictionaryWithContentsOfURL:answers][@"album\n5\nartist\nslow"][@"url"] isEqual:@"https://fixture.invalid/second/Slow/clip.mp4"]);

        // The other answers and the artist image are fetched again too.
        blue = YES;
        CHECK(album(@"Saved", &remote) && [remote isEqual:@"https://fixture.invalid/second/Saved/clip.mp4"] && albumSearches == 5);
        CHECK(album(@"Fresh", &remote) && [remote isEqual:@"https://fixture.invalid/second/Fresh/clip.mp4"] && albumSearches == 6);
        CHECK(album(@"Slow", &remote) && !remote && albumSearches == 6);
        CHECK(isBlue(logo(@"Singer")) && artistSearches == 2 && logoFetches == 2);

        // The artist photo and motion pipeline: a clear that arrives while any step is pending leaves nothing cached and
        // starts no download afterwards, and a request made after it fetches every step again.
        struct { NSString *artist, *term; NSArray<NSString *> *addresses; NSUInteger waiting; } stale[] = {
            {@"Early Painter", @"Early", nil, 1},                                    // the artist search
            {@"Album Painter", nil, @[@"id-album-painter/albums"], 1},               // the discography
            {@"Late Painter", nil, @[@"id-late-painter?extend"], 1},                 // the video resource
            {@"Photo Painter", nil, @[@"/photo/id-photo-painter/", @"artist-id-photo-painter/master"], 2},   // photo and video
        };
        for (size_t i = 0; i < sizeof(stale) / sizeof(stale[0]); i++) {
            NSUInteger transfers = sessions.count;
            ArtistResult old = artistClearedWhile(stale[i].artist, stale[i].term, stale[i].addresses, stale[i].waiting);
            NSArray<NSNumber *> *left = trafficAfterClear;
            CHECK(old.outcome == (i == 3 ? SGMotionArtistArtworkFinished : SGMotionArtistArtworkMetadataFailed));
            CHECK(!old.file && old.image == (i == 3));   // the photo already asked for still reaches its own request
            CHECK([artistTraffic() isEqual:left] && sessions.count == transfers);
            ArtistResult next = artistRun(stale[i].artist, nil);
            CHECK(next.outcome == SGMotionArtistArtworkFinished && next.image && next.file);
            NSArray<NSNumber *> *now = artistTraffic();
            for (NSUInteger step = 0; step < now.count; step++) CHECK(now[step].unsignedIntegerValue == left[step].unsignedIntegerValue + 1);
        }

        // A clip that cannot be removed is said, and the others still go.
        @autoreleasepool { makeClip(@"fourth", 400, NULL); makeClip(@"fifth", 500, NULL); }
        cacheBytes();
        NSURL *stuck = SGMotionMadeFile(@"fourth");
        CHECK(locked(stuck, YES));
        SGModRow *failing = SGArtworkCacheRow();
        informedTitle = informedMessage = nil;
        tapClear(failing);
        waitFor(^BOOL { return informedMessage != nil; });
        CHECK([informedTitle isEqual:@"Clear Downloaded Covers and Artist Photos"]);
        CHECK([informedMessage isEqual:@"Some files couldn't be removed."]);
        CHECK(([ownedClipNames() isEqualToArray:[@[leased.lastPathComponent, stuck.lastPathComponent] sortedArrayUsingSelector:@selector(compare:)]]));
        CHECK(![files() fileExistsAtPath:answers.path]);
        CHECK(locked(stuck, NO));

        // So is an answers file that cannot be removed.
        waitFor(^BOOL { return ![detail(failing) isEqual:@"Calculating…"] && ![detail(failing) isEqual:@"Clearing…"]; });
        CHECK(album(@"Saved", &remote) && albumSearches == 7);
        waitFor(^BOOL { return [files() fileExistsAtPath:answers.path]; });
        cacheBytes();
        CHECK(locked(answers, YES));
        informedTitle = informedMessage = nil;
        tapClear(failing);
        waitFor(^BOOL { return informedMessage != nil; });
        CHECK([informedMessage isEqual:@"Some files couldn't be removed."]);
        CHECK([files() fileExistsAtPath:answers.path] && ([ownedClipNames() isEqual:@[leased.lastPathComponent]]));
        CHECK(locked(answers, NO));

        // And once nothing stands in the way, nothing is reported.
        waitFor(^BOOL { return ![detail(failing) isEqual:@"Calculating…"] && ![detail(failing) isEqual:@"Clearing…"]; });
        informedTitle = informedMessage = nil;
        tapClear(failing);
        waitFor(^BOOL { return ![files() fileExistsAtPath:answers.path]; });
        waitFor(^BOOL { return ![detail(failing) isEqual:@"Clearing…"] && ![detail(failing) isEqual:@"Calculating…"]; });
        CHECK(!informedMessage && ([ownedClipNames() isEqual:@[leased.lastPathComponent]]));
        checkProtected();

        [NSURLProtocol unregisterClass:CatalogProtocol.class];
        if (priorToken) [defaults setObject:priorToken forKey:@"spotifyglass.motion.token"];
        else [defaults removeObjectForKey:@"spotifyglass.motion.token"];
        leased = nil;
        CHECK([files() removeItemAtURL:sandbox error:nil]);
        puts("artwork clear: size, confirmation, owned scope, leases, stale work and failure reporting passed");
        return 0;
    }
}

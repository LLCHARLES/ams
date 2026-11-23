// Where a track's moving artwork comes from, in the user's order: the Canvas Spotify gives the track and
// Apple Music's animated album cover. Either can be switched off. The player and the lock screen walk the
// order (SGMotionClipFor); the album page's animated cover asks only whether Apple Music is on.
//
// A track whose metadata names no Canvas has it asked of Spotify's Canvas service, the way Spotify's own
// player is told of one, as the signed-in app (SGSpclientHeaders).
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGSourcesPage.h"
#import "Shared/Lyrics/Lyrics.h"
#import "AnimatedArtwork.h"
#import "SGMotionClip.h"
#import "SGMotionTicket.h"

static NSString *const kCanvas = @"canvas", *const kAppleMusic = @"applemusic";

static NSArray<SGSource *> *allSources(void) {
    return @[
        [SGSource sourceWithKey:kCanvas name:SGL(@"settings.artwork.source.canvas.name", @"Spotify Canvas") detail:SGL(@"settings.artwork.source.canvas.detail", @"The track's own looping video")],
        [SGSource sourceWithKey:kAppleMusic name:@"Apple Music" detail:SGL(@"settings.artwork.source.applemusic.detail", @"The album's animated cover")],
    ];
}

NSArray<NSString *> *SGMotionSourceOrder(void) {
    id stored = [NSUserDefaults.standardUserDefaults arrayForKey:SGKeyMotionSources];
    NSArray *keys = [stored isKindOfClass:NSArray.class] ? stored : @[kCanvas, kAppleMusic];
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    for (id key in keys) {
        if (([key isEqual:kCanvas] || [key isEqual:kAppleMusic]) && ![order containsObject:key]) [order addObject:key];
    }
    return order;
}

BOOL SGMotionAppleMusicOn(void) {
    return [SGMotionSourceOrder() containsObject:kAppleMusic];
}

NSURL *SGMotionCanvasIn(NSDictionary *metadata) {
    if (![metadata isKindOfClass:NSDictionary.class]) return nil;
    id type = metadata[@"canvas.type"] ?: metadata[SGMotionHiddenCanvas @"canvas.type"];
    id address = metadata[@"canvas.url"] ?: metadata[SGMotionHiddenCanvas @"canvas.url"];
    BOOL video = [type isKindOfClass:NSString.class] && [type rangeOfString:@"video" options:NSCaseInsensitiveSearch].location != NSNotFound;
    return video && [address isKindOfClass:NSString.class] ? [NSURL URLWithString:address] : nil;
}

@interface SGMotionCanvasRequest : NSObject
@property (nonatomic, copy) NSString *uri;
@property (nonatomic, strong) NSData *body;
@property (nonatomic, strong) NSMutableDictionary<NSUUID *, void (^)(NSURL *)> *waiting;
@property (nonatomic, strong) NSURLSessionDataTask *task;
@property (nonatomic, strong) dispatch_source_t headerTimer;
- (void)start:(NSDictionary<NSString *, NSString *> *)headers;
- (void)finish:(NSString *)address status:(NSInteger)status;
@end

// Completed answers are bounded separately from live consumers. Failed, cancelled and
// evicted requests can be asked again.
static const NSUInteger kCanvasAnswerEntries = 200;
static NSMutableDictionary<NSString *, id> *sg_answers;
static NSMutableArray<NSString *> *sg_answerOrder;
static NSMutableDictionary<NSString *, SGMotionCanvasRequest *> *sg_asking;
static BOOL sg_waitingForHeaders;

@implementation SGMotionCanvasRequest
- (void)finish:(NSString *)address status:(NSInteger)status {
    if (sg_asking[self.uri] != self) return;
    [sg_asking removeObjectForKey:self.uri];
    if (self.headerTimer) dispatch_source_cancel(self.headerTimer);
    self.headerTimer = nil;
    [self.task cancel];
    self.task = nil;
    if (status == 200) {
        if (sg_answerOrder.count >= kCanvasAnswerEntries) {
            [sg_answers removeObjectForKey:sg_answerOrder.firstObject];
            [sg_answerOrder removeObjectAtIndex:0];
        }
        sg_answers[self.uri] = address ?: (id)NSNull.null;
        [sg_answerOrder addObject:self.uri];
    }
    NSArray *waiting = self.waiting.allValues;
    [self.waiting removeAllObjects];
    for (void (^waiter)(NSURL *) in waiting) waiter(address ? [NSURL URLWithString:address] : nil);
}

- (void)start:(NSDictionary<NSString *, NSString *> *)headers {
    if (self.headerTimer) dispatch_source_cancel(self.headerTimer);
    self.headerTimer = nil;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://spclient.wg.spotify.com/canvaz-cache/v0/canvases"]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = self.body;
    [headers enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSString *value, BOOL *stop) {
        [request setValue:value forHTTPHeaderField:name];
    }];
    [request setValue:@"application/x-protobuf" forHTTPHeaderField:@"Content-Type"];
    request.allowsConstrainedNetworkAccess = SGFlag(SGKeyMotionLowData, NO);
    __weak SGMotionCanvasRequest *weakSelf = self;
    self.task = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *reply, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        NSString *address = status == 200 ? SGMotionCanvasInReply(reply) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            SGMotionCanvasRequest *request = weakSelf;
            if (!request) return;
            static NSUInteger logged;
            if (logged++ < 5 || status != 200) SGLog(@"motion: Canvas service for %@: %ld, %@", request.uri, (long)status, address ? @"a video" : @"none");
            [request finish:address status:status];
        });
    }];
    [self.task resume];
}
@end

static void canvasFromService(NSString *uri, SGMotionTicket *parent, void (^done)(NSURL *canvas)) {
    // Songs only: a local file, an episode or an ad has no Canvas to ask for.
    id answer = [uri hasPrefix:@"spotify:track:"] ? sg_answers[uri] : NSNull.null;
    if (answer) {
        done([answer isKindOfClass:NSString.class] ? [NSURL URLWithString:answer] : nil);
        return;
    }
    NSData *body = SGMotionCanvasAsk(uri);
    if (!body) {
        done(nil);
        return;
    }
    if (!sg_answers) {
        sg_answers = [NSMutableDictionary dictionary];
        sg_answerOrder = [NSMutableArray array];
    }
    if (!sg_asking) sg_asking = [NSMutableDictionary dictionary];
    SGMotionCanvasRequest *request = sg_asking[uri];
    BOOL created = !request;
    if (created) {
        request = [SGMotionCanvasRequest new];
        request.uri = uri;
        request.body = body;
        request.waiting = [NSMutableDictionary dictionary];
        sg_asking[uri] = request;
    }
    NSUUID *consumer = NSUUID.UUID;
    SGMotionTicket *ticket = [SGMotionTicket new];
    parent.child = ticket;
    request.waiting[consumer] = ^(NSURL *canvas) {
        ticket.onCancel = nil;
        parent.child = nil;
        done(canvas);
    };
    __weak SGMotionCanvasRequest *weakRequest = request;
    ticket.onCancel = ^{
        SGMotionCanvasRequest *pending = weakRequest;
        [pending.waiting removeObjectForKey:consumer];
        if (!pending.waiting.count) [pending finish:nil status:0];
    };
    if (!created) return;
    // SGSpclientHeaders has no failure/cancellation result. Give its wait the same budget
    // as the HTTP session's request timeout, so a cold offline launch can try the next source.
    NSTimeInterval seconds = NSURLSession.sharedSession.configuration.timeoutIntervalForRequest;
    request.headerTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(request.headerTimer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)),
                              DISPATCH_TIME_FOREVER, 0);
    dispatch_source_set_event_handler(request.headerTimer, ^{
        SGMotionCanvasRequest *pending = weakRequest;
        SGLog(@"motion: Canvas headers unavailable within the request timeout for %@", pending.uri);
        [pending finish:nil status:0];
    });
    dispatch_resume(request.headerTimer);
    // The provider cannot unregister its callback. Keep just one, capturing no requests,
    // until it answers; cancelled/expired consumers disappear from sg_asking immediately.
    if (sg_waitingForHeaders) return;
    sg_waitingForHeaders = YES;
    SGSpclientHeaders(^(NSDictionary<NSString *, NSString *> *headers) {
        sg_waitingForHeaders = NO;
        for (SGMotionCanvasRequest *pending in sg_asking.allValues) {
            if (!pending.task) [pending start:headers];
        }
    });
}

void SGMotionClipFor(NSString *uri, NSURL *canvas, NSString *artist, NSString *album, CGFloat pixels,
                     void (^done)(NSURL *file, NSString *source)) {
    SGMotionRequestClip(uri, canvas, artist, album, pixels, done);
}

SGMotionTicket *SGMotionRequestClip(NSString *uri, NSURL *canvas, NSString *artist, NSString *album, CGFloat pixels,
                                   void (^done)(NSURL *file, NSString *source)) {
    return SGMotionRequestSongClip(uri, canvas, artist, album, nil, pixels, done);
}

SGMotionTicket *SGMotionRequestSongClip(NSString *uri, NSURL *canvas, NSString *artist, NSString *album, NSString *song,
                                       CGFloat pixels, void (^done)(NSURL *file, NSString *source)) {
    return SGMotionRequestAlbumSongClip(uri, canvas, artist, album, song, nil, pixels, done);
}

SGMotionTicket *SGMotionRequestAlbumSongClip(NSString *uri, NSURL *canvas, NSString *artist, NSString *album, NSString *song,
                                           NSString *albumURI, CGFloat pixels, void (^done)(NSURL *file, NSString *source)) {
    SGMotionTicket *ticket = [SGMotionTicket new];
    NSArray<NSString *> *order = SGMotionSourceOrder();
    // The walk holds itself until it ends, when it lets go.
    __block void (^ask)(NSUInteger) = nil;
    ticket.onCancel = ^{ ask = nil; };
    void (^finish)(NSURL *, NSString *) = ^(NSURL *file, NSString *source) {
        ask = nil;
        ticket.onCancel = nil;
        ticket.child = nil;
        if (ticket.cancelled) return;
        done(file, source);
    };
    void (^step)(NSUInteger) = ^(NSUInteger index) {
        if (ticket.cancelled) return;
        if (index >= order.count) {
            finish(nil, nil);
            return;
        }
        NSString *source = order[index];
        void (^next)(NSURL *) = ^(NSURL *file) {
            if (ticket.cancelled) return;
            if (file) finish(file, source);
            else ask(index + 1);
        };
        if ([source isEqualToString:kCanvas]) {
            if (canvas) ticket.child = SGMotionRequestFile(canvas, next);
            else canvasFromService(uri, ticket, ^(NSURL *found) {
                if (ticket.cancelled) return;
                if (found) ticket.child = SGMotionRequestFile(found, next);
                else next(nil);
            });
        } else {
            ticket.child = SGMotionRequestSongCover(artist, album, song, albumURI, uri, pixels, next);
        }
    };
    ask = step;
    step(0);
    return ticket;
}

SGModRow *SGMotionSourcesRow(void) {
    SGModRow *row = SGPageRow(SGL(@"settings.artwork.sources.row.title", @"Artwork sources"), ^UIViewController *{
        return SGSourcesPageMake(SGL(@"settings.artwork.sources.title", @"Artwork sources"), SGL(@"settings.artwork.sources.intro", @"Asked top to bottom until one has a clip for the track. Apple Music is "
                                                     @"asked for the album by name, then by barcode or a track's recording code if needed. It never sees your account."),
                                 allSources(), ^NSArray<NSString *> * { return SGMotionSourceOrder(); },
                                 ^(NSArray<NSString *> *keys) { [NSUserDefaults.standardUserDefaults setObject:keys forKey:SGKeyMotionSources]; });
    });
    row.value = ^NSString * {
        NSArray<NSString *> *order = SGMotionSourceOrder();
        if (!order.count) return SGL(@"common.off", @"Off");
        NSString *first = [order.firstObject isEqualToString:kCanvas] ? SGL(@"settings.artwork.sources.first.canvas", @"Canvas") : @"Apple Music";
        return order.count == 1 ? first : [NSString stringWithFormat:SGL(@"settings.artwork.sources.summary.format", @"%@ +%lu"), first, (unsigned long)order.count - 1];
    };
    return SGWithSymbol(row, @"square.stack.3d.down.right");
}

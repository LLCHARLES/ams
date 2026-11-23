#include "Diagnostics.h"
#import <Foundation/Foundation.h>
#import "TrackDownload.h"
#import "WireProto.h"
#import "NativeOffline.h"
#import "TrackJournal.h"
#import "TrackLibrary.h"
#import <objc/runtime.h>
#include <assert.h>
static BOOL prepareReady=YES,prepareDeferred;
static void (^pendingPreparation)(BOOL,NSString *);
static BOOL (^pendingRequested)(void);
void SAPPrepareNativeOffline(BOOL (^requested)(void),void (^completion)(BOOL,NSString *)) {
    dispatch_async(dispatch_get_main_queue(),^{
        if(prepareDeferred) {pendingPreparation=completion;pendingRequested=requested;}
        else completion(prepareReady,@"test native preparation");
    });
}
void SAPReadNativeTrackState(NSString *uri) {}
void SAPRequestNativeAlbumDownload(NSString *uri, void (^completion)(BOOL, NSString *)) {
    if (completion) completion(YES, @"test album request");
}
NSUInteger SAPObservedAudioKeyCount(void) { return 0; }
void SAPJournalVerifyTrack(NSString *uri,void (^completion)(NSDictionary *)) {if(completion)completion(nil);}
NSDictionary *SAPNativeOfflineReport(void) { return @{@"test_stub":@YES}; }
// Журнал здесь подменён: проверяем, что транспортный хук отдаёт ему каждый вызов
// сервиса Offline, а TrackDownload отдаёт рабочий канал к ядру.
static NSMutableArray *journalObserved;
static SAPJournalCaller journalCaller;
static unsigned journalRefreshes;
static NSMutableArray *likeJournal;
void SAPJournalNoteAction(NSString *name,NSDictionary *facts) {
    if (![name isEqual:@"single_track_like_finished"]) return;
    @synchronized(NSNull.null) {
        if (!likeJournal) likeJournal = [NSMutableArray array];
        [likeJournal addObject:[facts copy]];
    }
}
static NSArray *likeEvents(NSNumber *job) {
    @synchronized(NSNull.null) {
        NSMutableArray *events = [NSMutableArray array];
        for (NSDictionary *event in likeJournal)
            if ([event[@"download_generation"] isEqual:job]) [events addObject:event];
        return [events copy];
    }
}
static NSDictionary *downloadHistory(NSNumber *job) {
    for (NSDictionary *entry in SAPTrackDownloadReport()[@"history"])
        if ([entry[@"download_generation"] isEqual:job]) return entry;
    return nil;
}
void SAPJournalObserveCall(NSString *method, NSData *request, NSData *response, NSString *source) {
    if (!journalObserved) journalObserved = [NSMutableArray array];
    [journalObserved addObject:@{@"method": method ?: @"", @"request": @(request.length),
        @"response": @(response.length), @"source": source ?: @""}];
}
void SAPJournalSetCaller(SAPJournalCaller caller) { journalCaller = [caller copy]; }
BOOL SAPJournalOnOwnQueue(void) { return NO; }
static NSDictionary *nativeFailureForTesting;
NSDictionary *SAPJournalNativeErrorForURI(NSString *uri) {return [nativeFailureForTesting[@"uri"] isEqual:uri]?nativeFailureForTesting:nil;}
void SAPJournalRefresh(NSString *reason) { journalRefreshes++; }
void SAPJournalNoteCallIssue(NSString *method,NSString *uri,NSString *channel,NSString *issue) {}
NSString *SAPJournalSummaryText(void) { return @"test journal"; }
NSString *SAPJournalSummaryForReport(NSDictionary *report) {return @"test journal";}
static unsigned journalSaw(NSString *method) {
    unsigned count = 0;
    for (NSDictionary *entry in journalObserved) if ([entry[@"method"] isEqual:method]) count++;
    return count;
}

@interface FakeTrack : NSObject
@property(nonatomic, strong) NSURL *URI;
@property(nonatomic, strong) NSURL *albumURI;
@property(nonatomic, copy) NSString *trackTitle;
@end
@implementation FakeTrack @end
@interface FakeState : NSObject
@property(nonatomic, strong) FakeTrack *track;
@end
@implementation FakeState @end
// ABI fixtures for the exact 9.1.90 classes. Production hooks (not replacement
// download/menu/library logic) are installed on these runtime-named subclasses.
@protocol SPTContextMenuAction <NSObject>
- (NSString *)title;
- (id)performAction;
@end
@interface FakeMenuFactory : NSObject <SPTContextMenuAction>
@end
@implementation FakeMenuFactory
- (NSString *)title { return @"fixture"; }
- (id)performAction { return nil; }
- (id)contextMenuPresenterForTrackWithTrackURI:(id)uri trackName:(id)name trackMetadata:(id)metadata
    playable:(BOOL)playable imageURL:(id)image artists:(id)artists albumName:(id)album
    albumURI:(id)albumURI viewURI:(id)viewURI contextSourceURI:(id)contextURI
    metadataTitle:(id)metadataTitle logContext:(id)logContext options:(id)options actions:(id)actions {
    assert(playable && [metadata isEqual:@"metadata"] && [image isEqual:@"image"] &&
           [artists isEqual:@"artists"] && [album isEqual:@"album"] && [albumURI isEqual:@"albumURI"] &&
           [viewURI isEqual:@"viewURI"] && [contextURI isEqual:@"contextURI"] &&
           [metadataTitle isEqual:@"metadataTitle"] && [logContext isEqual:@"logContext"] && [options isEqual:@"options"]);
    return actions;
}
- (id)contextMenuPresenterForHeaderImageURL:(id)image headerImagePlaceholder:(id)placeholder
    imageStyle:(NSInteger)style title:(id)title subtitle:(id)subtitle metadataTitle:(id)metadataTitle
    actions:(id)actions entityURL:(id)uri options:(id)options {
    assert(style == 7 && [image isEqual:@"image"] && [placeholder isEqual:@"placeholder"] &&
           [subtitle isEqual:@"subtitle"] && [metadataTitle isEqual:@"metadataTitle"] && [options isEqual:@"options"]);
    return actions;
}
@end
static NSArray *trackMenu(FakeMenuFactory *factory, id uri, id title, NSArray *actions) {
    return [factory contextMenuPresenterForTrackWithTrackURI:uri trackName:title trackMetadata:@"metadata"
        playable:YES imageURL:@"image" artists:@"artists" albumName:@"album" albumURI:@"albumURI"
        viewURI:@"viewURI" contextSourceURI:@"contextURI" metadataTitle:@"metadataTitle"
        logContext:@"logContext" options:@"options" actions:actions];
}
@interface FakeCollectionPlatform : NSObject
@property(nonatomic) NSUInteger adds, mode;
@property(nonatomic) BOOL liked;
@property(nonatomic,copy) NSString *uri;
@property(nonatomic,copy) void (^late)(BOOL);
@end
@implementation FakeCollectionPlatform
- (id)stateProvider { return self; }
- (void)addURL:(NSURL *)url showUIConfirmation:(BOOL)confirmation completion:(void (^)(BOOL))completion {
    assert(NSThread.isMainThread && !confirmation);
    self.adds++; self.uri = url.absoluteString;
    if (self.mode == 2) { self.late = completion; return; }
    if (self.mode == 3) [NSException raise:@"LibraryFixture" format:@"failure"];
    if (self.mode == 0) self.liked = YES;
    completion(self.mode == 0);
}
@end
static void installFeatureFixtures(void) {
    Class menu = objc_allocateClassPair(FakeMenuFactory.class,
        "_TtC37ContextMenu_PlatformLegacyAdapterImpl16PresenterFactory", 0);
    Class library = objc_allocateClassPair(FakeCollectionPlatform.class,
        "_TtC23Collection_PlatformImpl22CollectionPlatformImpl", 0);
    assert(menu && library); objc_registerClassPair(menu); objc_registerClassPair(library);
}
@interface SPTEsperantoPlayer : NSObject
@property(nonatomic, strong) FakeState *state;
- (void)addPlayerObserver:(id)observer;
- (void)fetchState:(id)callback on:(id)queue;
- (void)globalPlayerSubscription:(id)subscription gotStateUpdate:(id)state;
@end
@implementation SPTEsperantoPlayer
- (void)addPlayerObserver:(id)observer { assert([observer isEqual:@"test"]); }
- (void)fetchState:(id)callback on:(id)queue {}
- (void)globalPlayerSubscription:(id)subscription gotStateUpdate:(id)state {}
@end
@interface FakeLifetime : NSObject
@property(nonatomic) BOOL cancelled, acquired;
- (void)cancel;
- (void)acquire;
@end
@implementation FakeLifetime
- (void)cancel { assert(self.acquired); self.cancelled = YES; }
- (void)acquire { self.acquired = YES; }
@end
@interface SPTEsperantoTransportBridgeImpl : NSObject
@property(nonatomic) unsigned scenario, queries, requests, removes;
@property(nonatomic) unsigned albumRequests;
@property(nonatomic) BOOL albumSaved,albumSaveFails;
@property(nonatomic) BOOL holdAlbumConfirmation;
@property(nonatomic,copy) dispatch_block_t confirmAlbumMembership;
@property(nonatomic) unsigned commandBehavior, commandCount;
@property(nonatomic,copy) void (^commandLateCallback)(NSData *);
@property(nonatomic, copy) NSString *requested;
@property(nonatomic, copy) void (^lateCallback)(NSData *);
@property(nonatomic, copy) BOOL (^errorCallback)(NSData *);
@property(nonatomic, strong) FakeLifetime *streamLifetime;
- (id)callSingle:(NSString *)service method:(NSString *)method payload:(NSData *)payload onResponse:(void (^)(NSData *))callback;
- (id)callStream:(NSString *)service method:(NSString *)method payload:(NSData *)payload onResponse:(BOOL (^)(NSData *))callback;
@end
static NSString *const trackURI = @"spotify:track:1234567890123456789012";
static NSData *join(NSData *a, NSData *b) { NSMutableData *d = [a mutableCopy]; [d appendData:b]; return d; }
@implementation SPTEsperantoTransportBridgeImpl
- (id)callStream:(NSString *)service method:(NSString *)method payload:(NSData *)payload onResponse:(BOOL (^)(NSData *))callback {
    assert([service isEqual:@"spotify.offline_esperanto.proto.Offline"] && [method isEqual:@"SubscribeError"] && payload.length == 0);
    self.errorCallback = callback; self.streamLifetime = [FakeLifetime new]; return self.streamLifetime;
}
- (id)callSingle:(NSString *)service method:(NSString *)method payload:(NSData *)payload onResponse:(void (^)(NSData *))callback {
    if ([method isEqual:@"warmup"]) return nil;
    if (self.scenario == 12) {
        if ([method isEqual:@"AddDownload"]) self.requests++;
        return nil; // Wrong/stale native channel: never answers.
    }
    NSString *albumURI = @"spotify:album:3333333333333333333333";
    if([service isEqual:@"spotify.your_library_esperanto.proto.YourLibraryService"] && [method isEqual:@"Contains"]) {
        assert([SAPProtoString(SAPProtoFields(payload),3)isEqual:albumURI]);
        NSData *entity=join(SAPProtoBytes(1,[albumURI dataUsingEncoding:NSUTF8StringEncoding]),SAPProtoInteger(2,self.albumSaved));
        NSData *response=join(SAPProtoBytes(2,entity),SAPProtoInteger(98,200));
        if(self.albumSaved && self.holdAlbumConfirmation)self.confirmAlbumMembership=^{callback(response);};
        else callback(response);
        return [FakeLifetime new];
    }
    if([service isEqual:@"spotify.collection_esperanto.proto.CollectionService"] && [method isEqual:@"Add"]) {
        assert(payload.length==40 && memcmp(payload.bytes,(uint8_t[]){0x12,0x26,0x0a,0x24},4)==0);
        assert(memcmp((uint8_t *)payload.bytes+4,albumURI.UTF8String,36)==0);
        self.albumSaved=!self.albumSaveFails;
        // Collection's status is nested in field 1, not YourLibrary's field 98.
        callback([NSData dataWithBytes:self.albumSaveFails?(uint8_t[]){0x0a,0x03,0x08,0x93,0x03}:(uint8_t[]){0x0a,0x03,0x08,0xc8,0x01} length:5]);
        return [FakeLifetime new];
    }
    assert([service isEqual:@"spotify.offline_esperanto.proto.Offline"]);
    if ([method isEqual:@"AddDownload"] && [SAPProtoString(SAPProtoFields(payload), 2) isEqual:albumURI]) {
        self.albumRequests++; callback(NSData.data); return [FakeLifetime new];
    }
    if ([method isEqual:@"GetContexts"]) {
        assert([SAPProtoString(SAPProtoFields(payload), 3) isEqual:albumURI]);
        NSData *context = join(SAPProtoBytes(1, [albumURI dataUsingEncoding:NSUTF8StringEncoding]), SAPProtoInteger(2, self.albumSaved?3:0));
        callback(SAPProtoBytes(1, SAPProtoBytes(1, context))); return [FakeLifetime new];
    }
    if([method isEqual:@"SetOfflinePlaybackAllowed"]) {
        self.commandCount++;assert([payload isEqual:SAPProtoInteger(1,1)]);
        if(self.commandBehavior==1)self.commandLateCallback=callback;
        else if(self.commandBehavior==2)callback(nil);
        else callback(SAPProtoInteger(1,1));
        return [FakeLifetime new];
    }
    if ([method isEqual:@"GetOfflinePlaybackStatus"]) {
        callback([NSData dataWithBytes:(uint8_t[]){0x08,0x01} length:2]);
    } else if ([method isEqual:@"AddDownload"] || [method isEqual:@"RemoveDownload"]) {
        // DownloadRequest.uri is field 2; device omitted means local device.
        // Header 0x12 0x24 and these exact 36 UTF-8 bytes are independent of decoder.
        assert(payload.length == 38 && ((uint8_t *)payload.bytes)[0] == 0x12 && ((uint8_t *)payload.bytes)[1] == 0x24);
        assert(memcmp((uint8_t *)payload.bytes + 2, trackURI.UTF8String, 36) == 0);
        if ([method isEqual:@"RemoveDownload"]) { self.removes++; callback(NSData.data); }
        else {
            self.requests++; self.requested = trackURI;
            if (self.scenario == 1) callback([NSData dataWithBytes:(uint8_t[]){0x08,0x17} length:2]); // NOT_ALLOWED=23
            else if (self.scenario == 6) self.lateCallback = callback;
            else if (self.scenario == 10) callback([NSData dataWithBytes:(uint8_t[]){0xff} length:1]);
            else if (self.scenario == 11) callback(nil);
            else callback(NSData.data); // Valid protobuf default error=0.
        }
    } else if ([method isEqual:@"GetItems"]) {
        assert(payload.length == 38 && ((uint8_t *)payload.bytes)[0] == 0x0a && ((uint8_t *)payload.bytes)[1] == 0x24);
        assert(memcmp((uint8_t *)payload.bytes + 2, trackURI.UTF8String, 36) == 0);
        unsigned status = self.scenario == 3 ? 3 : self.scenario >= 14 ? 1 : 0;
        if (self.requested) {
            self.queries++;
            if(self.scenario==14 || self.scenario==16) {
                status=self.queries<=4?1:self.queries==5?5:3;
                if(self.scenario==16 && self.queries==1)
                    nativeFailureForTesting=@{@"uri":trackURI,@"code":@7004,@"name":@"sync_error_offline_key_failed",@"at":@(NSDate.date.timeIntervalSince1970)};
            }
            else if(self.scenario==15 || self.scenario==17) {
                status=1;
                if(self.scenario==17 && self.queries==1)
                    nativeFailureForTesting=@{@"uri":trackURI,@"code":@7004,@"name":@"sync_error_offline_key_failed",@"at":@(NSDate.date.timeIntervalSince1970)};
            }
            else if (self.scenario == 2 || self.scenario == 8) status = 0;
            else if (self.scenario == 4) status = 6;
            else if (self.scenario == 5) { unsigned values[] = {3,5,3,3}; status = values[MIN(self.queries - 1, 3)]; }
            else if (self.scenario == 9) { self.errorCallback([NSData dataWithBytes:(uint8_t[]){0x08,0x17} length:2]); status = 1; }
            else status = self.queries == 1 ? 6 : self.queries < 4 ? 5 : 3;
        }
        NSString *uri = self.scenario == 8 ? @"spotify:track:2222222222222222222222" : trackURI;
        NSData *item = join(SAPProtoBytes(1, [uri dataUsingEncoding:NSUTF8StringEncoding]), SAPProtoInteger(2, status));
        item = join(item, SAPProtoInteger(4, status == 3 ? 100 : 20));
        callback(SAPProtoBytes(1, item));
    } else assert(!"unexpected RPC");
    return [FakeLifetime new];
}
@end
@interface SPTEsperantoCosmosTransport : SPTEsperantoTransportBridgeImpl @end
@implementation SPTEsperantoCosmosTransport
- (id)callSingle:(NSString *)service method:(NSString *)method payload:(NSData *)payload onResponse:(void (^)(NSData *))callback {
    // Initial GetItems answers; subsequent reads silently disappear after AddDownload.
    if(self.scenario==13 && self.requests>0 && [method isEqual:@"GetItems"])return [FakeLifetime new];
    return [super callSingle:service method:method payload:payload onResponse:callback];
}
@end
static void waitFor(BOOL (^condition)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!condition() && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.003]];
    if (!condition()) NSLog(@"Timeout: %@", SAPTrackDownloadReport());
    assert(condition());
}
static void reset(SPTEsperantoTransportBridgeImpl *t, unsigned scenario) {
    t.scenario = scenario; t.queries = 0; t.requested = nil; t.errorCallback = nil;
}
int main(void) { @autoreleasepool {
    SAPDiagnosticsSetEnabled(true);
    installFeatureFixtures();
    SAPInstallTrackDownloader(); SAPInstallTrackDownloader();
    assert([SAPTrackDownloadReport()[@"installed_hooks"] count] == 7);
    if([NSProcessInfo.processInfo.arguments containsObject:@"-SAPLocalizationOnly"]) {
        __block BOOL answered=NO;
        SAPCallOfflineCommandOnce(@"SetOfflinePlaybackAllowed",SAPProtoInteger(1,1),^(NSData *data,NSString *error) {
            assert(!data && [error isEqual:@"검증된 Spotify 트랜스포트가 없습니다. 먼저 기기 상태를 새로고침하세요."]);
            answered=YES;
        });
        waitFor(^BOOL{return answered;});answered=NO;
        SAPCallReadOnlyService(@"spotify.offline_esperanto.proto.Offline",@"LicenseStatus",NSData.data,^(NSData *data,NSString *error) {
            assert(!data && [error isEqual:@"Spotify가 요청에 응답하지 않았습니다"]);
            answered=YES;
        });
        waitFor(^BOOL{return answered;});answered=NO;
        SAPCallOfflineCommandOnce(@"UnknownMutation",NSData.data,^(NSData *data,NSString *error) {
            assert(!data && [error isEqual:@"지원되지 않는 명시적 오프라인 명령입니다"]);
            answered=YES;
        });
        waitFor(^BOOL{return answered;});
        puts("PASS: production transport/registration errors use Korean through real SGL");
        return 0;
    }
    SPTEsperantoPlayer *player = [SPTEsperantoPlayer new];
    NSString *preferenceKey = @"spotifyglass.pixie.autoLikeDownloads";
    id savedPreference = [NSUserDefaults.standardUserDefaults objectForKey:preferenceKey];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:preferenceKey];
    assert(!SAPAutoLikeDownloadsEnabled());
    FakeTrack *track = [FakeTrack new]; track.URI = [NSURL URLWithString:trackURI]; track.trackTitle = @"Original track";
    FakeState *state = [FakeState new]; state.track = track; player.state = state;
    [player addPlayerObserver:@"test"];
    __block NSString *last;
    void (^callback)(NSString *) = ^(NSString *message) { last = message; };
    SAPDownloadCurrentTrack(callback); assert(last.length && !SAPTrackDownloadActive());
    SPTEsperantoTransportBridgeImpl *bad = [SPTEsperantoTransportBridgeImpl new]; bad.scenario = 12;
    [bad callSingle:@"" method:@"warmup" payload:NSData.data onResponse:nil];
    SPTEsperantoTransportBridgeImpl *t = [SPTEsperantoTransportBridgeImpl new];
    [t callSingle:@"" method:@"warmup" payload:NSData.data onResponse:nil];
    SAPDownloadCurrentTrack(callback);
    waitFor(^BOOL{ return t.requests == 1; });
    assert(![SAPTrackDownloadReport()[@"phase"] isEqual:@"completed"]);
    FakeTrack *next = [FakeTrack new]; next.URI = [NSURL URLWithString:@"spotify:track:2222222222222222222222"]; next.trackTitle = @"Next";
    state.track = next;
    waitFor(^BOOL{ return !SAPTrackDownloadActive(); });
    assert([SAPTrackDownloadReport()[@"phase"] isEqual:@"completed"] && t.queries == 5);
    if (bad.requests != 0) {
        fputs("Unverified transport received a download command\n", stderr); return 1;
    }
    assert([SAPTrackDownloadReport()[@"track_uri"] isEqual:trackURI] && t.streamLifetime.cancelled);
    unsigned queries = t.queries;
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:0.04];
    while (until.timeIntervalSinceNow > 0) [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:until];
    assert(t.queries == queries); // No polling after completion.
    state.track = track;
    [bad callSingle:@"" method:@"warmup" payload:NSData.data onResponse:nil]; // Unrelated calls must not replace proven channel.
    for (unsigned scenario = 1; scenario <= 11; scenario++) {
        if (scenario == 7) continue;
        reset(t, scenario); unsigned requests = t.requests;
        SAPDownloadCurrentTrack(callback);
        if (scenario == 4) {
            waitFor(^BOOL{ return t.requests > requests && t.queries > 0; });
            SAPCancelTrackDownload(); waitFor(^BOOL{ return !SAPTrackDownloadActive(); });
            assert(t.removes == 1 && [SAPTrackDownloadReport()[@"phase"] isEqual:@"cancelled"]); continue;
        }
        waitFor(^BOOL{ return [SAPTrackDownloadReport()[@"active"] boolValue] || t.requests > requests || scenario == 3; });
        if (scenario == 3) waitFor(^BOOL{ return [SAPTrackDownloadReport()[@"monitoring_existing"] boolValue]; });
        waitFor(^BOOL{ return !SAPTrackDownloadActive(); });
        NSDictionary *report = SAPTrackDownloadReport();
        if (scenario == 1) assert([report[@"phase"] isEqual:@"rejected"] && [report[@"response_error"] intValue] == 23);
        if (scenario == 2 || scenario == 8) assert([report[@"phase"] isEqual:@"unconfirmed"] && ![report[@"detail"] containsString:@"не принял"]);
        if (scenario == 3) assert([report[@"phase"] isEqual:@"completed"] && t.requests == requests);
        if (scenario == 5) assert([report[@"phase"] isEqual:@"completed"] && t.queries == 4);
        if (scenario == 6) assert([report[@"phase"] isEqual:@"unconfirmed"] && report[@"response_error"] == NSNull.null);
        if (scenario == 9) assert([report[@"phase"] isEqual:@"failed"] && [report[@"offline_stream_error"] intValue] == 23);
        if (scenario == 10 || scenario == 11) assert([report[@"phase"] isEqual:@"invalid_response"]);
    }
    // A delayed completion from an older request must not corrupt a new job.
    void (^old)(NSData *) = t.lateCallback;
    reset(t, 0); unsigned requests = t.requests;
    SAPDownloadCurrentTrack(callback); waitFor(^BOOL{ return t.requests > requests; });
    old([NSData dataWithBytes:(uint8_t[]){0x08,0x17} length:2]);
    waitFor(^BOOL{ return !SAPTrackDownloadActive(); });
    assert([SAPTrackDownloadReport()[@"phase"] isEqual:@"completed"]);
    assert([SAPTrackDownloadReport()[@"history"] count] == 8);
    track.URI = [NSURL URLWithString:@"spotify:album:1234567890123456789012"];
    requests = t.requests; SAPDownloadCurrentTrack(callback); assert(t.requests == requests);
    track.URI = [NSURL URLWithString:trackURI];
    prepareReady=NO;
    SAPDownloadCurrentTrack(callback);
    waitFor(^BOOL{return [SAPTrackDownloadReport()[@"phase"] isEqual:@"native_preparation_failed"];});
    assert([SAPTrackDownloadReport()[@"phase"] isEqual:@"native_preparation_failed"]&&t.requests==requests);
    prepareReady=YES;prepareDeferred=YES;
    SAPDownloadCurrentTrack(callback);waitFor(^BOOL{return pendingPreparation!=nil;});
    SAPCancelTrackDownload();waitFor(^BOOL{return !SAPTrackDownloadActive();});
    assert(!pendingRequested());pendingPreparation(YES,@"late preparation");
    prepareDeferred=NO;reset(t,0);
    SAPDownloadCurrentTrack(callback);waitFor(^BOOL{return t.requests>requests;});
    waitFor(^BOOL{return !SAPTrackDownloadActive();});
    assert([SAPTrackDownloadReport()[@"phase"] isEqual:@"completed"]);
    // Хук транспорта обязан показать журналу и команду, и опросы состояния, не меняя их.
    assert(journalRefreshes > 0 && journalCaller != nil);
    assert(journalSaw(@"AddDownload") > 0 && journalSaw(@"GetItems") > 0);
    assert(journalSaw(@"GetOfflinePlaybackStatus") > 0 && journalSaw(@"SubscribeError") > 0);
    for (NSDictionary *entry in journalObserved) assert([entry[@"source"] hasPrefix:@"app:"] || [entry[@"source"] hasPrefix:@"menu:"]);
    unsigned beforeQueries = t.queries, seen = journalSaw(@"GetItems");
    id lifetime = journalCaller(@"GetItems", SAPProtoBytes(1, [trackURI dataUsingEncoding:NSUTF8StringEncoding]), NO, 0, ^(NSData *data){});
    assert(lifetime != nil && t.queries == beforeQueries + 1 && journalSaw(@"GetItems") == seen + 1);
    // A proven Cosmos route may stop answering later. Replay only its read on
    // the native bridge, while keeping the acknowledged AddDownload single-shot.
    SPTEsperantoCosmosTransport *cosmos=[SPTEsperantoCosmosTransport new];cosmos.scenario=13;
    unsigned observedBefore=journalSaw(@"GetItems");
    [cosmos callSingle:@"spotify.offline_esperanto.proto.Offline" method:@"GetItems"
        payload:SAPProtoBytes(1,[trackURI dataUsingEncoding:NSUTF8StringEncoding]) onResponse:^(NSData *data){}];
    assert(journalSaw(@"GetItems")==observedBefore+1); // Cosmos -> bridge counted once
    unsigned bridgeAdds=t.requests;
    SAPDownloadCurrentTrack(callback);waitFor(^BOOL{return cosmos.requests==1;});
    waitFor(^BOOL{return !SAPTrackDownloadActive();});
    assert([SAPTrackDownloadReport()[@"phase"] isEqual:@"completed"]);
    assert([SAPTrackDownloadReport()[@"transport_class"] isEqual:@"SPTEsperantoTransportBridgeImpl"]);
    assert(cosmos.requests==1 && t.requests==bridgeAdds);
    // Even a burst of native calls creates at most 64 one-shot watchdogs.
    // Timers drain after their deadline and do not form an idle polling loop.
    waitFor(^BOOL{return [SAPTrackDownloadReport()[@"application_watches_pending"] unsignedIntegerValue]==0;});
    NSUInteger droppedBefore=[SAPTrackDownloadReport()[@"application_watches_dropped"] unsignedIntegerValue];
    for(unsigned i=0;i<100;i++) {
        [t callSingle:@"spotify.offline_esperanto.proto.Offline" method:@"GetItems"
            payload:SAPProtoBytes(1,[trackURI dataUsingEncoding:NSUTF8StringEncoding]) onResponse:^(NSData *data){}];
        assert([SAPTrackDownloadReport()[@"application_watches_pending"] unsignedIntegerValue]==0);
    }
    assert([SAPTrackDownloadReport()[@"application_watches_dropped"] unsignedIntegerValue]==droppedBefore);
    puts("PASS: answered native requests release their watchdog immediately without filling the 64-call budget");
    SPTEsperantoTransportBridgeImpl *quiet=[SPTEsperantoTransportBridgeImpl new];quiet.scenario=12;
    for(unsigned i=0;i<74;i++)
        [quiet callSingle:@"spotify.offline_esperanto.proto.Offline" method:@"GetItems"
            payload:SAPProtoBytes(1,[trackURI dataUsingEncoding:NSUTF8StringEncoding]) onResponse:^(NSData *data){assert(!"unexpected reply");}];
    assert([SAPTrackDownloadReport()[@"application_watches_pending"] unsignedIntegerValue]<=64);
    assert([SAPTrackDownloadReport()[@"application_watches_dropped"] unsignedIntegerValue]>=10);
    waitFor(^BOOL{return [SAPTrackDownloadReport()[@"application_watches_pending"] unsignedIntegerValue]==0;});
    assert(quiet.requests==0);
    // Neither an old ERROR state nor a fresh key_denied is a permanent verdict.
    // Acknowledged AddDownload is sent once, while ERROR -> DOWNLOADING ->
    // DOWNLOADED is observed during the bounded settling period.
    for(unsigned scenario=14;scenario<=16;scenario++) {
        nativeFailureForTesting=@{@"uri":trackURI,@"code":@7004,@"name":@"sync_error_offline_key_failed",@"at":@(NSDate.date.timeIntervalSince1970-60)};
        reset(t,scenario);unsigned addsBefore=t.requests;SAPDownloadCurrentTrack(callback);
        waitFor(^BOOL{return t.requests>addsBefore;});
        waitFor(^BOOL{return [SAPTrackDownloadReport()[@"phase"] isEqual:@"waiting_error_update"];});
        waitFor(^BOOL{return !SAPTrackDownloadActive();});
        NSDictionary *value=SAPTrackDownloadReport();
        assert(t.requests==addsBefore+1);
        if(scenario==15) {
            assert([value[@"phase"] isEqual:@"failed"]);
            assert(![value[@"native_error_during_attempt"] boolValue]);
            assert(![value[@"detail"] containsString:@"key_denied / 7004"]);
        } else assert([value[@"phase"] isEqual:@"completed"] && t.queries==7);
    }
    reset(t,17);unsigned beforeNativeFailure=t.requests;SAPDownloadCurrentTrack(callback);waitFor(^BOOL{return t.requests>beforeNativeFailure;});waitFor(^BOOL{return !SAPTrackDownloadActive();});
    assert([SAPTrackDownloadReport()[@"phase"] isEqual:@"failed"]);
    assert([SAPTrackDownloadReport()[@"native_error_during_attempt"] boolValue]);
    assert([SAPTrackDownloadReport()[@"detail"] containsString:@"key_denied / 7004"]);
    assert([SAPTrackDownloadReport()[@"error_wait_seconds"] doubleValue]>=0.12);
    nativeFailureForTesting=nil;
    // Optional diagnostics must not be required for AddDownload, verified
    // completion or read-only fallback. No extra streams or journal work.
    SAPDiagnosticsSetEnabled(false);reset(t,0);t.streamLifetime=nil;t.errorCallback=nil;
    NSUInteger oldJournal=journalObserved.count;unsigned oldRefresh=journalRefreshes;unsigned oldAdds=t.requests;
    SAPDownloadCurrentTrack(callback);waitFor(^BOOL{return t.requests>oldAdds;});
    waitFor(^BOOL{return !SAPTrackDownloadActive();});
    assert([SAPTrackDownloadReport()[@"phase"] isEqual:@"completed"] && t.requests==oldAdds+1);
    assert(t.streamLifetime==nil && journalObserved.count==oldJournal && journalRefreshes==oldRefresh);
    assert([SAPTrackDownloadReport()[@"application_watches_pending"] unsignedIntegerValue]==0);
    // Switching off in the middle cancels only the diagnostic stream.
    SAPDiagnosticsSetEnabled(true);reset(t,4);oldAdds=t.requests;unsigned oldRemoves=t.removes;
    SAPDownloadCurrentTrack(callback);waitFor(^BOOL{return t.requests>oldAdds && t.streamLifetime!=nil;});
    FakeLifetime *diagnosticStream=t.streamLifetime;SAPDiagnosticsSetEnabled(false);
    waitFor(^BOOL{return diagnosticStream.cancelled;});assert(SAPTrackDownloadActive() && t.removes==oldRemoves);
    SAPCancelTrackDownload();waitFor(^BOOL{return !SAPTrackDownloadActive();});assert(t.removes==oldRemoves+1);
    SAPDiagnosticsSetEnabled(true);
    puts("PASS: diagnostics OFF keeps native download and completion; toggling OFF does not cancel the track");
    // Unlike read-only requests, explicit mutations must never fall back to a
    // second transport, including after a timeout or invalid response.
    reset(t,0);
    __block BOOL answered=NO;
    SAPCallReadOnlyService(@"spotify.offline_esperanto.proto.Offline",@"GetOfflinePlaybackStatus",NSData.data,^(NSData *d,NSString *e){assert(d && !e);answered=YES;});
    waitFor(^BOOL{return answered;});
    for(unsigned behavior=0;behavior<3;behavior++) {
        t.commandBehavior=behavior;unsigned before=t.commandCount;__block unsigned completions=0;
        SAPCallOfflineCommandOnce(@"SetOfflinePlaybackAllowed",SAPProtoInteger(1,1),^(NSData *d,NSString *e){
            assert(behavior==0?(d!=nil && e==nil):(d==nil && e!=nil));completions++;
        });
        waitFor(^BOOL{return completions==1;});assert(t.commandCount==before+1 && cosmos.commandCount==0 && bad.commandCount==0);
        if(behavior==1){t.commandLateCallback(SAPProtoInteger(1,1));
            NSDate *until=[NSDate dateWithTimeIntervalSinceNow:0.08];
            while(until.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];
            assert(completions==1 && t.commandCount==before+1);
        }
    }
    unsigned before=t.commandCount;answered=NO;
    SAPCallOfflineCommandOnce(@"UnknownMutation",NSData.data,^(NSData *d,NSString *e){assert(!d && e);answered=YES;});
    waitFor(^BOOL{return answered;});assert(t.commandCount==before);
    puts("PASS: explicit enable uses one proven endpoint once; timeout/invalid/late replies never replay it; unknown mutations are rejected");
    // The real menu hook captures selected A while B is playing, before any
    // asynchronous preparation. Mutable caller strings cannot retarget it.
    state.track = next;
    FakeMenuFactory *factory = [NSClassFromString(@"_TtC37ContextMenu_PlatformLegacyAdapterImpl16PresenterFactory") new];
    NSMutableString *selectedURI = [trackURI mutableCopy], *selectedTitle = [@"Selected A" mutableCopy];
    NSObject *nativeAction = [NSObject new];
    NSArray *menu = trackMenu(factory, selectedURI, selectedTitle, @[nativeAction]);
    assert(menu.count == 2 && menu.firstObject == nativeAction);
    id<SPTContextMenuAction> action = menu.lastObject;
    assert([[action title] isEqual:@"Download"]);
    [selectedURI setString:next.URI.absoluteString]; [selectedTitle setString:@"Changed"];
    reset(t, 0); requests = t.requests;
    [action performAction]; [action performAction];
    waitFor(^BOOL { return t.requests == requests + 1; });
    waitFor(^BOOL { return !SAPTrackDownloadActive(); });
    assert([SAPTrackDownloadReport()[@"track_uri"] isEqual:trackURI]);
    assert([SAPTrackDownloadReport()[@"track_title"] isEqual:@"Selected A"]);
    assert([SAPTrackDownloadReport()[@"like_status"] isEqual:@"off"]);
    [action performAction]; assert(t.requests == requests + 1);
    NSArray *reopened = trackMenu(factory, [NSURL URLWithString:trackURI], @"Reopened A", menu);
    assert(reopened.count == 2 && reopened.lastObject != action);
    // Invalid/non-track contexts never inherit a previously injected action.
    for (id invalid in @[@"spotify:album:1234567890123456789012",
        @"spotify:episode:1234567890123456789012", @"spotify:local:a:b:c:1",
        @"spotify:track:short", @"spotify:track:123456789012345678901!", NSNull.null]) {
        NSArray *invalidMenu = trackMenu(factory, invalid, @"Not music", menu);
        assert(invalidMenu.count == 1 && invalidMenu.firstObject == nativeAction);
        SAPDownloadTrack(invalid, @"Invalid", callback);
        assert(t.requests == requests + 1 && !SAPTrackDownloadActive());
    }
    NSArray *generic = [factory contextMenuPresenterForHeaderImageURL:@"image" headerImagePlaceholder:@"placeholder"
        imageStyle:7 title:@"Generic A" subtitle:@"subtitle" metadataTitle:@"metadataTitle"
        actions:@[nativeAction] entityURL:[NSURL URLWithString:trackURI] options:@"options"];
    assert(generic.count == 2);
    reset(t, 0); requests = t.requests;
    [generic.lastObject performAction];
    waitFor(^BOOL { return t.requests == requests + 1; });
    waitFor(^BOOL { return !SAPTrackDownloadActive(); });
    assert([SAPTrackDownloadReport()[@"track_title"] isEqual:@"Generic A"]);
    puts("PASS: production menu hooks select A while B plays; immutable metadata; reopened/duplicate/stale action; invalid and non-track contexts; generic music entity");

    SAPSetAutoLikeDownloadsEnabled(YES);
    assert(SAPAutoLikeDownloadsEnabled() && [NSUserDefaults.standardUserDefaults boolForKey:preferenceKey]);
    reset(t, 0); requests = t.requests;
    SAPDownloadTrack(trackURI, @"Unavailable like", callback);
    waitFor(^BOOL { return t.requests > requests; });
    waitFor(^BOOL { return !SAPTrackDownloadActive() && [SAPTrackDownloadReport()[@"like_status"] isEqual:@"unavailable"]; });
    assert([SAPTrackDownloadReport()[@"phase"] isEqual:@"completed"]);
    assert([SAPTrackDownloadReport()[@"like_detail"] isEqual:
        @"Adding this track to Liked Songs is unavailable. Add it manually; download status is shown separately."]);

    FakeCollectionPlatform *library = [NSClassFromString(@"_TtC23Collection_PlatformImpl22CollectionPlatformImpl") new];
    [library stateProvider]; // Observes the real base-platform getter hook.
    for (NSUInteger mode = 0; mode < 4; mode++) {
        library.mode = mode; NSUInteger adds = library.adds;
        reset(t, 0); requests = t.requests;
        SAPDownloadTrack(trackURI, @"Selected A", callback);
        waitFor(^BOOL { return t.requests > requests; });
        NSString *expectedLike = mode == 0 ? @"added" : @"failed";
        waitFor(^BOOL { return !SAPTrackDownloadActive() && [SAPTrackDownloadReport()[@"like_status"] isEqual:expectedLike]; });
        assert(library.adds == adds + 1 && [library.uri isEqual:trackURI]);
        assert([SAPTrackDownloadReport()[@"phase"] isEqual:@"completed"] && library.liked);
        if (mode) assert([SAPTrackDownloadReport()[@"like_detail"] isEqual:
            @"Could not add this track to Liked Songs. Try adding it manually; download status is shown separately."]);
        if (mode == 2) {
            library.late(YES);
            [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
            assert([SAPTrackDownloadReport()[@"like_status"] isEqual:@"failed"]);
        }
    }
    library.mode = 0; NSUInteger adds = library.adds;
    reset(t, 3); requests = t.requests;
    SAPDownloadTrack(trackURI, @"Already downloaded and liked", callback);
    waitFor(^BOOL { return library.adds == adds + 1; });
    waitFor(^BOOL { return !SAPTrackDownloadActive(); });
    assert(t.requests == requests && library.liked && [SAPTrackDownloadReport()[@"like_status"] isEqual:@"added"]);

    // A completed monitor does not cancel its still-pending library operation
    // when B starts. Exercise explicit failure, real library timeout and success.
    // B stays in deferred preparation so its entire current state is stable.
    for (NSUInteger outcome = 0; outcome < 3; outcome++) {
        library.mode = 2; reset(t, 3); adds = library.adds;
        NSMutableArray *messagesA = [NSMutableArray array];
        SAPDownloadTrack(trackURI, @"Completed A", ^(NSString *message) { [messagesA addObject:message]; });
        waitFor(^BOOL { return library.adds == adds + 1; });
        void (^completeA)(BOOL) = library.late;
        waitFor(^BOOL { return !SAPTrackDownloadActive(); });
        NSNumber *jobA = SAPTrackDownloadReport()[@"download_generation"];
        assert([downloadHistory(jobA)[@"phase"] isEqual:@"completed"]);
        assert([downloadHistory(jobA)[@"like_status"] isEqual:@"pending"]);
        prepareDeferred = YES; pendingPreparation = nil; pendingRequested = nil;
        SAPDownloadTrack(next.URI.absoluteString, @"Pending B", callback);
        waitFor(^BOOL { return pendingPreparation != nil; });
        NSArray *currentKeys = @[@"download_generation", @"track_uri", @"track_title", @"phase",
            @"detail", @"active", @"like_status", @"like_detail", @"request_sent", @"status_checks"];
        NSDictionary *beforeB = [SAPTrackDownloadReport() dictionaryWithValuesForKeys:currentKeys];
        assert([beforeB[@"track_uri"] isEqual:next.URI.absoluteString] && ![beforeB[@"track_uri"] isEqual:trackURI]);
        if (outcome != 1) completeA(outcome == 2);
        NSString *terminal = outcome == 2 ? @"added" : @"failed";
        waitFor(^BOOL { return [downloadHistory(jobA)[@"like_status"] isEqual:terminal]; });
        NSString *failure = @"“Completed A”: Could not add this track to Liked Songs. Try adding it manually; download status is shown separately.";
        NSPredicate *failureMatch = [NSPredicate predicateWithBlock:^BOOL(NSString *text, NSDictionary *bindings) {
            return [text isEqual:failure];
        }];
        if (outcome != 2) waitFor(^BOOL { return [messagesA filteredArrayUsingPredicate:failureMatch].count == 1; });
        // A duplicate or late native reply after a terminal callback/timeout
        // must not add another journal result or another failure notification.
        completeA(YES); completeA(NO);
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        assert([messagesA filteredArrayUsingPredicate:failureMatch].count == (outcome == 2 ? 0 : 1));
        NSArray *events = likeEvents(jobA);
        assert(events.count == 1 && [events[0][@"track_uri"] isEqual:trackURI]);
        assert([events[0][@"track_title"] isEqual:@"Completed A"] && [events[0][@"like_status"] isEqual:terminal]);
        assert([downloadHistory(jobA)[@"phase"] isEqual:@"completed"]);
        assert([downloadHistory(jobA)[@"like_status"] isEqual:terminal]);
        assert([[SAPTrackDownloadReport() dictionaryWithValuesForKeys:currentKeys] isEqual:beforeB]);
        SAPCancelTrackDownload(); waitFor(^BOOL { return !SAPTrackDownloadActive(); });
        assert(!pendingRequested());
        pendingPreparation = nil; pendingRequested = nil; prepareDeferred = NO;
    }
    puts("PASS: completed A pending like survives B start; A failure/timeout delivered once with title; success updates A history/journal once; B current report untouched");

    // The preference belongs to the action, not a later poll. Off never sends a
    // library mutation even with a captured platform, or when enabled afterward.
    SAPSetAutoLikeDownloadsEnabled(NO); adds = library.adds;
    reset(t, 0); requests = t.requests;
    SAPDownloadTrack(trackURI, @"Off at tap", callback);
    SAPSetAutoLikeDownloadsEnabled(YES);
    waitFor(^BOOL { return t.requests > requests; });
    waitFor(^BOOL { return !SAPTrackDownloadActive(); });
    assert(library.adds == adds && [SAPTrackDownloadReport()[@"like_status"] isEqual:@"off"]);
    for (unsigned rejectedScenario = 1; rejectedScenario <= 10; rejectedScenario += 9) {
        reset(t, rejectedScenario); requests = t.requests;
        SAPDownloadTrack(trackURI, @"Rejected", callback);
        waitFor(^BOOL { return t.requests > requests; });
        waitFor(^BOOL { return !SAPTrackDownloadActive(); });
        assert(library.adds == adds);
    }
    reset(t, 6); requests = t.requests;
    SAPDownloadTrack(trackURI, @"Cancel before acceptance", callback);
    waitFor(^BOOL { return t.requests > requests; });
    SAPCancelTrackDownload(); waitFor(^BOOL { return !SAPTrackDownloadActive(); });
    t.lateCallback(NSData.data);
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    assert(library.adds == adds && [SAPTrackDownloadReport()[@"phase"] isEqual:@"cancelled"]);

    // Duplicate queued commands produce one add. Cancellation never unlikes,
    // and an old library completion cannot overwrite the next job's outcome.
    library.mode = 2; reset(t, 4); requests = t.requests;
    NSMutableArray *cancelledMessages = [NSMutableArray array];
    SAPDownloadTrack(trackURI, @"Cancelled A", ^(NSString *message) { [cancelledMessages addObject:message]; });
    SAPDownloadTrack(trackURI, @"Duplicate", callback);
    waitFor(^BOOL { return library.adds == adds + 1; });
    assert(t.requests == requests + 1);
    NSNumber *cancelledJob = SAPTrackDownloadReport()[@"download_generation"];
    void (^oldLike)(BOOL) = library.late;
    SAPCancelTrackDownload(); waitFor(^BOOL { return !SAPTrackDownloadActive(); });
    assert(library.liked && [SAPTrackDownloadReport()[@"like_status"] isEqual:@"cancelled"]);
    library.mode = 1; reset(t, 0); requests = t.requests;
    SAPDownloadTrack(trackURI, @"Next action", callback);
    waitFor(^BOOL { return t.requests > requests; });
    waitFor(^BOOL { return !SAPTrackDownloadActive() && [SAPTrackDownloadReport()[@"like_status"] isEqual:@"failed"]; });
    oldLike(NO); oldLike(YES);
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    assert([SAPTrackDownloadReport()[@"track_title"] isEqual:@"Next action"]);
    assert([SAPTrackDownloadReport()[@"like_status"] isEqual:@"failed"] && library.liked);
    assert(likeEvents(cancelledJob).count == 0 && [downloadHistory(cancelledJob)[@"like_status"] isEqual:@"cancelled"]);
    for (NSString *message in cancelledMessages)
        assert(![message hasPrefix:@"“Cancelled A”: "]);

    // Unsaved albums must become library members before Spotify can download.
    adds = library.adds; next.albumURI = [NSURL URLWithString:@"spotify:album:3333333333333333333333"];
    t.holdAlbumConfirmation=YES;unsigned requestsBeforeMembership=t.albumRequests;
    __block BOOL albumDone = NO;
    SAPDownloadCurrentAlbum(^(NSString *message) {
        if ([message isEqual:@"The album is already fully downloaded in Spotify."]) albumDone = YES;
    });
    waitFor(^BOOL{return t.confirmAlbumMembership!=nil;});
    assert(t.albumSaved && t.albumRequests==requestsBeforeMembership);
    t.holdAlbumConfirmation=NO;t.confirmAlbumMembership();t.confirmAlbumMembership=nil;
    NSDate *albumDeadline=[NSDate dateWithTimeIntervalSinceNow:4];
    while(!albumDone && albumDeadline.timeIntervalSinceNow>0)
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:albumDeadline];
    if(!albumDone){fputs("FAIL: unsaved album did not become downloaded\n",stderr);return 1;}
    assert(t.albumSaved && library.adds == adds);
    t.albumSaved=NO;t.albumSaveFails=YES;unsigned albumRequests=t.albumRequests;
    __block BOOL saveFailed=NO;
    SAPDownloadCurrentAlbum(^(NSString *message){saveFailed=YES;});
    waitFor(^BOOL{return saveFailed;});
    assert(!t.albumSaved && t.albumRequests==albumRequests);
    t.albumSaveFails=NO;
    puts("PASS: album save then confirmed membership before download; rejected save starts no download");
    __block BOOL cancelledLibrary = NO;
    SAPAddTrackToLikedSongs(trackURI, ^BOOL { return NO; }, ^(NSString *status, NSString *message) {
        assert([status isEqual:@"cancelled"] && !message); cancelledLibrary = YES;
    });
    waitFor(^BOOL { return cancelledLibrary; }); assert(library.adds == adds);
    if (savedPreference) [NSUserDefaults.standardUserDefaults setObject:savedPreference forKey:preferenceKey];
    else [NSUserDefaults.standardUserDefaults removeObjectForKey:preferenceKey];
    puts("PASS: default off/persisted on; acceptance gating; add-only already-liked preservation; unavailable/failed/timed-out likes separate from download; cancellation and stale callback; no album/bulk likes");
    puts("PASS: native preparation failure/cancellation; native transport/descriptor routing; exact one-track wire request; journal observation of every Offline call; actual rejection codes vs no response; independent item-state completion; transient/incorrect/nil responses; cached track; cancellation; stale callback; no idle polling");
} }

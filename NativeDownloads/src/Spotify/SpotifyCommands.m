#import "SpotifyTransport.h"
#import "Localization.h"
#import "TrackJournal.h"
#import "WireProto.h"
#import "PlayerTrace.h"
#import "Diagnostics.h"
#import "Deadline.h"
#import "DiagnosticTrace.h"
#include <stdatomic.h>


static BOOL explicitEntityURI(NSString *uri,NSString *kind) {
    NSString *prefix=[NSString stringWithFormat:@"spotify:%@:",kind];
    if(![uri isKindOfClass:NSString.class] || ![uri hasPrefix:prefix] || uri.length!=prefix.length+22)return NO;
    NSCharacterSet *invalid=[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"].invertedSet;
    return [[uri substringFromIndex:prefix.length]rangeOfCharacterFromSet:invalid].location==NSNotFound;
}
static BOOL explicitAlbumURI(NSString *uri) {return explicitEntityURI(uri,@"album");}
static void callExplicitServiceOnce(NSString *serviceName,NSString *method,NSData *payload,void (^completion)(NSData *,NSString *)) {
    SAPInvokeServiceOnce(serviceName,method,payload,^(NSData *data,NSString *error,SAPCommandInvocationDisposition disposition){if(completion)completion(data,error);});
}
void SAPCallOfflineCommandOnceWithDisposition(NSString *method,NSData *payload,
    void (^completion)(NSData *,NSString *,SAPCommandInvocationDisposition)) {
    BOOL downloadCommand=NO;
    if(([method isEqual:@"AddDownload"] || [method isEqual:@"RemoveDownload"]) && [payload isKindOfClass:NSData.class]) {
        NSArray *fields=SAPProtoFields(payload);NSString *uri=SAPProtoString(fields,2);
        downloadCommand=fields.count==1 && (explicitAlbumURI(uri) ||
            explicitEntityURI(uri,@"playlist") || explicitEntityURI(uri,@"track"));
    }
    if((![method isEqual:@"SetOfflinePlaybackAllowed"] && !downloadCommand) || ![payload isKindOfClass:NSData.class]) {
        if(completion)dispatch_async(dispatch_get_main_queue(),^{completion(nil,SAPL(@"settings.pixie.transport.command_unsupported",@"Unsupported explicit offline command"),SAPCommandNotInvoked);});return;
    }
    SAPInvokeServiceOnce(SAPOfflineService,method,payload,completion);
}
void SAPCallOfflineCommandOnce(NSString *method,NSData *payload,void (^completion)(NSData *,NSString *)) {
    SAPCallOfflineCommandOnceWithDisposition(method,payload,^(NSData *data,NSString *error,SAPCommandInvocationDisposition disposition){if(completion)completion(data,error);});
}
void SAPCallPlaylistModificationOnce(BOOL rootlist,NSData *payload,void (^completion)(NSData *,NSString *)) {
    NSArray *outer=SAPProtoFields(payload),*request=SAPProtoFields(SAPProtoData(outer,2));
    NSString *operation=SAPProtoString(request,1);BOOL valid=NO;
    if(rootlist)valid=outer.count==1 && request.count>=3 && [operation isEqual:@"create"] && SAPProtoString(request,4).length && SAPProtoNumber(request,5,0)==1;
    else {
        NSString *uri=SAPProtoString(outer,1);NSString *identifier=[uri hasPrefix:@"spotify:playlist:"]?[uri substringFromIndex:17]:nil;
        NSCharacterSet *invalid=[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"].invertedSet;
        valid=identifier.length==22 && [identifier rangeOfCharacterFromSet:invalid].location==NSNotFound && [operation isEqual:@"add"] && [SAPProtoString(request,3)isEqual:@"end"];
        NSUInteger count=0;for(NSDictionary *f in request)if([f[@"number"]unsignedIntValue]==7){
            if([f[@"wire"]unsignedIntValue]!=2){valid=NO;continue;}
            NSString *track=[[NSString alloc]initWithData:f[@"value"] encoding:NSUTF8StringEncoding];NSString *tid=[track hasPrefix:@"spotify:track:"]?[track substringFromIndex:14]:nil;
            if(tid.length!=22 || [tid rangeOfCharacterFromSet:invalid].location!=NSNotFound)valid=NO;count++;
        }
        valid=valid && count>0 && count<=100;
    }
    NSSet *allowed=[NSSet setWithArray:rootlist?@[@1,@4,@5,@12]:@[@1,@3,@7]];
    for(NSDictionary *field in request)if(![allowed containsObject:field[@"number"]])valid=NO;
    if(outer.count!=(rootlist?1:2))valid=NO;
    if(!valid){if(completion)dispatch_async(dispatch_get_main_queue(),^{completion(nil,SAPL(@"settings.pixie.transport.invalid_playlist_modification",@"Invalid explicit playlist modification."));});return;}
    callExplicitServiceOnce(rootlist?@"spotify.playlist_esperanto.proto.RootlistModificationService":@"spotify.playlist_esperanto.proto.PlaylistService",@"Modify",payload,completion);
}
void SAPSetPlaylistOfflineOnceWithDisposition(NSString *uri,BOOL enabled,
    void (^completion)(NSData *,NSString *,SAPCommandInvocationDisposition)) {
    NSString *identifier=[uri hasPrefix:@"spotify:playlist:"]?[uri substringFromIndex:17]:nil;
    NSCharacterSet *invalid=[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"].invertedSet;
    if(identifier.length!=22 || [identifier rangeOfCharacterFromSet:invalid].location!=NSNotFound){if(completion)dispatch_async(dispatch_get_main_queue(),^{completion(nil,SAPL(@"settings.pixie.transport.invalid_playlist_identity",@"Invalid playlist identity."),SAPCommandNotInvoked);});return;}
    NSMutableData *payload=[SAPProtoBytes(1,[uri dataUsingEncoding:NSUTF8StringEncoding])mutableCopy];[payload appendData:SAPProtoInteger(3,enabled?1:2)];
    SAPInvokeServiceOnce(@"spotify.playlist_esperanto.proto.PlaylistService",@"SetOfflineState",payload,completion);
}
void SAPSetPlaylistOfflineOnce(NSString *uri,BOOL enabled,void (^completion)(NSData *,NSString *)) {
    SAPSetPlaylistOfflineOnceWithDisposition(uri,enabled,^(NSData *data,NSString *error,SAPCommandInvocationDisposition disposition){if(completion)completion(data,error);});
}
void SAPAddAlbumToLibraryOnce(NSString *albumURI,void (^completion)(NSData *,NSString *)) {
    if(!explicitAlbumURI(albumURI)) {if(completion)dispatch_async(dispatch_get_main_queue(),^{completion(nil,SAPL(@"settings.pixie.transport.invalid_album_identity",@"Invalid album identity for Collection.Add."));});return;}
    // collection_add_remove_items_request.proto: items=2, item.uri=1. This
    // matches the 40-byte request made by the normal album button in log 22.
    NSData *payload=SAPProtoBytes(2,SAPProtoBytes(1,[albumURI dataUsingEncoding:NSUTF8StringEncoding]));
    callExplicitServiceOnce(@"spotify.collection_esperanto.proto.CollectionService",@"Add",payload,completion);
}

@interface SAPAlbumMembershipRequest : NSObject
@property(nonatomic,copy) NSString *uri;
@property(nonatomic,copy) void (^completion)(BOOL,NSString *);
@property(nonatomic,copy) dispatch_block_t cancelRead;
@property(nonatomic,strong) dispatch_source_t deadline,recheck;
@property(nonatomic) BOOL finished,saveSent;
- (void)readMembership;
- (void)finish:(NSString *)error;
@end
@implementation SAPAlbumMembershipRequest
- (void)finish:(NSString *)error {
    if(self.finished)return;self.finished=YES;
    if(self.deadline)dispatch_source_cancel(self.deadline);self.deadline=nil;
    if(self.recheck)dispatch_source_cancel(self.recheck);self.recheck=nil;
    if(self.cancelRead)self.cancelRead();self.cancelRead=nil;
    void (^done)(BOOL,NSString *)=self.completion;self.completion=nil;
    SAP_JOURNAL_ACTION(@"album_library_confirmed",@{@"album_uri":self.uri,@"member":@(!error),@"save_sent":@(self.saveSent),@"error":error?:@""});
    if(done)dispatch_async(dispatch_get_main_queue(),^{done(!error,error);});
}
- (void)readMembership {
    if(self.finished)return;
    self.cancelRead=SAPCallReadOnlyServiceCancellable(@"spotify.your_library_esperanto.proto.YourLibraryService",@"Contains",
        SAPProtoBytes(3,[self.uri dataUsingEncoding:NSUTF8StringEncoding]),^(NSData *data,NSString *error){
        dispatch_async(SAPTransportWorker(),^{
            if(self.finished)return;self.cancelRead=nil;
            NSArray *fields=SAPProtoFields(data);NSNumber *member=nil;
            BOOL loading=SAPProtoNumber(SAPProtoFields(SAPProtoData(fields,1)),2,0)!=0;
            if(!error.length && fields && !loading && SAPProtoNumber(fields,98,0)==200 && !SAPProtoString(fields,99).length)
                for(NSDictionary *field in fields)if([field[@"number"]unsignedIntValue]==2 && [field[@"wire"]unsignedIntValue]==2) {
                    NSArray *entity=SAPProtoFields(field[@"value"]);
                    if([SAPProtoString(entity,1)isEqual:self.uri] && SAPProtoNumber(entity,2,0)<=1)member=@(SAPProtoNumber(entity,2,0));
                }
            if(error.length || (!member && !loading)) {
                [self finish:error?:SAPL(@"settings.pixie.session.library_state_invalid",@"Spotify did not return a valid library state for this album.")];return;
            }
            if(member.boolValue){[self finish:nil];return;}
            if(member && !self.saveSent) {
                self.saveSent=YES;
                SAPAddAlbumToLibraryOnce(self.uri,^(NSData *reply,NSString *saveError){
                    dispatch_async(SAPTransportWorker(),^{
                        if(self.finished)return;
                        // Collection.Add has Status in field 1; only Contains
                        // has the separate status_code field 98.
                        NSArray *status=SAPProtoFields(SAPProtoData(SAPProtoFields(reply),1));
                        if(saveError.length || SAPProtoNumber(status,1,0)!=200) {
                            [self finish:saveError?:SAPL(@"settings.pixie.session.library_state_invalid",@"Spotify did not return a valid library state for this album.")];return;
                        }
                        [self readMembership];
                    });
                });return;
            }
            self.recheck=SAPScheduleDeadline(SAPTransportWorker(),1,^{
                self.recheck=nil;[self readMembership];
            });
        });
    });
}
@end

void SAPEnsureAlbumInLibrary(NSString *albumURI,void (^completion)(BOOL,NSString *)) {
    if(!explicitAlbumURI(albumURI)) {
        if(completion)dispatch_async(dispatch_get_main_queue(),^{completion(NO,SAPL(@"settings.pixie.transport.invalid_album_identity",@"Invalid album identity for Collection.Add."));});return;
    }
    dispatch_async(SAPTransportWorker(),^{
        SAPAlbumMembershipRequest *request=[SAPAlbumMembershipRequest new];request.uri=albumURI;request.completion=completion;
        request.deadline=SAPScheduleDeadline(SAPTransportWorker(),30,^{
            [request finish:SAPL(@"settings.pixie.session.library_timeout",@"Spotify did not confirm the album in Your Library within 30 seconds.")];
        });
        [request readMembership];
    });
}

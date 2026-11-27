// Production worker with only the optional dylib, filesystem root and network/power policy replaced.
#import "Shared/Lyrics/PixieLyricsQueue.h"
#import "Core/SGDataRoot.h"
#import "Core/SGOptionalWork.h"
#import "Shared/LyricsSources/LyricsSources.h"
#import <dlfcn.h>
static NSURL *root;
static BOOL installed;
static NSUInteger metadataReads;
static void (^onPinCheck)(void);
static void (^onValidation)(NSString *);
void fixtureLedgerValidation(void (^check)(NSString *)) { onValidation=check; }
static BOOL validateTrack(NSString *track) {
    if (onValidation) onValidation(track);
    return SGLyricsIsSpotifyTrackID(track);
}
void fixturePins(dispatch_block_t checked) { onPinCheck=checked; }
static NSNumber *pinned(NSString *track) {
    if (onPinCheck) { onPinCheck(); return @1; }
    return SGLyricsPinnedID(track);
}
NSUInteger fixtureMetadataReads(void) { return metadataReads; }
void fixtureStorage(NSURL *dir) { root=dir; }
static void (^library)(NSArray *,NSString *);
static void listen(BOOL on) {}
static dispatch_block_t libraryRead(void (^done)(NSArray *,NSString *)) { library=done; return ^{}; }
static dispatch_block_t names(NSString *uri,void (^done)(NSDictionary *)) {
    ++metadataReads;
    dispatch_async(dispatch_get_main_queue(),^{done(@{@"uri":uri,@"name":@"Named song",@"artist_name":@"Artist"});});
    return ^{};
}
void fixtureCompanion(NSURL *dir) { installed=YES; root=dir; }
void (^fixtureLibrary(void))(NSArray *,NSString *) { return library; }
void (^fixtureTakeLibrary(void))(NSArray *,NSString *) {
    void (^done)(NSArray *,NSString *)=library;library=nil;return done;
}
void fixtureAnswerLibrary(NSArray *ids,NSString *error) {
    fixtureTakeLibrary()(ids,error);
}
static void *lookup(void *handle,const char *name) {
    if(!installed)return NULL;
    if(!strcmp(name,"SAPNativeDownloadCompletionSetActive"))return (void *)listen;
    if(!strcmp(name,"SAPFetchDownloadedTrackURIs"))return (void *)libraryRead;
    if(!strcmp(name,"SAPFetchDownloadedTrackMetadata"))return (void *)names;
    return NULL;
}
#define SGDataRoot(directory) root
#define SGLyricsPinnedID pinned
#define SGLyricsIsSpotifyTrackID validateTrack
#define SGOptionalWorkMayRun(expensive) YES
#define dlsym lookup
#import "Shared/Lyrics/PixieLyricsQueue.m"

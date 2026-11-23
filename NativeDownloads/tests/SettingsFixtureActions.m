#import <UIKit/UIKit.h>
#import "AudioProbeUI.h"
#import "Localization.h"
#import "NativeDownloadQuality.h"
#import "OfflineDevices.h"
#import "OfflineLibraryUI.h"
#import "TrackDownload.h"
#import "TrackExport.h"
// Fixture-only preference store and action counter. The shipping bridge forwards
// to TrackDownload's spotifyglass.pixie.autoLikeDownloads preference.
static BOOL SAPFixtureAutoLike=NO;
static BOOL SAPFixtureDownloadActive=NO;
static NSInteger SAPFixtureActionsPerformed=0;
BOOL SAPFixtureAutoLikeEnabled(void) {return SAPFixtureAutoLike;}
BOOL SAPAutoLikeDownloadsEnabled(void) {return SAPFixtureAutoLike;}
void SAPSetAutoLikeDownloadsEnabled(BOOL enabled) {SAPFixtureAutoLike=enabled;}
NSString *SAPAlbumURIForPage(id page) {return nil;}
NSString *SAPAudioExportFormat(void) {return @"m4a";}
void SAPShowOfflineLibrary(UIViewController *presenter) {}
NSString *const SAPNativeDownloadQualityOfferDidChangeNotification=@"FixtureQualityChanged";
BOOL SAPShouldOfferNativeDownloadQuality(void) {return NO;}
BOOL SAPDismissNativeDownloadQualityOfferAndOpenSettings(void) {return NO;}
void SAPPreviewOfflineDeviceSlots(void (^completion)(NSDictionary *,NSString *)) {completion(nil,@"fixture");}
void SAPDisableOfflineDevice(NSString *plan,NSString *token,void (^completion)(NSDictionary *,NSString *)) {completion(nil,@"fixture");}
void SAPEnableOfflineOnCurrentDevice(void (^completion)(NSDictionary *,NSString *)) {completion(nil,@"fixture");}
void SAPFixtureSetDownloadActive(BOOL active) {SAPFixtureDownloadActive=active;}
NSInteger SAPFixtureActionCount(void) {return SAPFixtureActionsPerformed;}
@implementation SAPSettingsActions
+ (NSDictionary *)snapshot {
 return @{@"report":@{},@"diagnostics":SAPL(@"settings.pixie.diagnostics.disabled_hint",@"Diagnostics are off. Enable Diagnostics to collect data."),@"journal_summary":SAPL(@"settings.pixie.journal.disabled_hint",@"Diagnostics are off. The log is not updated. You can still check the current track separately."),@"download_active":@(SAPFixtureDownloadActive),@"auto_like_downloads":@(SAPFixtureAutoLike),@"recording":@NO,@"last_wav_available":@NO,@"key_request_mode":@{@"selected_mode":@0,@"configured_mode":@0,@"last_selector_returned_mode":@(-1),@"runtime_selection_supported":@YES,@"restart_required":@NO,@"detail":SAPL(@"settings.pixie.keymode.detail.preference_only",@"Only restoring a confirmed mode 1 to mode 0 is allowed. A saved preference alone is not confirmation.")}};
}
+ (BOOL)autoLikeDownloadsEnabled {return SAPFixtureAutoLike;}
+ (void)setAutoLikeDownloadsEnabled:(BOOL)enabled {SAPFixtureAutoLike=enabled;}
+ (NSDictionary *)snapshotForDetails:(BOOL)journal {return [self snapshot];}
+ (void)loadDetails:(BOOL)journal completion:(void (^)(NSDictionary *))completion {dispatch_async(dispatch_get_main_queue(),^{completion([self snapshot]);});}
+ (void)perform:(SAPSettingsAction)action { SAPFixtureActionsPerformed++; }
+ (void)downloadAlbum:(NSString *)albumURI {SAPFixtureActionsPerformed++;}
+ (void)setKeyRequestMode:(NSInteger)mode completion:(void (^)(BOOL,NSString *))completion {NSCAssert(mode==0,@"Selecting mode 1 must not be offered");if(completion)completion(NO,@"Spotify reports 0 free device-license slots. Mode was not changed.");}
+ (void)refreshDownloadCompatibility:(void (^)(NSDictionary *))completion {if(completion)completion(@{@"status":@"complete"});}
+ (void)previewOfflineDeviceSlots:(void (^)(NSDictionary *,NSString *))completion {completion(nil,@"fixture: no mutation performed");}
+ (void)releaseOfflineDeviceSlots:(NSString *)planID cacheIDs:(NSArray *)cacheIDs completion:(void (^)(NSDictionary *,NSString *))completion {completion(nil,@"fixture: no mutation performed");}
+ (void)enableOfflineOnCurrentDevice:(void (^)(NSDictionary *,NSString *))completion {completion(nil,@"fixture: no mutation performed");}
@end
void SAPJournalNoteAction(NSString *name,NSDictionary *facts) {}
NSString *SAPDownloadCompatibilityText(NSDictionary *report) {return @"Device licenses: 0 of 5 free. Mode was not changed.";}

// SAPFixtureChrome: stand-in for Spotify's existing mini-player controller.
@interface _TtC18NowPlaying_BarImpl27NowPlayingBarViewController : UIViewController @end
@implementation _TtC18NowPlaying_BarImpl27NowPlayingBarViewController
- (void)viewDidLoad {
 [super viewDidLoad];self.view.backgroundColor=[UIColor colorWithRed:0.22 green:0.08 blue:0.15 alpha:1];self.view.layer.cornerRadius=8;
 UILabel *label=[UILabel new];label.text=@"   Текущий трек · мини-плеер                 ▶";label.textColor=UIColor.whiteColor;
 label.frame=CGRectMake(0,0,430,56);label.autoresizingMask=UIViewAutoresizingFlexibleWidth;[self.view addSubview:label];
}
@end

@protocol SPTPageController <NSObject>
- (NSString *)spt_pageIdentifier;
- (NSURL *)spt_pageURI;
@end
@protocol _TtP19Tome_PageAttributes17SPTPageController_ <NSObject>
- (NSString *)spt_pageIdentifier;
- (NSURL *)spt_pageURI;
@end
__attribute__((constructor)) static void SAPFixtureRegisterProtocols(void) {
 (void)[NSObject conformsToProtocol:@protocol(SPTPageController)];
 (void)[NSObject conformsToProtocol:@protocol(_TtP19Tome_PageAttributes17SPTPageController_)];
}

#import "Localization.h"
#import "NativeAdmission.h"
#import "TargetProfile.h"
#import "DownloadCompatibility.h"
#import "OfflineDevices.h"
#import "TrackExport.h"
#import "OfflineLibraryUI.h"
#import "NativeDownloadQuality.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "AudioProbeUI.h"
#import "Diagnostics.h"
#import "DiagnosticTrace.h"
#import "TrackJournal.h"
#import "TrackDownload.h"
#import "GitHubIcon.h"
#import "PixiePageNavigation.h"
#import "PixiePageController.h"
#include <math.h>

static NSString *const SAPUIChanged=@"SAPDownloadSettingsChanged";
static const void *SAPAttachmentKey=&SAPAttachmentKey;
static void *SAPContentSizeContext=&SAPContentSizeContext;
static void (*originalSettingsLoad)(id,SEL);
static void (*originalSettingsLayout)(id,SEL);
static void *(*originalModPageInit)(void *,SEL,id,id,id,id);
static BOOL settingsInstalled;
static NSString *settingsInstallStatus=@"not_attempted";
NSDictionary *SAPDownloadSettingsInstallReport(void) {
    return @{@"installed":@(settingsInstalled),@"status":settingsInstallStatus};
}

// Resolve Spotify's bottom chrome once per page. Layout callbacks only read
// the cached views' current geometry; there is no timer or playback hook.
@interface SAPBottomChrome : NSObject
@property(nonatomic,weak) UIWindow *window;
@property(nonatomic,strong) NSHashTable<UIView *> *views;
- (CGFloat)coveredBottomOfScroll:(UIScrollView *)scroll;
@end
@implementation SAPBottomChrome
- (void)collect:(UIViewController *)controller depth:(unsigned)depth {
    if(depth>20 || !controller)return;
    NSString *name=NSStringFromClass(controller.class);
    if([name isEqual:@"NowPlaying_BarImpl.NowPlayingBarContainerViewController"] ||
       [name isEqual:@"NowPlaying_BarImpl.NowPlayingBarViewController"] ||
       [name isEqual:@"_TtC18NowPlaying_BarImpl36NowPlayingBarContainerViewController"] ||
       [name isEqual:@"_TtC18NowPlaying_BarImpl27NowPlayingBarViewController"])
        if(controller.isViewLoaded)[self.views addObject:controller.view];
    if([controller isKindOfClass:UITabBarController.class])
        [self.views addObject:((UITabBarController *)controller).tabBar];
    if([name isEqual:@"NavigationUI_TabBarImpl.TabBarContainerImpl"] ||
       [name isEqual:@"_TtC23NavigationUI_TabBarImpl19TabBarContainerImpl"]) {
        SEL selector=NSSelectorFromString(@"tabBarView");
        if([controller respondsToSelector:selector]) {
            id bar=((id(*)(id,SEL))objc_msgSend)(controller,selector);
            if([bar isKindOfClass:UIView.class])[self.views addObject:bar];
        }
    }
    for(UIViewController *child in controller.childViewControllers)[self collect:child depth:depth+1];
}
- (CGFloat)coveredBottomOfScroll:(UIScrollView *)scroll {
    UIWindow *window=scroll.window;if(!window)return 0;
    if(self.window!=window) {
        self.window=window;self.views=[NSHashTable weakObjectsHashTable];
        [self collect:window.rootViewController depth:0];
    }
    CGRect viewport=[scroll convertRect:scroll.bounds toView:window];
    CGFloat top=CGRectGetMaxY(window.bounds)-window.safeAreaInsets.bottom;
    for(UIView *view in self.views) {
        BOOL visible=view.window==window;
        for(UIView *parent=view;visible && parent;parent=parent.superview)
            if(parent.hidden || parent.alpha<0.01)visible=NO;
        if(!visible)continue;
        CGRect rect=[view convertRect:view.bounds toView:window];
        if(rect.size.width<viewport.size.width*0.5 || rect.size.height<=0 ||
           rect.size.height>window.bounds.size.height*0.45 ||
           CGRectGetMinY(rect)<CGRectGetMidY(window.bounds) ||
           !CGRectIntersectsRect(viewport,rect))continue;
        top=MIN(top,CGRectGetMinY(rect));
    }
    return MAX(0,CGRectGetMaxY(viewport)-top);
}
@end

static CGFloat SAPBottomInset(UIScrollView *scroll,SAPBottomChrome *chrome,CGFloat base) {
    CGFloat automatic=scroll.adjustedContentInset.bottom-scroll.contentInset.bottom;
    return MAX(base,[chrome coveredBottomOfScroll:scroll]+12-automatic);
}

static UIImage *SAPSettingsIcon(NSString *symbol,UIColor *color,UITraitCollection *traits) {
    static NSCache *cache;static dispatch_once_t once;
    dispatch_once(&once,^{cache=[NSCache new];cache.countLimit=64;});
    UIColor *resolved=[color resolvedColorWithTraitCollection:traits];
    NSString *key=[NSString stringWithFormat:@"%@|%@|%ld|%.2f",symbol,resolved,(long)traits.accessibilityContrast,traits.displayScale];
    UIImage *cached=[cache objectForKey:key];if(cached)return cached;
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat preferredFormat];if(traits.displayScale>0)format.scale=traits.displayScale;
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc]initWithSize:CGSizeMake(30,30) format:format];
    UIImage *result=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context){
        UIBezierPath *shape=[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0,0,30,30) cornerRadius:8];
        if([symbol isEqual:@"pixie.github"]) {
            [UIColor.whiteColor setFill];[shape fill];
            static UIImage *logo;static dispatch_once_t logoOnce;
            dispatch_once(&logoOnce,^{logo=[UIImage imageWithData:[NSData dataWithBytesNoCopy:(void *)SAPGitHubIconPNG length:sizeof(SAPGitHubIconPNG) freeWhenDone:NO]];});
            [logo drawInRect:CGRectMake(3,3,24,24)];return;
        }
        CGContextSaveGState(context.CGContext);[shape addClip];
        NSArray *colors=@[(id)[resolved colorWithAlphaComponent:0.85].CGColor,(id)resolved.CGColor];
        CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
        CGGradientRef gradient=CGGradientCreateWithColors(space,(__bridge CFArrayRef)colors,NULL);
        CGContextDrawLinearGradient(context.CGContext,gradient,CGPointZero,CGPointMake(0,30),0);
        CGGradientRelease(gradient);CGColorSpaceRelease(space);CGContextRestoreGState(context.CGContext);
        UIImage *icon=[[UIImage systemImageNamed:symbol withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold]]imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
        CGSize size=icon.size;[icon drawInRect:CGRectMake((30-size.width)/2,(30-size.height)/2,size.width,size.height)];
    }];
    [cache setObject:result forKey:key];return result;
}
static UITableViewCell *SAPSettingsCell(UITableView *table,NSString *title,NSString *subtitle,NSString *symbol,UIColor *color,BOOL chevron) {
    UITableViewCell *cell=[table dequeueReusableCellWithIdentifier:@"SAPSettingsRow"];
    if(!cell){cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"SAPSettingsRow"];
        [cell.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:64].active=YES;}
    UIListContentConfiguration *content=[UIListContentConfiguration subtitleCellConfiguration];
    content.text=title;content.secondaryText=subtitle;content.image=SAPSettingsIcon(symbol,color,table.traitCollection);
    content.textProperties.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    content.textProperties.color=UIColor.labelColor;content.textProperties.numberOfLines=0;
    content.secondaryTextProperties.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    content.secondaryTextProperties.color=UIColor.secondaryLabelColor;content.secondaryTextProperties.numberOfLines=0;
    content.imageToTextPadding=14;content.directionalLayoutMargins=NSDirectionalEdgeInsetsMake(12,20,12,20);
    content.imageProperties.reservedLayoutSize=CGSizeMake(30,30);
    cell.contentConfiguration=content;cell.accessoryType=chevron?UITableViewCellAccessoryDisclosureIndicator:UITableViewCellAccessoryNone;
    cell.accessoryView=nil;
    // A read-only mode row may be reused for any action after reloadData.
    cell.userInteractionEnabled=YES;cell.selectionStyle=UITableViewCellSelectionStyleDefault;
    cell.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;cell.accessibilityLabel=title;
    return cell;
}

@interface SAPSettingsTable : SAPPixiePageController
@property(nonatomic,strong) NSDictionary *snapshot;
@property(nonatomic,strong) id changeObserver;
@property(nonatomic,strong) SAPBottomChrome *bottomChrome;
@property(nonatomic) CGFloat baseBottom,appliedBottom;
- (void)refresh;
@end
@implementation SAPSettingsTable
- (instancetype)init {return [super initWithStyle:UITableViewStyleInsetGrouped];}
- (void)viewDidLoad {
    [super viewDidLoad];self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    self.tableView.backgroundColor=UIColor.blackColor;self.tableView.rowHeight=UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight=70;self.tableView.separatorInset=UIEdgeInsetsMake(0,64,0,20);
    self.bottomChrome=[SAPBottomChrome new];
    self.baseBottom=self.appliedBottom=self.tableView.contentInset.bottom;
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"] style:UIBarButtonItemStylePlain target:self action:@selector(refresh)];
}
- (void)viewDidLayoutSubviews {[super viewDidLayoutSubviews];[self updateBottomInset];}
- (void)viewDidAppear:(BOOL)animated {[super viewDidAppear:animated];SAP_TRACE("ui","pixie_page_appeared",0,@{@"title":self.title?:@"",@"controller":NSStringFromClass(self.class)});}
- (void)viewSafeAreaInsetsDidChange {[super viewSafeAreaInsetsDidChange];[self updateBottomInset];}
- (void)updateBottomInset {
    if(!self.tableView.window)return;
    UIEdgeInsets inset=self.tableView.contentInset;
    if(fabs(inset.bottom-self.appliedBottom)>0.5)self.baseBottom=inset.bottom;
    self.appliedBottom=SAPBottomInset(self.tableView,self.bottomChrome,self.baseBottom);
    if(fabs(inset.bottom-self.appliedBottom)>0.5) {
        inset.bottom=self.appliedBottom;self.tableView.contentInset=inset;
    }
    UIEdgeInsets indicator=self.tableView.verticalScrollIndicatorInsets;
    indicator.bottom=self.appliedBottom;if(!UIEdgeInsetsEqualToEdgeInsets(indicator,self.tableView.verticalScrollIndicatorInsets))self.tableView.verticalScrollIndicatorInsets=indicator;
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];[self refresh];
    __weak typeof(self) weak=self;
    self.changeObserver=[NSNotificationCenter.defaultCenter addObserverForName:SAPUIChanged object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){[weak refresh];}];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];if(self.changeObserver)[NSNotificationCenter.defaultCenter removeObserver:self.changeObserver];self.changeObserver=nil;
}
- (void)dealloc {if(_changeObserver)[NSNotificationCenter.defaultCenter removeObserver:_changeObserver];}
- (void)refresh {self.snapshot=[SAPSettingsActions snapshot];[self.tableView reloadData];}
- (void)tableView:(UITableView *)table willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    if([view isKindOfClass:UITableViewHeaderFooterView.class]) {
        UITableViewHeaderFooterView *header=(id)view;
        header.textLabel.text=[self tableView:table titleForHeaderInSection:section];
        header.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];header.textLabel.textColor=UIColor.secondaryLabelColor;
    }
}
@end

static NSString *SAPObservedValue(id value) {
    if(!value||value==NSNull.null)return SAPL(@"settings.pixie.ui.unavailable",@"Unavailable");
    if([value isKindOfClass:NSNumber.class])return [value stringValue];
    return [value isKindOfClass:NSString.class]&&[value length]?value:SAPL(@"settings.pixie.ui.unavailable",@"Unavailable");
}
static UITableViewCell *SAPPlainSettingsCell(NSString *label,NSString *value) {
    UITableViewCell *cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.textLabel.text=label;cell.textLabel.numberOfLines=0;
    cell.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.detailTextLabel.text=value;cell.detailTextLabel.numberOfLines=0;
    cell.detailTextLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    cell.detailTextLabel.textColor=UIColor.secondaryLabelColor;
    cell.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;cell.selectionStyle=UITableViewCellSelectionStyleNone;
    return cell;
}
@interface SAPDetailsSettings : SAPSettingsTable
@property(nonatomic) NSUInteger detailsGeneration;
@end
@implementation SAPDetailsSettings
- (void)viewDidLoad {[super viewDidLoad];self.title=SAPL(@"settings.pixie.diagnostics.audio",@"Audio diagnostics");self.tableView.separatorInset=UIEdgeInsetsMake(0,20,0,20);}
- (void)refresh {
    NSUInteger expected=++self.detailsGeneration;__weak typeof(self) weak=self;
    [SAPSettingsActions loadDetails:NO completion:^(NSDictionary *value){
        if(weak.detailsGeneration!=expected)return;weak.snapshot=value;[weak.tableView reloadData];
    }];
}
- (void)viewWillDisappear:(BOOL)animated {self.detailsGeneration++;[super viewWillDisappear:animated];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {return 4;}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {return section==0?6:section==1?8:section==2?6:5;}
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section {return @[SAPL(@"settings.pixie.ui.audio",@"Audio"),SAPL(@"settings.pixie.header.status",@"Status"),SAPL(@"settings.pixie.ui.offline_checks",@"Offline checks"),SAPL(@"settings.pixie.ui.hooks_traces",@"Hooks / traces")][section];}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    if(section==0)return SAPDiagnosticsEnabled()?SAPL(@"settings.pixie.diagnostics.observed_only",@"Observed values only. Refresh reads the existing diagnostics snapshot."):SAPL(@"settings.pixie.diagnostics.off_snapshot",@"Diagnostics are off. Collection and polling are stopped. Retained observations may be stale; missing data is unavailable.");
    if(section==1)return SAPL(@"settings.pixie.diagnostics.track_scope",@"Unique tracks by final observed state. This is the retained journal snapshot, not your entire library.");
    if(section==2)return SAPL(@"settings.pixie.diagnostics.native_source",@"Native source: Spotify's in-process offline API. Refresh quotas and licenses in Download compatibility for a new explicit check.");
    return SAPL(@"settings.pixie.diagnostics.send_log_hint",@"Detailed events remain in Send log.");
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    if(index.section==2 && index.row==5)return SAPSettingsCell(table,SAPL(@"settings.pixie.action.verify_current_track",@"Check current track"),SAPL(@"settings.pixie.track.native_status",@"Read this track's native offline status"),@"checkmark.circle.fill",UIColor.systemGreenColor,NO);
    NSDictionary *report=self.snapshot[@"report"]?:@{};NSString *label,*value;
    if(index.section==1) {
        NSArray *labels=@[SAPL(@"settings.pixie.ui.downloaded",@"Downloaded"),SAPL(@"settings.pixie.ui.downloading",@"Downloading"),SAPL(@"settings.pixie.ui.waiting",@"Waiting"),SAPL(@"settings.pixie.ui.paused",@"Paused"),SAPL(@"settings.pixie.ui.errors",@"Errors"),SAPL(@"settings.pixie.ui.limit_reached",@"Limit reached"),SAPL(@"settings.pixie.ui.not_downloaded",@"Not downloaded"),SAPL(@"settings.pixie.ui.expired",@"Expired")];
        NSArray *keys=@[@"downloaded",@"downloading",@"waiting",@"awaiting_redownload",@"error",@"waiting_limit_exceeded",@"not_downloaded",@"expired"];
        NSDictionary *counts=report[@"track_journal"][@"state_counts"];
        label=labels[index.row];value=[counts isKindOfClass:NSDictionary.class]?SAPObservedValue(counts[keys[index.row]]?:@0):SAPL(@"settings.pixie.ui.unavailable",@"Unavailable");
    }else if(index.section==0) {
        label=@[SAPL(@"settings.pixie.probe.pcm_confirmed",@"PCM confirmed"),SAPL(@"settings.pixie.diagnostics.callbacks",@"Callbacks"),SAPL(@"settings.pixie.diagnostics.frames",@"Frames"),SAPL(@"settings.pixie.diagnostics.pcm_bytes",@"PCM bytes"),SAPL(@"settings.pixie.diagnostics.format",@"Format"),SAPL(@"settings.pixie.diagnostics.output",@"Output")][index.row];
        if(index.row==4)value=report[@"sample_rate"]&&report[@"channels"]?[NSString stringWithFormat:SAPL(@"settings.pixie.diagnostics.audio_format",@"%@ Hz · %@ ch · %@ bit"),report[@"sample_rate"],report[@"channels"],SAPObservedValue(report[@"bits_per_channel"])]:SAPL(@"settings.pixie.ui.unavailable",@"Unavailable");
        else value=SAPObservedValue(report[@[@"pcm_confirmed",@"callbacks",@"frames",@"pcm_bytes",@"format",@"route"][index.row]]);
    }else if(index.section==2) {
        NSDictionary *check=report[@"compatibility_check"],*sources=check[@"sources"],*license=sources[@"licenses"];
        label=@[SAPL(@"settings.pixie.diagnostics.native_check",@"Native check"),SAPL(@"settings.pixie.diagnostics.free_slots",@"Free device slots"),SAPL(@"settings.pixie.diagnostics.offline_playback",@"Offline playback"),SAPL(@"settings.pixie.diagnostics.track_quota",@"Local track quota"),SAPL(@"settings.pixie.diagnostics.device_read",@"Local device read")][index.row];
        if(index.row==0) {
            NSString *status=check[@"status"];
            double age=NSDate.date.timeIntervalSince1970-[check[@"finished_at"]doubleValue];
            value=check[@"finished_at"]?[NSString stringWithFormat:@"%@ · %@",SAPObservedValue(status),age>90?SAPL(@"settings.pixie.diagnostics.stale",@"stale"):SAPL(@"settings.pixie.diagnostics.recent",@"recent snapshot")]:SAPObservedValue(status);
        }else if(index.row==1)value=[license[@"read_status"]isEqual:@"received"]&&license[@"free_licenses"]&&license[@"max_licenses"]?[NSString stringWithFormat:@"%@ / %@",license[@"free_licenses"],license[@"max_licenses"]]:SAPObservedValue(license[@"read_status"]);
        else if(index.row==2)value=[sources[@"playback"][@"read_status"]isEqual:@"received"]?([sources[@"playback"][@"allowed"]boolValue]?SAPL(@"settings.pixie.ui.allowed",@"Allowed"):SAPL(@"settings.pixie.ui.not_allowed",@"Not allowed")):SAPObservedValue(sources[@"playback"][@"read_status"]);
        else if(index.row==3)value=sources[@"native"][@"current_tracks"]&&sources[@"native"][@"music_limit"]?[NSString stringWithFormat:@"%@ / %@",sources[@"native"][@"current_tracks"],sources[@"native"][@"music_limit"]]:SAPObservedValue(sources[@"native"][@"read_status"]);
        else value=SAPObservedValue(sources[@"local_device"][@"read_status"]);
    }else {
        label=@[SAPL(@"settings.pixie.diagnostics.av_hooks",@"AV hooks"),SAPL(@"settings.pixie.diagnostics.au_calls",@"AU calls"),SAPL(@"settings.pixie.diagnostics.callback_errors",@"Callback errors"),SAPL(@"settings.pixie.diagnostics.trace_active",@"Trace active"),SAPL(@"settings.pixie.diagnostics.trace_run",@"Trace run")][index.row];
        value=index.row<3?SAPObservedValue(report[@[@"objc_hooks",@"au_set_calls",@"callback_errors"][index.row]]):SAPObservedValue(report[@"trace_coverage"][index.row==3?@"active":@"run_id"]);
    }
    return SAPPlainSettingsCell(label,value);
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    [table deselectRowAtIndexPath:index animated:YES];
    if(index.section==2 && index.row==5)[SAPSettingsActions perform:SAPSettingsVerify];
}

@end

@interface SAPOfflineDevicesSettings : SAPSettingsTable
@property(nonatomic,strong) NSDictionary *plan;
@property(nonatomic,copy) NSArray *enabledDevices;
@property(nonatomic,copy) NSString *readError;
@property(nonatomic) BOOL busy;
@property(nonatomic) NSUInteger refreshGeneration;
@end
@implementation SAPOfflineDevicesSettings
@synthesize plan=_plan;
- (void)setPlan:(NSDictionary *)plan {
    _plan=plan;
    NSMutableArray *enabled=[NSMutableArray array];
    for(NSDictionary *device in plan[@"devices"])
        if([device[@"offline_enabled"]boolValue])[enabled addObject:device];
    self.enabledDevices=enabled;
}
- (void)viewDidLoad {[super viewDidLoad];self.title=SAPL(@"settings.pixie.devices.title",@"Offline devices");self.tableView.separatorInset=UIEdgeInsetsMake(0,20,0,20);}
- (void)refresh {
    if(self.busy)return;self.busy=YES;self.readError=nil;[self.tableView reloadData];
    NSUInteger expected=++self.refreshGeneration;
    SAPPreviewOfflineDeviceSlots(^(NSDictionary *plan,NSString *error){
        if(expected!=self.refreshGeneration)return;self.busy=NO;self.plan=plan;self.readError=error;[self.tableView reloadData];
    });
}
- (NSArray *)devices {return self.enabledDevices?:@[];}
- (BOOL)actionsAllowed {
    double age=NSDate.date.timeIntervalSince1970-[self.plan[@"created_at"]doubleValue];
    return !self.busy&&[self.plan[@"actions_allowed"]boolValue]&&age>=0&&age<=90;
}
- (NSDictionary *)currentDevice {for(NSDictionary *device in self.plan[@"devices"])if([device[@"is_current_device"]boolValue])return device;return nil;}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {return 3;}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {return section==0?MAX(1,self.devices.count):section==1?1:3;}
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section {
    if(section==1) {
        NSDictionary *current=self.currentDevice;
        if(current)return [NSString stringWithFormat:SAPL(@"settings.pixie.devices.current_name",@"%@ (current)"),[current[@"name"]length]?current[@"name"]:SAPL(@"settings.pixie.devices.fallback.device_name",@"Spotify device")];
        return SAPL(@"settings.pixie.devices.current",@"Current device");
    }
    return section==0?SAPL(@"settings.pixie.devices.section",@"Devices"):SAPL(@"settings.pixie.devices.sources",@"Source checks");
}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    if(section==2) {
        if(self.busy)return SAPL(@"settings.pixie.devices.refreshing",@"Refreshing native and direct sources…");
        double age=NSDate.date.timeIntervalSince1970-[self.plan[@"created_at"]doubleValue];
        if(self.plan&&age>90)return SAPL(@"settings.pixie.devices.stale",@"This snapshot is stale. Refresh before changing registrations.");
        return self.readError?:self.plan[@"detail"]?:SAPL(@"settings.pixie.devices.sources_agree",@"Native and direct source states agree. Each change is sent once and verified by a fresh read.");
    }
    if(section==0)return SAPL(@"settings.pixie.devices.list_hint",@"Only devices with offline access enabled are shown. Swipe left to disable offline access. Cached tracks on that copy may become unavailable.");
    return SAPL(@"settings.pixie.devices.auth_hint",@"Play one track online on this device, then refresh if authentication or the local device identity is unavailable.");
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    if(index.section==2) {
        NSString *value=index.row==0?SAPObservedValue(self.plan[@"native_read_status"]):index.row==1?SAPObservedValue(self.plan[@"direct_read_status"]):self.plan[@"free_licenses"]?[NSString stringWithFormat:@"%@ / %@",self.plan[@"free_licenses"],self.plan[@"max_licenses"]]:SAPL(@"settings.pixie.ui.unavailable",@"Unavailable");
        return SAPPlainSettingsCell(@[SAPL(@"settings.pixie.devices.native_source",@"Native source"),SAPL(@"settings.pixie.devices.direct_source",@"Direct source"),[NSString stringWithFormat:SAPL(@"settings.pixie.devices.free_maximum",@"Free / maximum slots (%@)"),self.plan[@"quota_source"]?:SAPDeviceL(@"unavailable")]][index.row],value);
    }
    if(index.section==1) {
        BOOL enable=self.actionsAllowed&&self.currentDevice&&![self.currentDevice[@"offline_enabled"]boolValue];
        NSString *title=self.actionsAllowed&&[self.currentDevice[@"offline_enabled"]boolValue]?SAPL(@"settings.pixie.devices.enabled_here",@"Offline enabled on this device"):SAPL(@"settings.pixie.devices.enable_here",@"Enable offline on this device");
        UITableViewCell *cell=SAPSettingsCell(table,title,self.busy?SAPL(@"settings.pixie.ui.checking",@"Checking…"):self.actionsAllowed&&[self.currentDevice[@"offline_enabled"]boolValue]?SAPDeviceL(@"enabled"):enable?SAPL(@"settings.pixie.devices.uses_slot",@"Uses one available slot"):SAPL(@"settings.pixie.devices.refresh_registration",@"Refresh to confirm the current registration"),@"iphone.badge.play",UIColor.systemBlueColor,NO);
        cell.userInteractionEnabled=enable;cell.selectionStyle=enable?UITableViewCellSelectionStyleDefault:UITableViewCellSelectionStyleNone;return cell;
    }
    if(!self.devices.count) {
        BOOL unavailable=!self.plan||self.readError;
        return SAPPlainSettingsCell(self.busy?SAPL(@"settings.pixie.devices.title",@"Offline devices"):unavailable?SAPL(@"settings.pixie.devices.list_unavailable",@"Device list unavailable"):SAPL(@"settings.pixie.devices.no_enabled",@"No offline-enabled devices"),
            self.busy?SAPL(@"settings.pixie.ui.loading",@"Loading…"):unavailable?SAPL(@"settings.pixie.devices.refresh_list",@"Refresh to read the current list"):SAPL(@"settings.pixie.devices.no_registrations",@"No active offline registrations in this snapshot"));
    }
    NSDictionary *device=self.devices[index.row];NSString *cache=device[@"cache_id"]?:@"";
    NSString *suffix=[cache substringFromIndex:cache.length>8?cache.length-8:0];
    NSString *identifier=device[@"device_id"]?:@"";NSString *deviceSuffix=[identifier substringFromIndex:identifier.length>8?identifier.length-8:0];
    NSString *name=[device[@"name"]length]?device[@"name"]:SAPL(@"settings.pixie.devices.fallback.device_name",@"Spotify device");
    NSString *subtitle=[device[@"registration_status"]isEqual:@"not_registered"]?SAPL(@"settings.pixie.devices.not_listed",@"Not registered (not listed)"):[device[@"offline_enabled"]boolValue]?SAPDeviceL(@"enabled"):SAPDeviceL(@"disabled");
    NSUInteger matchingNames=0,matchingIdentifiers=0;
    for(NSDictionary *candidate in self.devices) {
        NSString *candidateName=[candidate[@"name"]length]?candidate[@"name"]:SAPL(@"settings.pixie.devices.fallback.device_name",@"Spotify device");
        if([candidateName isEqual:name]) {
            matchingNames++;if([candidate[@"device_id"]isEqual:identifier])matchingIdentifiers++;
        }
    }
    if(matchingNames>1)subtitle=[NSString stringWithFormat:SAPL(@"settings.pixie.devices.device_suffix",@"%@ · Device %@"),subtitle,deviceSuffix];
    if(matchingIdentifiers>1)subtitle=[NSString stringWithFormat:SAPL(@"settings.pixie.devices.cache_suffix",@"%@ · Cache %@"),subtitle,suffix];
    UITableViewCell *cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    UIListContentConfiguration *content=[UIListContentConfiguration subtitleCellConfiguration];
    content.text=[device[@"is_current_device"]boolValue]?[name stringByAppendingString:@" (current)"]:name;content.secondaryText=subtitle;
    content.textProperties.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    content.secondaryTextProperties.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    content.secondaryTextProperties.color=UIColor.secondaryLabelColor;content.secondaryTextProperties.numberOfLines=0;
    cell.contentConfiguration=content;cell.accessibilityLabel=content.text;
    cell.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;cell.selectionStyle=UITableViewCellSelectionStyleNone;
    return cell;
}
- (void)showResult:(NSString *)title message:(NSString *)message {
    if(!self.view.window)return;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SAPL(@"common.ok",@"OK") style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:alert animated:YES completion:nil];
}
- (void)enableCurrent {
    if(!self.actionsAllowed||!self.currentDevice||[self.currentDevice[@"offline_enabled"]boolValue])return;
    self.busy=YES;[self.tableView reloadData];
    SAPEnableOfflineOnCurrentDevice(^(NSDictionary *result,NSString *error){
        self.busy=NO;[self refresh];[self showResult:error?SAPL(@"settings.pixie.devices.enable_unconfirmed",@"Enable not confirmed"):SAPL(@"settings.pixie.alert.offline_confirmed.title",@"Offline registration confirmed") message:error?:SAPL(@"settings.pixie.devices.enabled_confirmed",@"Spotify confirms offline access for this exact device. Audio playback has not been tested.")];
    });
}
- (void)confirmDisable:(NSDictionary *)device {
    if(!self.actionsAllowed)return;
    NSString *cache=device[@"cache_id"],*suffix=[cache substringFromIndex:cache.length>8?cache.length-8:0];
    NSString *identifier=device[@"device_id"];NSString *deviceSuffix=[identifier substringFromIndex:identifier.length>8?identifier.length-8:0];
    UIAlertController *confirm=[UIAlertController alertControllerWithTitle:SAPL(@"settings.pixie.devices.disable_confirm",@"Disable offline access?") message:[NSString stringWithFormat:SAPL(@"settings.pixie.devices.disable_message",@"%@ · Device %@ · Cache %@\n\nCached tracks on this copy may become unavailable offline. The registration and free slot will be verified after the command."),device[@"name"]?:SAPL(@"settings.pixie.devices.fallback.device_name",@"Spotify device"),deviceSuffix,suffix] preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:SAPL(@"common.cancel",@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:SAPL(@"settings.pixie.devices.disable",@"Disable offline access") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){
        if(!self.actionsAllowed)return;self.busy=YES;[self.tableView reloadData];
        SAPDisableOfflineDevice(self.plan[@"id"],device[@"selection_token"],^(NSDictionary *result,NSString *error){
            self.busy=NO;[self refresh];[self showResult:error?SAPL(@"settings.pixie.devices.disable_unconfirmed",@"Disable not confirmed"):SAPL(@"settings.pixie.devices.access_disabled",@"Offline access disabled") message:error?:[NSString stringWithFormat:SAPL(@"settings.pixie.devices.free_slots",@"Free device slots: %@ / %@."),result[@"free_licenses"],result[@"max_licenses"]]];
        });
    }]];[self presentViewController:confirm animated:YES completion:nil];
}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)table trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)index {
    if(index.section!=0||(NSUInteger)index.row>=self.devices.count||!self.actionsAllowed)return nil;
    NSDictionary *device=self.devices[index.row];if([device[@"synthetic_record"]boolValue]||![device[@"offline_enabled"]boolValue])return nil;
    UIContextualAction *action=[UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:SAPL(@"settings.pixie.ui.remove",@"Remove") handler:^(UIContextualAction *action,UIView *view,void (^done)(BOOL)){done(YES);[self confirmDisable:device];}];
    UISwipeActionsConfiguration *configuration=[UISwipeActionsConfiguration configurationWithActions:@[action]];configuration.performsFirstActionWithFullSwipe=NO;return configuration;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {[table deselectRowAtIndexPath:index animated:YES];if(index.section==1)[self enableCurrent];}
@end

@interface SAPDownloadsSettings : SAPSettingsTable
@property(nonatomic) BOOL checkingCompatibility;
@property(nonatomic) BOOL qualityOffer;
@property(nonatomic,strong) UIView *qualityHeader;
@property(nonatomic,strong) id qualityObserver;
@end
@implementation SAPDownloadsSettings
- (void)viewDidLoad {
    [super viewDidLoad];self.title=SAPL(@"settings.pixie.manager.title",@"Pixie Download Manager");
    [self updateQualityOffer];
    __weak typeof(self) weak=self;
    self.qualityObserver=[NSNotificationCenter.defaultCenter addObserverForName:SAPNativeDownloadQualityOfferDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note){[weak updateQualityOffer];}];
}
- (void)dealloc {if(_qualityObserver)[NSNotificationCenter.defaultCenter removeObserver:_qualityObserver];}
- (void)updateQualityOffer {
    self.qualityOffer=SAPShouldOfferNativeDownloadQuality();[self layoutQualityOffer];
}
- (void)qualityOfferTapped {
    // Persist suppression and remove the header before native navigation starts.
    SAPDismissNativeDownloadQualityOfferAndOpenSettings();
}
- (void)viewDidLayoutSubviews {[super viewDidLayoutSubviews];[self layoutQualityOffer];}
- (void)layoutQualityOffer {
    if(!self.qualityOffer) {
        // Avoid assigning nil to an already empty table header on every layout.
        if(self.qualityHeader && self.tableView.tableHeaderView==self.qualityHeader)self.tableView.tableHeaderView=nil;
        self.qualityHeader=nil;return;
    }
    if(!self.qualityHeader) {
        UIView *header=UIView.new;
        UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
        UIButtonConfiguration *configuration=[UIButtonConfiguration plainButtonConfiguration];
        configuration.title=SAPL(@"settings.pixie.quality.offer",@"Downloads are set to Normal; switch to High in Spotify settings.");
        configuration.baseForegroundColor=UIColor.systemGreenColor;
        configuration.contentInsets=NSDirectionalEdgeInsetsMake(12,0,12,0);
        configuration.titleTextAttributesTransformer=^NSDictionary *(NSDictionary *attributes){NSMutableDictionary *result=attributes.mutableCopy;result[NSFontAttributeName]=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];return result;};
        button.configuration=configuration;button.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeading;
        button.titleLabel.numberOfLines=0;button.titleLabel.adjustsFontForContentSizeCategory=YES;
        [button addTarget:self action:@selector(qualityOfferTapped) forControlEvents:UIControlEventTouchUpInside];
        button.translatesAutoresizingMaskIntoConstraints=NO;[header addSubview:button];
        [NSLayoutConstraint activateConstraints:@[[button.leadingAnchor constraintEqualToAnchor:header.layoutMarginsGuide.leadingAnchor],[button.trailingAnchor constraintEqualToAnchor:header.layoutMarginsGuide.trailingAnchor],[button.topAnchor constraintEqualToAnchor:header.topAnchor],[button.bottomAnchor constraintEqualToAnchor:header.bottomAnchor]]];
        self.qualityHeader=header;
    }
    CGFloat width=self.tableView.bounds.size.width;if(width<=0)return;
    self.qualityHeader.directionalLayoutMargins=self.tableView.directionalLayoutMargins;
    CGSize size=[self.qualityHeader systemLayoutSizeFittingSize:CGSizeMake(width,UILayoutFittingCompressedSize.height) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    CGRect frame=CGRectMake(0,0,width,ceil(size.height));
    BOOL resized=!CGRectEqualToRect(self.qualityHeader.frame,frame);
    if(resized)self.qualityHeader.frame=frame;
    if(self.tableView.tableHeaderView!=self.qualityHeader || resized)self.tableView.tableHeaderView=self.qualityHeader;
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {return 5;}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    if(section==0)return [self.snapshot[@"download_active"]boolValue]?4:3;
    if(section==1)return 3;
    if(section==3)return 4;
    if(section==2)return 2;
    return 2;
}
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section {
    return @[SAPL(@"settings.pixie.header.download",@"Download"),SAPL(@"settings.pixie.header.compatibility",@"Download compatibility"),SAPL(@"settings.pixie.ui.export",@"Export"),SAPL(@"settings.pixie.diagnostics.title",@"Diagnostics"),SAPL(@"settings.pixie.header.me",@"Me")][section];
}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    if(section==0) {
        NSDictionary *startup=self.snapshot[@"jailbreak_bootstrap"];
        if(startup&&![startup[@"native_patches_ready"]boolValue])return [NSString stringWithFormat:SAPL(@"settings.pixie.footer.init_failed",@"Pixie could not initialize downloads (%@). Supported Spotify: %@. Detected: %@. Menu and logs remain available."),startup[@"reason"],@SAP_SPOTIFY_VERSION,startup[@"detected_spotify_version"]];
        return SAPL(@"settings.pixie.footer.download_export",@"Downloads stay in Spotify. Audio export creates files you can save to Files or share.");
    }
    if(section==1) {
        NSDictionary *mode=self.snapshot[@"key_request_mode"];
        return [NSString stringWithFormat:SAPL(@"settings.pixie.footer.troubleshooting",@"%@\n\nOnly change settings in this menu if downloads are not working."),mode[@"detail"]?:@""];
    }
    if(section==4)return @"Spotify 9.1.90 · Vitrine-Pixie v1.4.";
    if(section==2)return SAPL(@"settings.pixie.footer.export",@"Export downloaded Spotify audio to external apps or Files from Pixie or Spotify’s Share as file option. Choose a destination in the share sheet. The selected format applies to future exports.");
    if(section==3)return SAPL(@"settings.pixie.footer.diagnostics",@"Enable Diagnostics for detailed passive events.");
    return nil;
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    NSString *title,*subtitle=nil,*symbol;UIColor *color;BOOL chevron=NO;
    if(index.section==0) {
        NSInteger likeRow=[self.snapshot[@"download_active"]boolValue]?3:2;
        if(index.row==likeRow) {
            UITableViewCell *cell=SAPSettingsCell(table,SAPL(@"settings.pixie.auto_like.title",@"Add single-track downloads to Liked Songs"),nil,@"heart.fill",UIColor.systemGreenColor,NO);
            UISwitch *toggle=[UISwitch new];toggle.on=SAPAutoLikeDownloadsEnabled();
            [toggle addTarget:self action:@selector(autoLikeChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView=toggle;cell.selectionStyle=UITableViewCellSelectionStyleNone;return cell;
        }
        NSArray *titles=@[[self.snapshot[@"download_active"]boolValue]?SAPL(@"settings.pixie.action.track_status",@"Track download status"):SAPL(@"settings.pixie.action.download_current_track",@"Download current track"),SAPL(@"settings.pixie.action.download_current_album",@"Download current track's album"),SAPL(@"settings.pixie.action.cancel_download",@"Cancel download")];
        title=titles[index.row];symbol=@[@"arrow.down.circle.fill",@"square.stack.fill",@"xmark.circle.fill"][index.row];
        color=index.row==2?UIColor.systemOrangeColor:UIColor.systemGreenColor;
    }else if(index.section==1) {
        NSDictionary *mode=self.snapshot[@"key_request_mode"];
        if(index.row==2)return SAPSettingsCell(table,SAPL(@"settings.pixie.devices.title",@"Offline devices"),SAPL(@"settings.pixie.devices.review",@"Review registrations and offline access"),@"externaldrive.badge.person.crop",UIColor.systemOrangeColor,YES);
        if(index.row==1) {
            return SAPSettingsCell(table,SAPL(@"settings.pixie.row.refresh_quotas.title",@"Refresh quotas and licenses"),self.checkingCompatibility?SAPL(@"settings.pixie.row.refresh_quotas.checking",@"Checking Spotify's reported state…"):SAPL(@"settings.pixie.row.refresh_quotas.idle",@"Read only · no licenses or downloads are reset"),@"arrow.clockwise",UIColor.systemBlueColor,NO);
        }
        NSInteger configured=[mode[@"configured_mode"]integerValue];
        title=SAPL(@"settings.pixie.row.request_mode.title",@"Configured request mode");
        NSNumber *last=mode[@"last_selector_returned_mode"];
        subtitle=self.checkingCompatibility?SAPL(@"settings.pixie.row.request_mode.checking",@"Checking quotas and licenses…"):([mode[@"configuration_source"]isEqual:@"verified_direct_instruction"]||[mode[@"configuration_source"]isEqual:@"verified_static_trace_argument"])?SAPL(@"settings.pixie.row.request_mode.verified_executable",@"Verified fixed argument in the executable"):
            (last && last.integerValue>=0?[NSString stringWithFormat:SAPL(@"settings.pixie.row.request_mode.last_selector_format",@"Last selector returned %@ · authorization unconfirmed"),last]:SAPL(@"settings.pixie.row.request_mode.no_invocation",@"No selector invocation observed this launch"));
        symbol=@"arrow.triangle.2.circlepath";color=UIColor.systemOrangeColor;chevron=YES;
        UITableViewCell *cell=SAPSettingsCell(table,title,subtitle,symbol,color,chevron);
        UILabel *status=[UILabel new];status.font=[UIFont monospacedDigitSystemFontOfSize:17 weight:UIFontWeightBold];
        status.text=configured<0?@"?":configured==0?@"0":@"1";
        status.textColor=configured==0?UIColor.systemGreenColor:configured==1?UIColor.systemRedColor:UIColor.secondaryLabelColor;
        [status sizeToFit];cell.accessoryView=status;
        BOOL restore=[mode[@"restore_zero_supported"]boolValue];
        cell.selectionStyle=restore?UITableViewCellSelectionStyleDefault:UITableViewCellSelectionStyleNone;
        cell.userInteractionEnabled=restore;
        return cell;
    }else if(index.section==2) {
        if(index.row==1)return SAPSettingsCell(table,SAPL(@"settings.pixie.library.title",@"Downloaded tracks"),SAPL(@"settings.pixie.library.browse",@"Browse Spotify offline music"),@"music.note.list",UIColor.systemGreenColor,YES);
        UITableViewCell *cell=SAPSettingsCell(table,SAPL(@"settings.pixie.export.ogg",@"Use Ogg format"),nil,@"waveform",UIColor.systemBlueColor,NO);
        UISwitch *toggle=[UISwitch new];toggle.on=[SAPAudioExportFormat()isEqual:@"ogg"];toggle.accessibilityLabel=SAPL(@"settings.pixie.export.ogg",@"Use Ogg format");
        [toggle addTarget:self action:@selector(oggFormatChanged:) forControlEvents:UIControlEventValueChanged];cell.accessoryView=toggle;
        cell.selectionStyle=UITableViewCellSelectionStyleNone;return cell;
    }else if(index.section==4) {
        title=index.row==0?@"GitHub":SAPL(@"settings.pixie.row.telegram.title",@"Telegram channel");
        subtitle=index.row==0?@"Glongq/Vitrine-Pixie":@"@glongqforks";
        symbol=index.row==0?@"pixie.github":@"paperplane.fill";
        color=index.row==0?UIColor.whiteColor:UIColor.systemBlueColor;chevron=YES;
    }else {
        title=@[SAPL(@"settings.pixie.header.diagnostics",@"Diagnostics"),SAPL(@"settings.pixie.diagnostics.audio",@"Audio diagnostics"),SAPL(@"settings.pixie.entry.send_log.title",@"Send log"),SAPL(@"settings.pixie.log.reset",@"Reset log")][index.row];
        symbol=@[@"slider.horizontal.3",@"waveform.path.ecg",@"square.and.arrow.up",@"trash.fill"][index.row];color=index.row==3?UIColor.systemGrayColor:UIColor.systemTealColor;chevron=index.row==1;
        if(index.row==3)subtitle=SAPL(@"settings.pixie.log.reset_detail",@"Clear previous logs and start a fresh history");
    }
    UITableViewCell *cell=SAPSettingsCell(table,title,subtitle,symbol,color,chevron);
    if(index.section==3 && index.row==0) {
        UISwitch *toggle=[UISwitch new];toggle.on=SAPDiagnosticsEnabled();
        toggle.accessibilityLabel=SAPL(@"settings.pixie.header.diagnostics",@"Diagnostics");toggle.accessibilityIdentifier=@"SpotifyDiagnosticsSwitch";
        [toggle addTarget:self action:@selector(diagnosticsChanged:) forControlEvents:UIControlEventValueChanged];cell.accessoryView=toggle;
    }
    return cell;
}
- (void)oggFormatChanged:(UISwitch *)toggle {
    [NSUserDefaults.standardUserDefaults setObject:toggle.on?@"ogg":@"m4a" forKey:@"PixieExportFormat"];
}
- (void)autoLikeChanged:(UISwitch *)toggle {SAPSetAutoLikeDownloadsEnabled(toggle.on);}
- (void)applyDiagnostics:(BOOL)enabled {
    BOOL before=SAPDiagnosticsEnabled();SAPDiagnosticsSetEnabled(enabled);
    SAP_JOURNAL_ACTION(@"diagnostics_changed",@{@"before":@(before),@"after":@(SAPDiagnosticsEnabled())});[self refresh];
}
- (void)requestDiagnostics:(BOOL)enabled {
    if(enabled==SAPDiagnosticsEnabled() || self.presentedViewController)return;
    if(!enabled){[self applyDiagnostics:NO];return;}
    UIAlertController *confirm=[UIAlertController alertControllerWithTitle:SAPL(@"settings.pixie.confirm",@"Are you sure?") message:SAPL(@"settings.pixie.diagnostics.enable_confirm",@"Enable detailed diagnostics logging?") preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:SAPL(@"player.audio_quality.no",@"No") style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:SAPL(@"player.audio_quality.yes",@"Yes") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){[self applyDiagnostics:YES];}]];
    [self presentViewController:confirm animated:YES completion:nil];
}
- (void)diagnosticsChanged:(UISwitch *)toggle {
    BOOL requested=toggle.on;[toggle setOn:SAPDiagnosticsEnabled() animated:YES];[self requestDiagnostics:requested];
}
- (void)slotMessage:(NSString *)title message:(NSString *)message {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SAPL(@"common.ok",@"OK") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    [table deselectRowAtIndexPath:index animated:YES];
    SAP_TRACE("ui","pixie_menu_selection",0,@{@"title":self.title?:@"",@"section":@(index.section),@"row":@(index.row)});
    if(index.section==4) {
        NSURL *url=[NSURL URLWithString:index.row==0?@"https://github.com/Glongq/Vitrine-Pixie":@"https://t.me/glongqforks"];
        [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];return;
    }
    if(index.section==2) {
        if(index.row==1){SAPShowOfflineLibrary(self);return;}
        return;
    }
    if(index.section==3 && index.row==0){[self requestDiagnostics:!SAPDiagnosticsEnabled()];return;}
    if(index.section==3 && index.row==2){[SAPSettingsActions perform:SAPSettingsSendLog];return;}
    if(index.section==3 && index.row==3){[SAPSettingsActions perform:SAPSettingsResetJournal];return;}
    if(index.section==1) {
        if(self.checkingCompatibility)return;
        if(index.row==2){SAPShowPixiePage(self,[SAPOfflineDevicesSettings new]);return;}
        if(index.row==1) {
            self.checkingCompatibility=YES;[self.tableView reloadData];
            [SAPSettingsActions refreshDownloadCompatibility:^(NSDictionary *result){
                self.checkingCompatibility=NO;[self refresh];
                UIAlertController *status=[UIAlertController alertControllerWithTitle:SAPL(@"settings.pixie.alert.quota_check.title",@"Quota and license check") message:SAPDownloadCompatibilityText(result) preferredStyle:UIAlertControllerStyleAlert];
                [status addAction:[UIAlertAction actionWithTitle:SAPL(@"common.ok",@"OK") style:UIAlertActionStyleCancel handler:nil]];
                [self presentViewController:status animated:YES completion:nil];
            }];return;
        }
        NSDictionary *mode=self.snapshot[@"key_request_mode"];
        if(![mode[@"restore_zero_supported"]boolValue])return;
        UIAlertController *choice=[UIAlertController alertControllerWithTitle:SAPL(@"settings.pixie.alert.restore_mode_0.title",@"Restore mode 0?") message:SAPL(@"settings.pixie.alert.restore_mode_0.message",@"The verified selector was observed returning 1. This action only restores mode 0, after a fresh quota and license check. It does not guarantee that downloading will work.") preferredStyle:UIAlertControllerStyleAlert];
        [choice addAction:[UIAlertAction actionWithTitle:SAPL(@"settings.pixie.alert.restore_mode_0.action",@"Restore mode 0") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
            self.checkingCompatibility=YES;[self.tableView reloadData];
            [SAPSettingsActions setKeyRequestMode:0 completion:^(BOOL changed,NSString *reason){
                self.checkingCompatibility=NO;[self refresh];
                [self slotMessage:changed?SAPL(@"settings.pixie.alert.mode_0_restored.title",@"Mode 0 restored"):SAPL(@"settings.pixie.alert.mode_unchanged.title",@"Mode unchanged") message:reason];
            }];
        }]];
        [choice addAction:[UIAlertAction actionWithTitle:SAPL(@"common.cancel",@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:choice animated:YES completion:nil];return;
    }
    if(index.section==3 && index.row==1) {
        SAPDetailsSettings *page=[SAPDetailsSettings new];
        SAPShowPixiePage(self,page);return;
    }
    SAPSettingsAction action;
    if(index.section==0) {
        if(index.row==([self.snapshot[@"download_active"]boolValue]?3:2))return;
        const SAPSettingsAction actions[]={SAPSettingsDownload,SAPSettingsDownloadAlbum,SAPSettingsCancelDownload};
        if(index.row<0||index.row>=3)return;action=actions[index.row];
    }
    else return;
    [SAPSettingsActions perform:action];
    if(action==SAPSettingsCancelDownload)[self refresh];
}
@end

// Embedded footer is a view/data source, not a child view controller. The
// existing SwiftUI hosting controller retains sole ownership of its view tree.
@interface SAPDownloadsEntry : NSObject <UITableViewDataSource,UITableViewDelegate>
@property(nonatomic,weak) UIViewController *settingsHost;
@property(nonatomic,strong) UITableView *view;
@end
@implementation SAPDownloadsEntry
- (instancetype)init {
    if((self=[super init])) {
        self.view=[[UITableView alloc]initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
        self.view.dataSource=self;self.view.delegate=self;
        self.view.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
        self.view.rowHeight=UITableViewAutomaticDimension;self.view.estimatedRowHeight=76;
        self.view.scrollEnabled=NO;self.view.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever;
        self.view.backgroundColor=UIColor.clearColor;self.view.accessibilityIdentifier=@"SpotifyTrackDownloadsSection";
    }
    return self;
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {return 1;}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {return 1;}
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section {return SAPL(@"settings.pixie.manager.title",@"Pixie Download Manager");}
- (void)tableView:(UITableView *)table willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    if([view isKindOfClass:UITableViewHeaderFooterView.class]) {
        UITableViewHeaderFooterView *header=(id)view;
        header.textLabel.text=SAPL(@"settings.pixie.manager.title",@"Pixie Download Manager");
        header.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
        header.textLabel.textColor=UIColor.secondaryLabelColor;
    }
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    return SAPSettingsCell(table,SAPL(@"settings.pixie.entry.manage_downloads.title",@"Manage downloads"),SAPL(@"settings.pixie.entry.manage_downloads.subtitle",@"Current track, mode and download status"),@"arrow.down.circle.fill",UIColor.systemGreenColor,YES);
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    [table deselectRowAtIndexPath:index animated:YES];
    if(index.row==0)SAPShowPixiePage(self.settingsHost,[SAPDownloadsSettings new]);
}
@end

@interface SAPSettingsAttachment : NSObject
@property(nonatomic,weak) UIViewController *host;
@property(nonatomic,weak) UIScrollView *scroll;
@property(nonatomic,strong) SAPDownloadsEntry *entry;
@property(nonatomic,strong) SAPBottomChrome *bottomChrome;
@property(nonatomic) CGFloat baseBottom,appliedBottom;
@property(nonatomic) BOOL observing,updating;
- (void)layout;
@end
@implementation SAPSettingsAttachment
- (void)dealloc {
    if(_observing && _scroll)[_scroll removeObserver:self forKeyPath:@"contentSize" context:SAPContentSizeContext];
}
- (void)layout {
    if(self.updating || !self.scroll || !self.host.view.window)return;
    self.updating=YES;
    UIScrollView *scroll=self.scroll;
    CGFloat height=[[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]scaledValueForValue:232];
    if(fabs(scroll.contentInset.bottom-self.appliedBottom)>0.5)self.baseBottom=scroll.contentInset.bottom;
    // Eevee ends its SwiftUI List with a separate, empty Spacer section.
    // Start after the final real footer, before that reserved blank space.
    CGFloat start=scroll.contentSize.height;
    if([scroll isKindOfClass:UICollectionView.class]) {
        UICollectionView *list=(id)scroll;
        for(NSInteger section=list.numberOfSections-1;section>=0;section--) {
            UICollectionViewLayoutAttributes *footer=[list.collectionViewLayout layoutAttributesForSupplementaryViewOfKind:UICollectionElementKindSectionFooter atIndexPath:[NSIndexPath indexPathForItem:0 inSection:section]];
            if(footer && footer.frame.size.height>1){start=CGRectGetMaxY(footer.frame);break;}
        }
    }else if([scroll isKindOfClass:UITableView.class]) {
        UITableView *list=(id)scroll;
        for(NSInteger section=list.numberOfSections-1;section>=0;section--) {
            CGRect footer=[list rectForFooterInSection:section];
            if(footer.size.height>1){start=CGRectGetMaxY(footer);break;}
        }
    }
    CGRect frame=CGRectMake(0,start,scroll.bounds.size.width,height);
    if(!CGRectEqualToRect(self.entry.view.frame,frame))self.entry.view.frame=frame;
    if(self.entry.view.superview!=scroll)[scroll addSubview:self.entry.view];
    if(scroll.subviews.lastObject!=self.entry.view)[scroll bringSubviewToFront:self.entry.view];
    CGFloat extension=MAX(0,start+height-scroll.contentSize.height);
    UIEdgeInsets inset=scroll.contentInset;
    self.appliedBottom=SAPBottomInset(scroll,self.bottomChrome,self.baseBottom)+extension;
    if(fabs(inset.bottom-self.appliedBottom)>0.5){inset.bottom=self.appliedBottom;scroll.contentInset=inset;}
    UIEdgeInsets indicator=scroll.verticalScrollIndicatorInsets;
    indicator.bottom=MAX(self.baseBottom,self.appliedBottom-extension);
    if(!UIEdgeInsetsEqualToEdgeInsets(indicator,scroll.verticalScrollIndicatorInsets))scroll.verticalScrollIndicatorInsets=indicator;
    self.updating=NO;
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if(context!=SAPContentSizeContext){[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];return;}
    if(NSThread.isMainThread)[self layout];else dispatch_async(dispatch_get_main_queue(),^{[self layout];});
}
@end
static UIScrollView *SAPSettingsList(UIView *root,CGFloat width,unsigned depth) {
    if(depth>12)return nil;
    if([root isKindOfClass:UIScrollView.class] && root.bounds.size.width>width*0.65 &&
        ([root isKindOfClass:UITableView.class] || [root isKindOfClass:UICollectionView.class]))return (id)root;
    for(UIView *view in root.subviews){UIScrollView *found=SAPSettingsList(view,width,depth+1);if(found)return found;}
    return nil;
}
static void SAPAttachSettings(UIViewController *host) {
    if(![host.title isEqual:@"EeveeSpotify"])return;
    SAPSettingsAttachment *attachment=objc_getAssociatedObject(host,SAPAttachmentKey);
    if(attachment){[attachment layout];return;}
    UIScrollView *list=SAPSettingsList(host.view,host.view.bounds.size.width,0);if(!list)return;
    attachment=[SAPSettingsAttachment new];attachment.host=host;attachment.scroll=list;
    attachment.bottomChrome=[SAPBottomChrome new];
    attachment.baseBottom=list.contentInset.bottom;attachment.appliedBottom=list.contentInset.bottom;
    SAPDownloadsEntry *entry=[SAPDownloadsEntry new];entry.settingsHost=host;attachment.entry=entry;
    [list addSubview:entry.view];
    objc_setAssociatedObject(host,SAPAttachmentKey,attachment,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [list addObserver:attachment forKeyPath:@"contentSize" options:NSKeyValueObservingOptionNew context:SAPContentSizeContext];attachment.observing=YES;
    [attachment layout];
}
static void SAPSettingsLoaded(id self,SEL selector) {originalSettingsLoad(self,selector);SAPAttachSettings(self);}
static void SAPSettingsLayout(id self,SEL selector) {originalSettingsLayout(self,selector);SAPAttachSettings(self);}
static void *SAPModPageInit(void *self,SEL selector,NSString *title,NSString *intro,NSArray *sections,NSString *footer) {
    if([title isEqualToString:@"Retrine"] || [title isEqualToString:@"Vitrine"]) {
        id (*pageRow)(NSString *,UIViewController *(^)(void))=dlsym(RTLD_DEFAULT,"SGPageRow");
        id (*identify)(id,NSString *)=dlsym(RTLD_DEFAULT,"SGSearchIdentified");
        id (*keywords)(id,NSString *)=dlsym(RTLD_DEFAULT,"SGSearchKeywords");
        id (*withTile)(id,NSString *,UIColor *)=dlsym(RTLD_DEFAULT,"SGWithTile");
        id (*section)(NSString *,NSArray *)=dlsym(RTLD_DEFAULT,"SGSection");
        if(pageRow && withTile && section) {
            id row=pageRow(SAPL(@"settings.pixie.downloads.title",@"Pixie downloads"),^UIViewController *{return [SAPDownloadsSettings new];});
            row=withTile(row,@"arrow.down.circle.fill",UIColor.systemGreenColor);
            if(identify)identify(row,@"page.pixie");
            if(keywords)keywords(row,SAPL(@"settings.pixie.downloads.keywords",@"downloads offline files diagnostics send log"));
            // Find Privacy by its stable page ID, not its translated heading or the number of warning cards.
            BOOL placed=NO;
            for(id group in sections) {
                if(![group respondsToSelector:@selector(rows)] || ![group respondsToSelector:@selector(setRows:)])continue;
                NSArray *rows=[group valueForKey:@"rows"];
                for(id entry in rows) {
                    if(![entry respondsToSelector:@selector(searchIdentifier)] || ![[entry valueForKey:@"searchIdentifier"] isEqual:@"page.ads"])continue;
                    [group setValue:[rows arrayByAddingObject:row] forKey:@"rows"];
                    placed=YES;break;
                }
                if(placed)break;
            }
            if(!placed) {
                NSMutableArray *groups=[sections mutableCopy] ?: [NSMutableArray array];
                [groups insertObject:section(nil,@[row]) atIndex:groups.count ? groups.count-1 : 0];
                sections=groups;
            }
            SAP_TRACE("ui","pixie_rows_added_to_retrine",0,@{@"added_rows":@1,@"root_title":title});
        }else {
            settingsInstallStatus=@"retrine_row_factories_unavailable";
        }
    }
    return originalModPageInit(self,selector,title,intro,sections,footer);
}
void SAPInstallDownloadSettings(void) {
    if(!SAPRuntimeProfileAdmitted())return;
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{SAPInstallDownloadSettings();});return;}
    if(settingsInstalled)return;
    Class modPage=NSClassFromString(@"SGModPage");
    SEL init=NSSelectorFromString(@"initWithTitle:intro:sections:footer:");
    Method method=modPage?class_getInstanceMethod(modPage,init):NULL;
    if(method&&method_getNumberOfArguments(method)==6) {
        originalModPageInit=(void *)method_getImplementation(method);
        class_replaceMethod(modPage,init,(IMP)SAPModPageInit,method_getTypeEncoding(method));
        settingsInstalled=YES;settingsInstallStatus=@"retrine_page_hook_installed";return;
    }
        #ifdef SAP_UI_FIXTURE
        Class cls=NSClassFromString(@"SAPFixtureEeveeSettingsViewController");
#else
        Class cls=NSClassFromString(@"EeveeSpotify.EeveeSettingsViewController");
#endif
        if(!cls)cls=NSClassFromString(@"_TtC12EeveeSpotify27EeveeSettingsViewController");
        if(!cls){settingsInstallStatus=modPage?@"retrine_page_signature_unavailable":@"settings_host_not_loaded";return;}
        SEL load=@selector(viewDidLoad),layout=@selector(viewDidLayoutSubviews);
        Method lm=class_getInstanceMethod(cls,load),dm=class_getInstanceMethod(cls,layout);
        if(!lm || !dm || method_getNumberOfArguments(lm)!=2 || method_getNumberOfArguments(dm)!=2){settingsInstallStatus=@"settings_host_signature_mismatch";return;}
        originalSettingsLoad=(void *)method_getImplementation(lm);originalSettingsLayout=(void *)method_getImplementation(dm);
        // Add overrides only to Eevee's existing controller; inherited UIKit methods are not changed.
        class_replaceMethod(cls,load,(IMP)SAPSettingsLoaded,method_getTypeEncoding(lm));
        class_replaceMethod(cls,layout,(IMP)SAPSettingsLayout,method_getTypeEncoding(dm));
        settingsInstalled=YES;settingsInstallStatus=@"settings_host_hook_installed";
}

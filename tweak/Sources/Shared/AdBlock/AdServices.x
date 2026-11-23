// EeveeSpotify's service suppression, extended from EeveeSpotifyReincarnated d4daa49.
// Only verified Objective-C selectors are added; several upstream Swift services
// have no Objective-C -load there. The audit records those explicitly rather than inventing it.
// AdServices owns both the target list and installation. Existing load hooks are kept for older
// versions, but each now requires a compatible method; the two view fallbacks stay separate.
#import "Core/SGCore.h"
#import "AdBlock.h"

typedef struct {
    const char *className;
    const char *selector;
    BOOL upsell;
} SGServiceTarget;

static const SGServiceTarget serviceTargets[] = {
    {"_TtC19AdsPlatform_AdsImpl14AdsServiceImpl", "load", NO},
    {"_TtC29AdsNowPlaying_InStreamAdsImpl18InStreamAdsService", "load", NO},
    {"_TtC29AdsNowPlaying_EmbeddedNPVImpl22EmbeddedNPVServiceImpl", "load", NO},
    {"_TtC36AdsStandalone_LeavebehindAdsBaseImpl25LeavebehindAdsBaseService", "load", NO},
    {"_TtC36AdsStandalone_LeavebehindAdsBaseImpl33LeavebehindAdsBaseInternalService", "load", NO},
    {"_TtC35AdsEmbedded_AdsSponsoredContextImpl30AdsSponsoredContextServiceImpl", "load", NO},
    {"_TtC48AdsEmbedded_AdsSponsoredContextNPBAttachmentImpl43AdsSponsoredContextNPBAttachmentServiceImpl", "load", NO},
    {"_TtC42AdsEmbedded_AdsSponsoredPlaylistHeaderImpl37AdsSponsoredPlaylistHeaderServiceImpl", "load", NO},
    {"_TtC20NativeAds_LoggerImpl26NativeAdsLoggerServiceImpl", "load", NO},
    // This class registers scroll cards; unlike Eevee's hook, do not add a nonexistent -load.
    {"_TtC32AdsEmbedded_EmbeddedCTACardsImpl23EmbeddedCTACardsService", "registerScrollProviderIn:", NO},
    {"_TtC28AdsPlatform_AdsBaseSwiftImpl23AdsBaseSwiftServiceImpl", "load", NO},
    {"_TtC23AdsPlatform_AdsBaseImpl18AdsBaseServiceImpl", "load", NO},
    {"_TtC46Betamax_AudioAdPictureInPictureCoordinatorImpl41AudioAdPictureInPictureCoordinatorService", "load", NO},
    {"_TtC28AdsStandalone_RewardedAdImpl32RewardedAdFetchControllerService", "load", NO},
    {"_TtC29AdsStandalone_AdOnAppOpenImpl22AdOnAppOpenServiceImpl", "load", NO},
    {"_TtC32AdsEmbedded_EmbeddedPlaylistImpl27EmbeddedPlaylistServiceImpl", "load", NO},
    {"_TtC28AdsStandalone_RewardedAdImpl28OnDemandAdEventLoggerService", "load", NO},
    {"_TtC19Upsells_ServiceImpl18UpsellsServiceImpl", "load", YES},
    {"_TtC31PremiumUpsell_UpsellServiceImpl17UpsellServiceImpl", "load", YES},
    {"_TtC45ReinventFree_ContextualUpsellPremiumPromoImpl39ContextualUpsellPremiumPromoServiceImpl", "load", YES},
    {"_TtC40Referrals_ReferralsUpsellCardElementImpl37ReferralsUpsellCardElementServiceImpl", "load", YES},
    {"_TtC31ReinventFree_DownloadUpsellImpl21DownloadUpsellService", "load", YES},
    {"_TtC28Jam_FreeHostedJamsUpsellImpl31FreeHostedJamsUpsellServiceImpl", "load", YES},
    {"_TtC30Jam_FreeUserSkipUpsellPageImpl29FreeUserSkipUpsellPageService", "load", YES},
    {"_TtC38Jam_FreeUserShuffleUpsellSheetPageImpl37FreeUserShuffleUpsellSheetPageService", "load", YES},
};

static Method compatibleMethod(Class cls, SEL selector, unsigned arguments) {
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (!method || method_getNumberOfArguments(method) != arguments) return NULL;
    char type[2];
    method_getReturnType(method, type, sizeof(type));
    if (type[0] != 'v') return NULL;
    if (arguments == 3) {
        method_getArgumentType(method, 2, type, sizeof(type));
        if (type[0] != '@') return NULL;
    }
    return method;
}

static void stopAdService(id self, SEL selector) { SGAdBlockCountOne(@"Ad services"); }
static void stopUpsellService(id self, SEL selector) { SGAdBlockCountOne(@"Upsell services"); }
static void stopScrollProvider(id self, SEL selector, id registry) { SGAdBlockCountOne(@"Ad services"); }

static void installServices(void) {
    for (size_t i = 0; i < sizeof(serviceTargets) / sizeof(serviceTargets[0]); i++) {
        const SGServiceTarget *target = &serviceTargets[i];
        if (!SGHidden(target->upsell ? SGKeyHideUpsells : SGKeyHideAds)) continue;
        Class cls = objc_getClass(target->className);
        SEL selector = sel_registerName(target->selector);
        BOOL scrollProvider = selector == @selector(registerScrollProviderIn:);
        Method method = compatibleMethod(cls, selector, scrollProvider ? 3 : 2);
        if (!method) continue;
        IMP replacement = scrollProvider ? (IMP)stopScrollProvider :
            (target->upsell ? (IMP)stopUpsellService : (IMP)stopAdService);
        // No original is called. Replacing on the target class (not its Method) also keeps
        // an inherited implementation intact for unrelated services on older versions.
        class_replaceMethod(cls, selector, replacement, method_getTypeEncoding(method));
    }
}

static void takeDown(UIView *view) {
    view.hidden = YES;
    view.userInteractionEnabled = NO;
    if (view.superview) [view removeFromSuperview];
}

%group AdViews

%hook _TtC18AdsPlatform_ECMKit37AdsSponsoredPlaylistHeaderCentralView
- (void)didMoveToSuperview {
    %orig;
    takeDown((UIView *)self);
}
%end

%end

%group UpsellViews

%hook _TtC13Upsells_UIKit29SelfLoadingUpsellBannerUIView
- (void)didMoveToSuperview {
    %orig;
    takeDown((UIView *)self);
}
%end

%end

%ctor {
    installServices();
    SEL selector = @selector(didMoveToSuperview);
    Class adView = objc_getClass("_TtC18AdsPlatform_ECMKit37AdsSponsoredPlaylistHeaderCentralView");
    if (SGHidden(SGKeyHideAds) && [adView isSubclassOfClass:UIView.class] &&
        compatibleMethod(adView, selector, 2)) {
        %init(AdViews);
    }
    Class upsellView = objc_getClass("_TtC13Upsells_UIKit29SelfLoadingUpsellBannerUIView");
    if (SGHidden(SGKeyHideUpsells) && [upsellView isSubclassOfClass:UIView.class] &&
        compatibleMethod(upsellView, selector, 2)) {
        %init(UpsellViews);
    }
}

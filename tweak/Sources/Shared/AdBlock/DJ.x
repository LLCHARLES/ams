// The DJ under Spoof Premium: Spotify offers it only where its playlist (spotify:playlist:37i9dQZF1EYkqdzj48dyYq)
// loads, which the checker below tries first. Answering yes gives the full DJ, requests included. A Free account
// is still told "DJ is not available in your country" at each start (DJMRegionUnavailableDialogEffectHandler, pure
// Swift) while the DJ plays on, so that dialog is closed before it shows.
#import "Core/SGCore.h"
#import "AdBlock.h"

@interface SPTEncorePopUpPresenter : NSObject
+ (instancetype)shared;
- (void)dismissPopupWithAnimate:(BOOL)animate clearQueue:(BOOL)clearQueue completion:(id)completion;
@end

%hook _TtC16Endless_AIDJImpl26AIDJEligibilityCheckerImpl
- (void)isEligibleForDJWithCompletion:(void (^)(BOOL))completion {
    if (completion) completion(YES);
}
%end

static id stringsAsset(NSBundle *bundle, NSString *name) {
    if (!bundle) return nil;
    NSData *data = [[NSDataAsset alloc] initWithName:name bundle:bundle].data;
    return data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
}

// Spotify's key and language assets share indexes. Missing title data must leave the dialog visible.
static NSSet<NSString *> *regionTitles(void) {
    static NSSet<NSString *> *titles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *path = [NSBundle.mainBundle pathForResource:@"SPTStrings" ofType:@"bundle"];
        NSBundle *strings = path ? [NSBundle bundleWithPath:path] : nil;
        NSArray *keys = stringsAsset(strings, @"_i18n.KEYS");
        NSDictionary *files = stringsAsset(strings, @"_i18n.INDEX");
        NSUInteger at = [keys isKindOfClass:NSArray.class] ? [keys indexOfObject:@"SPTEndless_DJMusicImpl:sDJMRegionUnavailableDialogTitle"] : NSNotFound;
        NSMutableSet<NSString *> *found = [NSMutableSet set];
        for (NSString *language in [NSBundle.mainBundle.preferredLocalizations arrayByAddingObject:@"en"]) {
            if (at == NSNotFound) break;
            NSString *file = [files isKindOfClass:NSDictionary.class] && [files[language] isKindOfClass:NSString.class] ? files[language] : language;
            NSArray *values = stringsAsset(strings, [@"_i18n." stringByAppendingString:file]);
            id value = [values isKindOfClass:NSArray.class] && at < values.count ? values[at] : nil;
            if ([value isKindOfClass:NSString.class]) [found addObject:value];
        }
        SGLog(@"DJ: the region dialog's titles in Spotify's strings: %@", found.count ? [found.allObjects componentsJoinedByString:@" | "] : @"none, so it stays");
        titles = found;
    });
    return titles;
}

// The title is set only by the container's first layout.
%hook PopUpContainer
- (void)viewDidLayoutSubviews {
    %orig;
    UIViewController *container = (UIViewController *)self;
    if (container.view.window.hidden) return;
    static char kTitleKey;
    NSString *title = ((UILabel *)SGFindIdentifier(container.view, @"PopUp.Dialog.Title-internal", &kTitleKey)).text;
    if (!title || ![regionTitles() containsObject:title]) return;
    Class cls = %c(SPTEncorePopUpPresenter);
    if (![cls respondsToSelector:@selector(shared)]) return;
    id presenter = [cls shared];
    if (![presenter respondsToSelector:@selector(dismissPopupWithAnimate:clearQueue:completion:)]) return;
    container.view.window.hidden = YES;
    [presenter dismissPopupWithAnimate:NO clearQueue:NO completion:nil];
    SGLog(@"DJ: closed \"%@\"", title);
}
%end

%ctor {
    if (!SGHidden(SGKeyFakePremium)) return;
    %init(PopUpContainer = objc_getClass("_TtC29EncoreConsumerMobile_Wrappers25PopUpPresentableContainer"));
    SGRequireClasses(@[@"_TtC16Endless_AIDJImpl26AIDJEligibilityCheckerImpl", @"_TtC29EncoreConsumerMobile_Wrappers25PopUpPresentableContainer"]);
}

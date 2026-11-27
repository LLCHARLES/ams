// FontImport.m as the tweak compiles it, with Core Text's registration replaced by check.m's double (the same one
// FontLibrary.m uses there), so the imported family's registration can be held and counted like the library's.
#import <CoreText/CoreText.h>
#import "../harness-fail.h"
#import "Settings/SGPageStyle.h"
static NSUInteger notices;
static void notice(UIViewController *presenter, NSString *title, NSString *message) {
    notices++;
    SGPresentInformation(presenter, title, message);
}
#define SGPresentInformation notice
bool harnessRegister(CFURLRef url, CTFontManagerScope scope, CFErrorRef *error);
#define CTFontManagerRegisterFontsForURL harnessRegister
static BOOL inspected;
static CFArrayRef inspectFont(CFURLRef url) CF_RETURNS_RETAINED {
    inspected = YES;
    return CTFontManagerCreateFontDescriptorsFromURL(url);
}
#define CTFontManagerCreateFontDescriptorsFromURL inspectFont
// A Files provider whose materialized URL is available only inside the coordinated accessor.
static NSURL *placeholder, *providerMetadata, *providerFile;
static BOOL contentRequested;
@interface SGFontTestCoordinator : NSFileCoordinator
@end
@implementation SGFontTestCoordinator
- (void)coordinateReadingItemAtURL:(NSURL *)url options:(NSFileCoordinatorReadingOptions)options
    error:(NSError **)error byAccessor:(void (NS_NOESCAPE ^)(NSURL *))reader {
    if ([url isEqual:placeholder]) {
        if (options & NSFileCoordinatorReadingImmediatelyAvailableMetadataOnly) url = providerMetadata;
        else { contentRequested = YES; url = providerFile; }
    }
    [super coordinateReadingItemAtURL:url options:options error:error byAccessor:reader];
}
@end
#define NSFileCoordinator SGFontTestCoordinator
#import "Shared/Fonts/FontImport.m"

dispatch_queue_t harnessImportQueue(void) { return registrationQueue(); }

void harnessImportPlaceholder(NSURL *url, NSURL *metadata, NSURL *materialized, void (^done)(BOOL)) {
    placeholder = url; providerMetadata = metadata; providerFile = materialized; contentRequested = NO;
    import(@[url], ^{ placeholder = providerMetadata = providerFile = nil; done(contentRequested); });
}
void harnessRemoveCustom(dispatch_block_t done) { removeImported(importIdentity(), done); }
void harnessImport(NSURL *url, dispatch_block_t done) { import(@[url], done); }
void harnessImportFiles(NSArray *urls, dispatch_block_t done) {
    inspected = NO;
    import(urls, ^{
        HARNESS_CHECK(!inspected); // a rejected batch must not stage and parse an earlier pick
        done();
    });
}
NSArray *harnessStoredFontNames(void) { return [storedFiles() valueForKey:@"lastPathComponent"]; }

void harnessRejectedImport(NSURL *invalid, void (^done)(BOOL)) {
    NSUInteger before = notices;
    __block BOOL notified = NO;
    import(@[invalid], ^{ notified = notices == before + 1; });
    // Both operations publish on main in submission order. The next fixture needs the
    // stale swipe to have cleared its pending flag before it requests registration.
    removeImported(@{}, ^{ done(notified); });
}

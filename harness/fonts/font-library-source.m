// Compile the real catalog/service, substituting only the download/installation
// boundary while the selection regression holds a completion. The page and selection guard stay real.
#define SGFontLibraryDownload SGRealFontLibraryDownload
#define SGFontLibraryDownloading SGRealFontLibraryDownloading
#define SGFontLibraryInstalled SGRealFontLibraryInstalled
#define SGFontLibraryRegister SGRealFontLibraryRegister
#define SGFontLibraryRegisterAsync SGRealFontLibraryRegisterAsync
#import "Shared/Fonts/FontLibrary.m"
#undef SGFontLibraryDownload
#undef SGFontLibraryDownloading
#undef SGFontLibraryInstalled
#undef SGFontLibraryRegister
#undef SGFontLibraryRegisterAsync
#import "font-library-source.h"
#import "../harness-fail.h"

static NSMutableSet<NSString *> *installedFonts;
static NSString *pendingFont;
static void (^pendingCompletion)(NSString *);
static NSUInteger landingsPending;

void SGHarnessHoldFontDownloads(NSArray<NSString *> *installed) {
    HARNESS_CHECK(!pendingCompletion);
    installedFonts = installed ? [NSMutableSet setWithArray:installed] : nil;
}

BOOL SGFontLibraryInstalled(NSString *identifier) {
    return installedFonts ? [installedFonts containsObject:identifier] : SGRealFontLibraryInstalled(identifier);
}

NSString *SGFontLibraryRegister(NSString *identifier) {
    if (!installedFonts) return SGRealFontLibraryRegister(identifier);
    return [installedFonts containsObject:identifier] ? @"Chalkduster" : nil;
}

// As production: nothing registers on the caller, and the answer lands on main in a later turn.
void SGFontLibraryRegisterAsync(NSString *identifier, void (^done)(NSString *family)) {
    if (!installedFonts) {
        SGRealFontLibraryRegisterAsync(identifier, done);
        return;
    }
    landingsPending++;
    dispatch_async(dispatch_get_main_queue(), ^{
        landingsPending--;
        if (done) done([installedFonts containsObject:identifier] ? @"Chalkduster" : nil);
    });
}

NSString *SGFontLibraryDownloading(void) {
    return installedFonts ? pendingFont : SGRealFontLibraryDownloading();
}

void SGFontLibraryDownload(NSString *identifier, void (^done)(NSString *)) {
    if (!installedFonts) {
        SGRealFontLibraryDownload(identifier, done);
        return;
    }
    HARNESS_CHECK(!pendingCompletion);
    pendingFont = [identifier copy];
    pendingCompletion = [done copy];
}

void SGHarnessFinishFontDownload(void) {
    HARNESS_CHECK(pendingCompletion && pendingFont);
    [installedFonts addObject:pendingFont];
    void (^done)(NSString *) = pendingCompletion;
    pendingCompletion = nil;
    pendingFont = nil;
    done(nil);
    // The registration the completion asked for lands on main in a later turn; the caller checks what it did.
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:60];
    while (landingsPending && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    HARNESS_CHECK(!landingsPending);
}

// The free fonts page and FontLibrary.m's registration: opening the page registers no font on the main
// thread; every installed family is registered on the library's queue, then published and announced on main.
// Core Text is replaced at the two calls FontLibrary.m makes (the descriptors of a file, its registration)
// so a fixture file of the catalog's size stands for a font; the family it answers is Helvetica.
#import <CoreText/CoreText.h>
#import <UIKit/UIKit.h>
#import <stdatomic.h>
#import "../harness-fail.h"

static atomic_int sg_mainCalls, sg_workerCalls;
extern void harnessRemoveCustom(dispatch_block_t done);
extern void harnessImport(NSURL *url, dispatch_block_t done);
extern void harnessImportFiles(NSArray *urls, dispatch_block_t done);
extern void harnessImportPlaceholder(NSURL *url, NSURL *metadata, NSURL *materialized, void (^done)(BOOL));
extern NSArray *harnessStoredFontNames(void);
extern void harnessRejectedImport(NSURL *invalid, void (^done)(BOOL));
// While set, a registration enters and waits here, as a multi-MB Korean font takes its time in Core Text; the
// imported font's file waits on a semaphore of its own, so the two kinds land one after the other.
static dispatch_semaphore_t sg_holdRegistration, sg_holdImported;
static atomic_uint sg_registrationEntries;
static CFArrayRef harnessDescriptors(CFURLRef url) {
    atomic_fetch_add(NSThread.isMainThread ? &sg_mainCalls : &sg_workerCalls, 1);
    CTFontDescriptorRef face = CTFontDescriptorCreateWithNameAndSize(CFSTR("Helvetica"), 12);
    CFArrayRef faces = CFArrayCreate(NULL, (const void **)&face, 1, &kCFTypeArrayCallBacks);
    CFRelease(face);
    return faces;
}
bool harnessRegister(CFURLRef url, CTFontManagerScope scope, CFErrorRef *error) {
    atomic_fetch_add(NSThread.isMainThread ? &sg_mainCalls : &sg_workerCalls, 1);
    dispatch_semaphore_t hold = [((__bridge NSURL *)url).lastPathComponent isEqual:@"Harness.ttf"] ? sg_holdImported : sg_holdRegistration;
    if (hold) {
        atomic_fetch_add(&sg_registrationEntries, 1);
        if (dispatch_semaphore_wait(hold, dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC)))
            HARNESS_FAIL(@"registration of %@ stayed held", [(__bridge NSURL *)url lastPathComponent]);
        HARNESS_CHECK([NSFileManager.defaultManager fileExistsAtPath:[(__bridge NSURL *)url path]]);
    }
    return true;
}
static bool harnessUnregister(CFURLRef url, CTFontManagerScope scope, CFErrorRef *error) {
    return true;
}
#define CTFontManagerCreateFontDescriptorsFromURL harnessDescriptors
#define CTFontManagerRegisterFontsForURL harnessRegister
#define CTFontManagerUnregisterFontsForURL harnessUnregister
#import "Shared/Fonts/FontLibrary.m"
#import "Settings/SGModPage.h"
#import "Shared/LyricsPiP/LyricsPiPStyle.h"
#import "Shared/LyricsPiP/LyricsPiP.h"

SGAppFont SGAppFontChosen(void) { return (SGAppFont)[NSUserDefaults.standardUserDefaults integerForKey:SGKeyAppFont]; }
NSArray<NSString *> *SGAppFontNames(void) { return @[]; }
NSArray<NSString *> *SGAppFontFamilies(void) { return @[]; }

static void pumpUntilAt(BOOL (^done)(void), int line) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:60];
    while (!done() && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    if (!done()) HARNESS_FAIL(@"condition at check.m:%d did not become true", line);
}
#define pumpUntil(...) pumpUntilAt(__VA_ARGS__, __LINE__)

extern dispatch_queue_t harnessImportQueue(void);
static void drainRegistrations(dispatch_queue_t worker) {
    __block BOOL drained = NO;
    dispatch_async(worker, ^{
        dispatch_async(dispatch_get_main_queue(), ^{ drained = YES; });
    });
    pumpUntil(^BOOL { return drained; });
}

// A reader can submit registration on the next main-queue turn. Don't park main waiting for it.
static void awaitRegistrations(unsigned count) {
    pumpUntil(^BOOL { return atomic_load(&sg_registrationEntries) >= count; });
}

// A file of exactly the catalog's size, which is all SGFontLibraryInstalled asks of it.
static void install(NSString *identifier) {
    NSFileManager *files = NSFileManager.defaultManager;
    for (size_t i = 0; i < sizeof kFamilies / sizeof *kFamilies; i++) {
        if (![kFamilies[i].identifier isEqualToString:identifier]) continue;
        HARNESS_CHECK([files createDirectoryAtURL:familyFolder(identifier) withIntermediateDirectories:YES attributes:nil error:nil]);
        for (const SGFontFileLine *file = kFamilies[i].files; file < kFamilies[i].files + 5 && file->name; file++) {
            NSString *path = [familyFolder(identifier) URLByAppendingPathComponent:file->name].path;
            HARNESS_CHECK([files createFileAtPath:path contents:nil attributes:nil]);
            NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
            HARNESS_CHECK([handle truncateAtOffset:(unsigned long long)file->size error:nil]);
            [handle closeFile];
        }
        return;
    }
    HARNESS_FAIL(@"%@ is not in the catalog", identifier);
}

// The download the Free fonts page asks for, finished at once: the family's files are there and the page's
// completion runs on main, as FontLibrary.m's does when the last file checks out.
void harnessDownload(NSString *identifier, void (^done)(NSString *error)) {
    install(identifier);
    dispatch_async(dispatch_get_main_queue(), ^{ done(nil); });
}

static NSString *rowFamily(UITableViewController *page, NSString *identifier) {
    SGLibraryFont *font = SGFontLibraryFont(identifier);
    NSUInteger row = [[SGFontLibrary() filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"korean == %@", @(font.korean)]] indexOfObject:font];
    NSIndexPath *path = [NSIndexPath indexPathForRow:(NSInteger)row inSection:font.korean ? 0 : 1];
    UITableViewCell *cell = [page tableView:page.tableView cellForRowAtIndexPath:path];
    return ((UIListContentConfiguration *)cell.contentConfiguration).textProperties.font.familyName;
}

// The family the Font page's preview of the free font named `name` is drawn in, as the table shows it now.
static NSString *pickerPreviewFamily(UITableViewController *page, NSString *name) {
    [page.tableView layoutIfNeeded];
    for (UITableViewCell *cell in page.tableView.visibleCells) {
        UIListContentConfiguration *content = (UIListContentConfiguration *)cell.contentConfiguration;
        if ([content.text isEqual:name]) return content.textProperties.font.familyName;
    }
    HARNESS_FAIL(@"the Font page shows no row for %@", name);
}

int main(void) { @autoreleasepool {
    [NSFileManager.defaultManager removeItemAtURL:libraryFolder() error:nil];
    install(@"nanumgothic");
    install(@"lato");

    __block NSMutableArray<NSString *> *announced = [NSMutableArray array];
    id token = [NSNotificationCenter.defaultCenter addObserverForName:SGFontLibraryChangedNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            HARNESS_CHECK(NSThread.isMainThread);
            [announced addObject:note.userInfo[@"identifier"]];
        }];

    // Opening the page registers nothing on main, and nothing is published until main runs again.
    UITableViewController *page = (UITableViewController *)SGFontLibraryPage();
    [page loadViewIfNeeded];
    HARNESS_CHECK(atomic_load(&sg_mainCalls) == 0);
    HARNESS_CHECK(!SGFontLibraryRegisteredFamily(@"lato") && !SGFontLibraryRegisteredFamily(@"nanumgothic"));
    HARNESS_CHECK(![rowFamily(page, @"lato") isEqual:@"Helvetica"]);

    pumpUntil(^BOOL { return announced.count == 2; });
    HARNESS_CHECK([SGFontLibraryRegisteredFamily(@"lato") isEqual:@"Helvetica"]);
    HARNESS_CHECK([SGFontLibraryRegisteredFamily(@"nanumgothic") isEqual:@"Helvetica"]);
    HARNESS_CHECK([announced containsObject:@"lato"] && [announced containsObject:@"nanumgothic"]);
    HARNESS_CHECK([rowFamily(page, @"lato") isEqual:@"Helvetica"]);
    // Two families of two and three files: each file registered once, each family described once, none on main.
    HARNESS_CHECK(atomic_load(&sg_workerCalls) == 7 && atomic_load(&sg_mainCalls) == 0);

    // Opening it again registers nothing twice and announces nothing new.
    SGFontLibraryRegisterInstalled();
    drainRegistrations(registrationQueue());
    HARNESS_CHECK(announced.count == 2 && atomic_load(&sg_workerCalls) == 7);

    // A removal behind a pending registration wins: the family is never published after it.
    [announced removeAllObjects];
    install(@"poppins");
    install(@"jua");
    SGFontLibraryRegisterInstalled();
    SGFontLibraryRemove(@"poppins");
    HARNESS_CHECK(!SGFontLibraryInstalled(@"poppins") && !SGFontLibraryRegisteredFamily(@"poppins"));
    pumpUntil(^BOOL { return [announced containsObject:@"jua"]; });
    drainRegistrations(registrationQueue());
    HARNESS_CHECK(!SGFontLibraryRegisteredFamily(@"poppins"));

    // The synchronous entry still answers a family nothing has registered yet, and publishes it.
    install(@"barlow");
    HARNESS_CHECK(!SGFontLibraryRegisteredFamily(@"barlow"));
    HARNESS_CHECK([SGFontLibraryRegister(@"barlow") isEqual:@"Helvetica"]);
    HARNESS_CHECK([SGFontLibraryRegisteredFamily(@"barlow") isEqual:@"Helvetica"]);

    [NSNotificationCenter.defaultCenter removeObserver:token];
    for (NSString *identifier in @[@"nanumgothic", @"lato", @"jua", @"barlow"]) SGFontLibraryRemove(identifier);
    [NSFileManager.defaultManager removeItemAtURL:libraryFolder() error:nil];

    // The Font page (FontImport.m) with two Korean families installed, a font of the user's own imported, and
    // Core Text holding every registration: opening it asks for them without waiting, so a block queued on main
    // runs while Core Text is still busy, and the previews turn into their fonts when the registrations land.
    install(@"gowundodum");
    install(@"dohyeon");
    NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *importedFolder = [[support URLByAppendingPathComponent:@"Retrine" isDirectory:YES] URLByAppendingPathComponent:@"Font" isDirectory:YES];
    HARNESS_CHECK([NSFileManager.defaultManager createDirectoryAtURL:importedFolder withIntermediateDirectories:YES attributes:nil error:nil]);
    HARNESS_CHECK([NSFileManager.defaultManager createFileAtPath:[importedFolder URLByAppendingPathComponent:@"Harness.ttf"].path contents:nil attributes:nil]);
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    [store setObject:@[@"Harness.ttf", @"..", @"."] forKey:SGKeyAppFontFiles];
    HARNESS_CHECK([harnessStoredFontNames() isEqual:@[@"Harness.ttf"]]);
    [store setObject:@[@42] forKey:SGKeyAppFontFiles];
    HARNESS_CHECK(!harnessStoredFontNames().count);
    [store setObject:@[@"Harness.ttf"] forKey:SGKeyAppFontFiles];
    [store setObject:@"Helvetica" forKey:SGKeyAppFontName];
    atomic_store(&sg_mainCalls, 0);   // the synchronous entry above ran its registration on the calling thread
    sg_holdRegistration = dispatch_semaphore_create(0);
    sg_holdImported = dispatch_semaphore_create(0);
    atomic_store(&sg_registrationEntries, 0);
    NSMutableSet<NSString *> *pickerAnnounced = [NSMutableSet set];
    id pickerToken = [NSNotificationCenter.defaultCenter addObserverForName:SGFontLibraryChangedNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) { [pickerAnnounced addObject:note.userInfo[@"identifier"]]; }];
    UITableViewController *picker = (UITableViewController *)SGAppFontRows().firstObject.page();
    [picker loadViewIfNeeded];   // a window needs the app's scene, which a command-line check does not have
    picker.tableView.frame = CGRectMake(0, 0, 390, 2400);
    [picker viewWillAppear:NO];
    // The library's queue and the imported font's each hold one registration.
    awaitRegistrations(2);
    __block BOOL queuedRan = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ queuedRan = YES; });
    pumpUntil(^BOOL { return queuedRan; });
    HARNESS_CHECK(!SGFontLibraryRegisteredFamily(@"dohyeon") && !SGFontLibraryRegisteredFamily(@"gowundodum"));
    HARNESS_CHECK(![pickerPreviewFamily(picker, @"Do Hyeon") isEqual:@"Helvetica"]);
    HARNESS_CHECK(![pickerPreviewFamily(picker, @"Helvetica") isEqual:@"Helvetica"]);
    // The library's families land first; the imported font is still waiting in Core Text.
    for (int release = 0; release < 2; release++) dispatch_semaphore_signal(sg_holdRegistration);
    pumpUntil(^BOOL { return [pickerAnnounced containsObject:@"dohyeon"] && [pickerAnnounced containsObject:@"gowundodum"]; });
    HARNESS_CHECK([pickerPreviewFamily(picker, @"Do Hyeon") isEqual:@"Helvetica"]);
    HARNESS_CHECK([pickerPreviewFamily(picker, @"Gowun Dodum") isEqual:@"Helvetica"]);
    HARNESS_CHECK(![pickerPreviewFamily(picker, @"Helvetica") isEqual:@"Helvetica"]);
    dispatch_semaphore_signal(sg_holdImported);
    pumpUntil(^BOOL { return [pickerPreviewFamily(picker, @"Helvetica") isEqual:@"Helvetica"]; });
    HARNESS_CHECK(atomic_load(&sg_mainCalls) == 0);
    sg_holdRegistration = sg_holdImported = nil;

    // Out of sight, a change reloads nothing; coming back shows it.
    [picker viewDidDisappear:NO];
    install(@"jua");
    NSInteger rows = [picker tableView:picker.tableView numberOfRowsInSection:2];
    [NSNotificationCenter.defaultCenter postNotificationName:SGFontLibraryChangedNotification object:nil userInfo:@{@"identifier": @"jua"}];
    HARNESS_CHECK([picker tableView:picker.tableView numberOfRowsInSection:2] == rows);
    [picker viewWillAppear:NO];
    HARNESS_CHECK([picker tableView:picker.tableView numberOfRowsInSection:2] == rows + 1);
    pumpUntil(^BOOL { return [pickerAnnounced containsObject:@"jua"]; });
    [store removeObjectForKey:SGKeyAppFontFiles];
    [store removeObjectForKey:SGKeyAppFontName];
    [NSFileManager.defaultManager removeItemAtURL:importedFolder error:nil];

    // The Free fonts page: a download that finishes while Core Text is busy leaves the page free; the family is
    // chosen and announced once its registration lands.
    atomic_store(&sg_registrationEntries, 0);
    sg_holdRegistration = dispatch_semaphore_create(0);
    UITableViewController *library = (UITableViewController *)SGFontLibraryPage();
    [library loadViewIfNeeded];
    SGLibraryFont *sunflower = SGFontLibraryFont(@"sunflower");
    NSUInteger sunflowerRow = [[SGFontLibrary() filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"korean == YES"]] indexOfObject:sunflower];
    HARNESS_CHECK(!SGFontLibraryInstalled(@"sunflower") && ![store stringForKey:SGKeyAppFontLibrary]);
    [library tableView:library.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)sunflowerRow inSection:0]];
    awaitRegistrations(1);
    queuedRan = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ queuedRan = YES; });
    pumpUntil(^BOOL { return queuedRan; });
    HARNESS_CHECK(!SGFontLibraryRegisteredFamily(@"sunflower") && ![store stringForKey:SGKeyAppFontLibrary]);
    for (int release = 0; release < 3; release++) dispatch_semaphore_signal(sg_holdRegistration);
    pumpUntil(^BOOL { return [[store stringForKey:SGKeyAppFontLibrary] isEqual:@"sunflower"]; });
    HARNESS_CHECK([SGFontLibraryRegisteredFamily(@"sunflower") isEqual:@"Helvetica"] && atomic_load(&sg_mainCalls) == 0);
    sg_holdRegistration = nil;
    [store removeObjectForKey:SGKeyAppFontLibrary];
    [store removeObjectForKey:SGKeyAppFont];

    [NSNotificationCenter.defaultCenter removeObserver:pickerToken];
    for (NSString *identifier in @[@"gowundodum", @"dohyeon", @"jua", @"sunflower"]) SGFontLibraryRemove(identifier);
    [NSFileManager.defaultManager removeItemAtURL:libraryFolder() error:nil];

    // The Lyrics PiP style (LyricsPiPStyle.m) with a downloaded family and an imported one, neither registered
    // yet, and Core Text holding both registrations: building the font choices and resolving the PiP font asks
    // for them without waiting, so a block queued on main runs while Core Text is still busy; the font system
    // stands in until they land, and then the choice is listed and the font resolves.
    install(@"nanumgothic");
    HARNESS_CHECK([NSFileManager.defaultManager createDirectoryAtURL:importedFolder withIntermediateDirectories:YES attributes:nil error:nil]);
    HARNESS_CHECK([NSFileManager.defaultManager createFileAtPath:[importedFolder URLByAppendingPathComponent:@"Harness.ttf"].path contents:nil attributes:nil]);
    [store setObject:@[@"Harness.ttf"] forKey:SGKeyAppFontFiles];
    [store setObject:@"Courier" forKey:SGKeyAppFontName];   // the family the imported file carries; the library's is Helvetica
    HARNESS_CHECK(!SGFontLibraryRegisteredFamily(@"nanumgothic") && !SGRegisteredCustomFont());
    atomic_store(&sg_mainCalls, 0);
    sg_holdRegistration = dispatch_semaphore_create(0);
    sg_holdImported = dispatch_semaphore_create(0);
    atomic_store(&sg_registrationEntries, 0);
    NSMutableSet<NSString *> *pipAnnounced = [NSMutableSet set];
    id pipToken = [NSNotificationCenter.defaultCenter addObserverForName:SGFontLibraryChangedNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) { [pipAnnounced addObject:note.userInfo[@"identifier"]]; }];
    // Resolving each PiP font asks for its family: the first starts the library's registration, the second the
    // imported file's.
    [store setObject:@"library:nanumgothic" forKey:SGKeyPiPFont];
    HARNESS_CHECK([SGLyricsPiPReadStyle().font isEqual:@"system"]);
    [store setObject:@"custom" forKey:SGKeyPiPFont];
    // A second reader need not ask in the same main-queue turn as the first one.
    dispatch_async(dispatch_get_main_queue(), ^{
        HARNESS_CHECK([SGLyricsPiPReadStyle().font isEqual:@"system"]);
    });
    awaitRegistrations(2);
    queuedRan = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ queuedRan = YES; });
    pumpUntil(^BOOL { return queuedRan; });
    HARNESS_CHECK(!SGLyricsPiPFontAvailable(@"library:nanumgothic") && !SGLyricsPiPFontAvailable(@"custom"));
    HARNESS_CHECK([SGLyricsPiPReadStyle().font isEqual:@"system"] && ![SGLyricsPiPFontName(@"custom") isEqual:@"Courier"]);
    HARNESS_CHECK(atomic_load(&sg_mainCalls) == 0);
    for (int release = 0; release < 5; release++) dispatch_semaphore_signal(sg_holdRegistration);
    dispatch_semaphore_signal(sg_holdImported);
    pumpUntil(^BOOL { return [pipAnnounced containsObject:@"nanumgothic"] && [pipAnnounced containsObject:@"custom"]; });
    HARNESS_CHECK(SGLyricsPiPFontAvailable(@"library:nanumgothic") && SGLyricsPiPFontAvailable(@"custom"));
    HARNESS_CHECK([SGLyricsPiPReadStyle().font isEqual:@"Courier"] && [SGLyricsPiPFontName(@"custom") isEqual:@"Courier"]);
    [store setObject:@"library:nanumgothic" forKey:SGKeyPiPFont];
    HARNESS_CHECK([SGLyricsPiPReadStyle().font isEqual:@"Helvetica"]);
    // The imported files are registered: asking again, as the Font page does at every visit, registers nothing.
    int registered = atomic_load(&sg_workerCalls);
    for (int ask = 0; ask < 3; ask++) SGRegisterCustomFontAsync();
    drainRegistrations(harnessImportQueue());
    HARNESS_CHECK(atomic_load(&sg_workerCalls) == registered && atomic_load(&sg_mainCalls) == 0);
    sg_holdRegistration = sg_holdImported = nil;
    [NSNotificationCenter.defaultCenter removeObserver:pipToken];
    __block BOOL rejected = NO;
    harnessRejectedImport([importedFolder URLByAppendingPathComponent:@"Harness.ttf"], ^(BOOL notified) {
        HARNESS_CHECK(notified); rejected = YES;
    });
    pumpUntil(^BOOL { return rejected; });

    // The Lyrics PiP font page (LyricsPiPSettings.m), opened while Core Text holds both registrations: its rows
    // for the two families are not there, and they come in without reopening once the registrations land.
    SGFontLibraryRemove(@"nanumgothic");
    install(@"nanumgothic");
    [store setObject:@"Menlo" forKey:SGKeyAppFontName];   // another family name, so the one cached above no longer counts
    HARNESS_CHECK(!SGRegisteredCustomFont() && !SGFontLibraryRegisteredFamily(@"nanumgothic"));
    atomic_store(&sg_mainCalls, 0);
    sg_holdRegistration = dispatch_semaphore_create(0);
    sg_holdImported = dispatch_semaphore_create(0);
    atomic_store(&sg_registrationEntries, 0);
    SGModPage *pip = (SGModPage *)SGLyricsPiPRow().page();
    SGModPage *fontPage = (SGModPage *)pip.sections[2].rows[1].page();   // opening it asks for the families
    [fontPage loadViewIfNeeded];
    fontPage.tableView.frame = CGRectMake(0, 0, 390, 2400);
    [fontPage viewWillAppear:NO];
    awaitRegistrations(2);
    queuedRan = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ queuedRan = YES; });
    pumpUntil(^BOOL { return queuedRan; });
    NSArray<NSString *> * (^fontRows)(void) = ^NSArray<NSString *> * {
        NSMutableArray<NSString *> *titles = [NSMutableArray array];
        for (NSInteger row = 0; row < [fontPage tableView:fontPage.tableView numberOfRowsInSection:0]; row++) {
            UITableViewCell *cell = [fontPage tableView:fontPage.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]];
            [titles addObject:((UIListContentConfiguration *)cell.contentConfiguration).text];
        }
        return titles;
    };
    HARNESS_CHECK([fontRows() containsObject:@"San Francisco"] && ![fontRows() containsObject:@"Nanum Gothic"] && ![fontRows() containsObject:@"Menlo"]);
    HARNESS_CHECK(atomic_load(&sg_mainCalls) == 0);
    for (int release = 0; release < 5; release++) dispatch_semaphore_signal(sg_holdRegistration);
    dispatch_semaphore_signal(sg_holdImported);
    pumpUntil(^BOOL { return [fontRows() containsObject:@"Nanum Gothic"] && [fontRows() containsObject:@"Menlo"]; });
    HARNESS_CHECK(atomic_load(&sg_mainCalls) == 0);
    [fontPage viewDidDisappear:NO];
    sg_holdRegistration = sg_holdImported = nil;
    __block NSUInteger removals = 0;
    id staleToken = [NSNotificationCenter.defaultCenter addObserverForName:SGFontLibraryChangedNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        if ([note.userInfo[@"identifier"] isEqual:@"custom"]) {
            HARNESS_CHECK(NSThread.isMainThread && !SGRegisteredCustomFont());
            removals++;
        }
    }];
    __block BOOL deleted = NO;
    harnessRemoveCustom(^{ deleted = YES; });
    pumpUntil(^BOOL { return deleted; });
    BOOL notifiedRemoval = removals == 1;
    NSURL *importURL = [importedFolder URLByAppendingPathComponent:@"Harness.ttf"];
    HARNESS_CHECK([NSFileManager.defaultManager createFileAtPath:importURL.path contents:nil attributes:nil]);
    [store setObject:@[@"Harness.ttf"] forKey:SGKeyAppFontFiles];
    [store setObject:@"Courier" forKey:SGKeyAppFontName];
    sg_holdImported = dispatch_semaphore_create(0);
    atomic_store(&sg_registrationEntries, 0);
    SGRegisterCustomFontAsync();
    awaitRegistrations(1);
    SGRegisterCustomFontAsync(); // must join the held registration, not enter Core Text twice
    deleted = NO;
    [store setInteger:SGAppFontCustom forKey:SGKeyAppFont];
    harnessRemoveCustom(^{ HARNESS_CHECK(NSThread.isMainThread); deleted = YES; });
    __block BOOL invalidFinished = NO;
    harnessImport(importURL, ^{ invalidFinished = YES; });
    dispatch_async(dispatch_get_main_queue(), ^{
        HARNESS_CHECK(!deleted && [NSFileManager.defaultManager fileExistsAtPath:importURL.path]);
        dispatch_semaphore_signal(sg_holdImported);
    });
    pumpUntil(^BOOL { return deleted && invalidFinished; });
    HARNESS_CHECK(notifiedRemoval && removals == 1 && !SGRegisteredCustomFont() && ![NSFileManager.defaultManager fileExistsAtPath:importURL.path]);
    HARNESS_CHECK([store objectForKey:SGKeyAppFont] == nil);
    [NSNotificationCenter.defaultCenter removeObserver:staleToken];
    sg_holdImported = nil;
    // The app font Fonts.x registered at launch resolves at once, with no notification to wait for.
    SGFontLibraryRemove(@"nanumgothic");
    install(@"lato");
    HARNESS_CHECK([SGFontLibraryRegister(@"lato") isEqual:@"Helvetica"]);   // the launch path
    [store setObject:@"app" forKey:SGKeyPiPFont];
    SGSetInt(SGKeyAppFont, SGAppFontLibrary);
    [store setObject:@"lato" forKey:SGKeyAppFontLibrary];
    HARNESS_CHECK([SGLyricsPiPReadStyle().font isEqual:@"Helvetica"]);
    [store removeObjectForKey:SGKeyPiPFont];
    [store removeObjectForKey:SGKeyAppFont];
    [store removeObjectForKey:SGKeyAppFontLibrary];
    [store removeObjectForKey:SGKeyAppFontFiles];
    [store removeObjectForKey:SGKeyAppFontName];
    [NSFileManager.defaultManager removeItemAtURL:importedFolder error:nil];
    SGFontLibraryRemove(@"lato");
    [NSFileManager.defaultManager removeItemAtURL:libraryFolder() error:nil];
    puts("PASS: free fonts register off main on a serial queue, publish and refresh rows on main, a removal beats a pending registration, the Font page, the Free fonts page and the Lyrics PiP font choices stay free while Core Text is busy and update when registration lands");
    CTFontRef face = CTFontCreateWithName(CFSTR("Chalkduster"), 16, NULL);
    NSURL *original = CFBridgingRelease(CTFontCopyAttribute(face, kCTFontURLAttribute));
    CFRelease(face);
    NSURL *picks = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSFileManager *fm = NSFileManager.defaultManager;
    HARNESS_CHECK([fm createDirectoryAtURL:picks withIntermediateDirectories:NO attributes:nil error:nil]);
    NSMutableArray *many = [NSMutableArray array];
    for (NSInteger i = 0; i < 33; i++) {
        NSURL *url = [picks URLByAppendingPathComponent:[NSString stringWithFormat:@"%ld.ttf", (long)i]];
        HARNESS_CHECK([fm copyItemAtURL:original toURL:url error:nil]);
        [many addObject:url];
    }
    NSURL *oversize = many.firstObject;
    NSURL *stale = [importedFolder URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
    HARNESS_CHECK([fm createDirectoryAtURL:stale withIntermediateDirectories:YES attributes:nil error:nil]);
    for (NSArray *batch in @[many, @[oversize], @[many[1], oversize]]) {
        if (batch.count <= 2) {
            NSFileHandle *handle = [NSFileHandle fileHandleForWritingToURL:oversize error:nil];
            HARNESS_CHECK([handle truncateAtOffset:64 * 1024 * 1024 + (batch.count == 1) error:nil] && [handle closeAndReturnError:nil]);
        }
        __block BOOL completed = NO;
        harnessImportFiles(batch, ^{ completed = YES; });
        pumpUntil(^BOOL { return completed; });
        HARNESS_CHECK(![store objectForKey:SGKeyAppFontFiles]);
    }
    HARNESS_CHECK(![fm fileExistsAtPath:stale.path]);
    NSURL *legacy = [importedFolder URLByAppendingPathComponent:@"Legacy.ttf"];
    HARNESS_CHECK([fm moveItemAtURL:oversize toURL:legacy error:nil]);
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingToURL:legacy error:nil];
    HARNESS_CHECK([handle truncateAtOffset:64 * 1024 * 1024 + 1 error:nil] && [handle closeAndReturnError:nil]);
    [store setObject:@[@"Legacy.ttf"] forKey:SGKeyAppFontFiles];
    [store setObject:@"Chalkduster" forKey:SGKeyAppFontName];
    HARNESS_CHECK([SGRegisterCustomFont() isEqual:@"Chalkduster"]);
    __block BOOL removedLegacy = NO;
    harnessRemoveCustom(^{ removedLegacy = YES; });
    pumpUntil(^BOOL { return removedLegacy; });
    HARNESS_CHECK(![fm fileExistsAtPath:legacy.path]);
    NSURL *cloudPick = [picks URLByAppendingPathComponent:@"Cloud.ttf"];
    NSURL *largePromise = [picks URLByAppendingPathComponent:@"large-promise"];
    HARNESS_CHECK([fm createFileAtPath:largePromise.path contents:nil attributes:nil]);
    NSFileHandle *promise = [NSFileHandle fileHandleForWritingToURL:largePromise error:nil];
    HARNESS_CHECK([promise truncateAtOffset:64 * 1024 * 1024 + 1 error:nil] && [promise closeAndReturnError:nil]);
    __block BOOL rejectedCloud = NO;
    harnessImportPlaceholder(cloudPick, largePromise, many[1], ^(BOOL requested) {
        HARNESS_CHECK(!requested && !harnessStoredFontNames().count);
        rejectedCloud = YES;
    });
    pumpUntil(^BOOL { return rejectedCloud; });
    __block BOOL importedCloud = NO;
    harnessImportPlaceholder(cloudPick, many[1], many[1], ^(BOOL requested) { importedCloud = requested; });
    pumpUntil(^BOOL { return importedCloud; });
    HARNESS_CHECK(([harnessStoredFontNames() isEqual:@[@"Cloud.ttf"]] && [SGRegisteredCustomFont() isEqual:@"Chalkduster"]));
    HARNESS_CHECK([fm removeItemAtURL:picks error:nil]);
    return 0;
} }

// A font family of the user's own for Fonts.x: the .ttf, .otf, .ttc or .otc files of one family picked together in
// Files are copied into Application Support, registered with Core Text for this process and named by the
// family name read from them. Like every other font choice it takes over when Spotify starts again, and
// Fonts.x registers the files again on each launch.
#import <CoreText/CoreText.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <fcntl.h>
#import <sys/stat.h>
#import <unistd.h>
#import "Core/SGCore.h"
#import "Core/SGDataRoot.h"
#import "Settings/SGModPage.h"
#import "Settings/SGSettingsIndex.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Fonts/FontLibrary.h"
#import "Shared/Fonts/Fonts.h"

extern BOOL SGImportSafeFilename(NSString *name);
extern int SGOpenImportFile(int parent, const char *path, NSUInteger limit);
extern NSData *SGReadImportFile(int fd, NSUInteger limit);
static const NSUInteger maxFontFiles = 32, maxFontBytes = 64 * 1024 * 1024;

static NSURL *fontFolder(void) {
    return [SGDataRoot(NSApplicationSupportDirectory) URLByAppendingPathComponent:@"Font" isDirectory:YES];
}

// Application Support is private; this worker is the only writer. Core Text's URL
// registration and unregistration must use the same (stable) installed URL.
static NSURL *storedFontURL(NSString *name) {
    if (!SGImportSafeFilename(name)) return nil;
    NSURL *url = [fontFolder() URLByAppendingPathComponent:name];
    int fd = SGOpenImportFile(AT_FDCWD, url.fileSystemRepresentation, NSUIntegerMax);
    if (fd < 0) return nil;
    close(fd);
    return url;
}

// The family name of every face in the file, "" for a face without one; empty when Core Text finds no font. A
// collection gives one per face.
static NSArray<NSString *> *familiesIn(NSURL *url) {
    NSArray *faces = CFBridgingRelease(CTFontManagerCreateFontDescriptorsFromURL((__bridge CFURLRef)url));
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (id face in faces) {
        NSString *name = CFBridgingRelease(CTFontDescriptorCopyAttribute((__bridge CTFontDescriptorRef)face, kCTFontFamilyNameAttribute));
        [names addObject:name ?: @""];
    }
    return names;
}

// The one family name all the faces share, or nil when they differ, one has none, or there are no faces.
NSString *SGFontSingleFamily(NSArray<NSString *> *names) {
    NSSet<NSString *> *distinct = [NSSet setWithArray:names];
    return distinct.count == 1 && distinct.anyObject.length ? distinct.anyObject : nil;
}

// An import from before families is one file under SGKeyAppFontFile and a PostScript name under
// SGKeyAppFontName. It becomes a list of one file and its family name, on first use after the update.
static void migrate(void) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    NSString *file = [store objectForKey:SGKeyAppFontFile];
    NSURL *url = storedFontURL(file);
    if (!url) return;
    NSString *family = familiesIn(url).firstObject;
    if (family.length) {
        [store setObject:@[file] forKey:SGKeyAppFontFiles];
        [store setObject:family forKey:SGKeyAppFontName];
        [store removeObjectForKey:SGKeyAppFontFile];
    }
}

// The imported files still in the folder.
static NSArray<NSURL *> *storedFiles(void) {
    migrate();
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    for (NSString *file in [NSUserDefaults.standardUserDefaults arrayForKey:SGKeyAppFontFiles]) {
        NSURL *url = storedFontURL(file);
        if (url) [urls addObject:url];
    }
    return urls;
}

static NSString *importedFamily(void) {
    return storedFiles().count ? [NSUserDefaults.standardUserDefaults stringForKey:SGKeyAppFontName] : nil;
}

// A replacement can reuse every filename and the family name. Identify the files themselves.
static NSDictionary *importIdentity(void) {
    NSMutableDictionary *files = [NSMutableDictionary dictionary];
    for (NSURL *url in storedFiles()) {
        id identifier;
        if (![url getResourceValue:&identifier forKey:NSURLFileResourceIdentifierKey error:nil] || !identifier) return nil;
        files[url] = identifier;
    }
    NSString *family = [NSUserDefaults.standardUserDefaults stringForKey:SGKeyAppFontName];
    return files.count && family.length ? @{@"family":family, @"files":files} : nil;
}

// A face iOS already carries under the same name (Chalkduster, say) is refused as a duplicate and is there
// all the same, so what counts is whether the family has faces afterward. Files that are gone are skipped.
static NSString *registerCustom(void) {
    NSString *family = importedFamily();
    for (NSURL *url in storedFiles()) {
        CFErrorRef error = NULL;
        if (!CTFontManagerRegisterFontsForURL((__bridge CFURLRef)url, kCTFontManagerScopeProcess, &error)) {
            NSError *failure = CFBridgingRelease(error);
            SGLog(@"fonts: %@ not registered: %@", url.lastPathComponent, failure.localizedDescription);
        }
    }
    return family && [UIFont fontNamesForFamilyName:family].count ? family : nil;
}

// What registerCustom answered, published on the main thread by SGRegisterCustomFont or SGRegisterCustomFontAsync.
static NSString *sg_registeredCustom;
static NSDictionary *sg_displayIdentity; // main-thread mirror
static NSUInteger sg_importGeneration; // main thread, like the published family
static BOOL sg_registrationPending;

static dispatch_queue_t registrationQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("spotifyglass.fontImport.registration", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

// Only the serial worker inspects the files. A superseded completion can compare with the
// last finished operation without waiting on a copy or Core Text registration.
static NSDictionary *sg_workerIdentity;
static NSDictionary *snapshotImport(void) {
    NSDictionary *identity = importIdentity();
    @synchronized (registrationQueue()) { sg_workerIdentity = identity; }
    return identity;
}
static BOOL sameIdentity(NSDictionary *a, NSDictionary *b) { return a == b || [a isEqual:b]; }
static BOOL currentIdentity(NSDictionary *identity) {
    @synchronized (registrationQueue()) { return sameIdentity(identity, sg_workerIdentity); }
}

static void publishCustom(NSString *family, NSDictionary *identity);

NSString *SGRegisterCustomFont(void) {
    NSUInteger generation = ++sg_importGeneration;
    sg_registrationPending = NO;
    __block NSString *family;
    dispatch_sync(registrationQueue(), ^{ family = registerCustom(); });
    sg_registeredCustom = family;
    dispatch_async(registrationQueue(), ^{
        NSDictionary *identity = snapshotImport();
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation == sg_importGeneration) publishCustom(family, identity);
        });
    });
    return family;
}

NSString *SGRegisteredCustomFont(void) {
    return [sg_registeredCustom isEqualToString:[NSUserDefaults.standardUserDefaults stringForKey:SGKeyAppFontName]] ? sg_registeredCustom : nil;
}

static void publishCustom(NSString *family, NSDictionary *identity) {
    BOOL sameFamily = sg_registeredCustom == family || [sg_registeredCustom isEqualToString:family];
    if (sameFamily && sameIdentity(identity, sg_displayIdentity)) return;
    sg_displayIdentity = identity;
    sg_registeredCustom = family;
    [NSNotificationCenter.defaultCenter postNotificationName:SGFontLibraryChangedNotification object:nil userInfo:@{@"identifier": sameFamily ? @"custom-files" : @"custom"}];
}

// registerCustom on a queue of its own, one registration at a time; the answer is published on main.
void SGRegisterCustomFontAsync(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ SGRegisterCustomFontAsync(); });
        return;
    }
    if (sg_registrationPending || SGRegisteredCustomFont()) return;
    sg_registrationPending = YES;
    NSUInteger generation = sg_importGeneration;
    dispatch_async(registrationQueue(), ^{
        NSDictionary *identity = snapshotImport();
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != sg_importGeneration || sameIdentity(identity, sg_displayIdentity)) return;
            publishCustom(sg_registeredCustom, identity);
        });
        NSString *family = registerCustom();
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != sg_importGeneration) return;
            sg_registrationPending = NO;
            publishCustom(family, identity);
        });
    });
}

// On the registration queue, after any previous use of the files by Core Text.
static void removeImportedFiles(NSArray<NSURL *> *urls) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    for (NSURL *url in urls) {
        CTFontManagerUnregisterFontsForURL((__bridge CFURLRef)url, kCTFontManagerScopeProcess, NULL);
        unlink(url.fileSystemRepresentation);
    }
    for (NSString *key in @[SGKeyAppFontFiles, SGKeyAppFontName]) [store removeObjectForKey:key];
}

static void resetCustomSelection(void) {
    if (SGAppFontChosen() == SGAppFontCustom) {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyAppFont];
        SGPrefsChanged();
    }
}

static void removeImported(NSDictionary *target, dispatch_block_t done) {
    NSUInteger generation = ++sg_importGeneration;
    sg_registrationPending = YES;
    dispatch_async(registrationQueue(), ^{
        BOOL removed = [target isEqual:importIdentity()];
        if (removed) removeImportedFiles([target[@"files"] allKeys]);
        NSDictionary *remaining = snapshotImport();
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation == sg_importGeneration) sg_registrationPending = NO;
            // A later request may have failed validation without installing anything.
            if (removed && !remaining && currentIdentity(nil)) {
                resetCustomSelection();
                publishCustom(nil, nil);
            }
            done();
        });
    });
}

static void tell(NSString *title, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.later", @"Later") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"settings.font.action.restart_now", @"Restart now") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { SGRestartSpotify(); }]];
    SGPresentDark(alert);
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

// The files are checked and copied aside before the ones in use are touched, so files Core Text will not read,
// of more than one family, or that fail to copy change nothing.
static BOOL sg_importing;
// Only this serial worker creates directories among the installed files. A UUID
// directory is a previous staging area whose worker didn't reach its cleanup.
static void reclaimStaging(NSURL *folder) {
    NSFileManager *files = NSFileManager.defaultManager;
    for (NSURL *entry in [files contentsOfDirectoryAtURL:folder includingPropertiesForKeys:nil options:0 error:nil]) {
        if (![[[NSUUID alloc] initWithUUIDString:entry.lastPathComponent].UUIDString isEqual:entry.lastPathComponent]) continue;
        struct stat st;
        if (lstat(entry.fileSystemRepresentation, &st) == 0 && S_ISDIR(st.st_mode)) [files removeItemAtURL:entry error:nil];
    }
}

// Inspect the whole selection before staging even the first file. Keep each grant
// through its read; the descriptor and byte-budget checks below also cover growth.
static BOOL preflight(NSArray<NSURL *> *picked, NSMutableArray<NSURL *> *scoped) {
    if (!picked.count || picked.count > maxFontFiles) return NO;
    NSUInteger remaining = maxFontBytes;
    for (NSURL *url in picked) {
        if (!url.isFileURL || !SGImportSafeFilename(url.lastPathComponent)) return NO;
        if ([url startAccessingSecurityScopedResource]) [scoped addObject:url];
        struct stat st;
        // A provider may have no local file until its coordinated accessor runs.
        // Veto a known link, but do not require an already-materialized inode here.
        if (lstat(url.fileSystemRepresentation, &st) == 0 && S_ISLNK(st.st_mode)) return NO;
        __block NSNumber *size = nil;
        [[NSFileCoordinator new] coordinateReadingItemAtURL:url options:NSFileCoordinatorReadingImmediatelyAvailableMetadataOnly error:nil
            byAccessor:^(NSURL *reading) {
                NSDictionary *metadata = [reading promisedItemResourceValuesForKeys:@[NSURLFileResourceTypeKey, NSURLFileSizeKey] error:nil];
                if ([metadata[NSURLFileResourceTypeKey] isEqual:NSURLFileResourceTypeRegular]) size = metadata[NSURLFileSizeKey];
            }];
        if (![size isKindOfClass:NSNumber.class] || !size.unsignedLongLongValue || size.unsignedLongLongValue > remaining) return NO;
        remaining -= size.unsignedIntegerValue;
    }
    return YES;
}

static void import(NSArray<NSURL *> *picked, dispatch_block_t done) {
    NSArray *selection = SGFontSelectionSnapshot();
    NSUInteger generation = ++sg_importGeneration;
    sg_registrationPending = YES;
    dispatch_async(registrationQueue(), ^{
    NSMutableArray<NSString *> *families = [NSMutableArray array];
    NSFileManager *files = NSFileManager.defaultManager;
    NSURL *folder = fontFolder();
    if (folder) reclaimStaging(folder);
    NSURL *incoming = [folder URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
    NSMutableArray<NSString *> *copied = [NSMutableArray array];
    NSMutableArray<NSURL *> *scoped = [NSMutableArray array];
    BOOL staged = incoming && preflight(picked, scoped) &&
        [files createDirectoryAtURL:incoming withIntermediateDirectories:YES attributes:nil error:nil];
    BOOL fonts = staged;
    NSUInteger remaining = maxFontBytes;
    for (NSURL *url in picked) @autoreleasepool {
        if (!fonts) break;
        NSString *name = url.lastPathComponent;
        __block NSData *data = nil;
        [[NSFileCoordinator new] coordinateReadingItemAtURL:url options:NSFileCoordinatorReadingWithoutChanges error:nil
            byAccessor:^(NSURL *reading) {
                data = SGReadImportFile(SGOpenImportFile(AT_FDCWD, reading.fileSystemRepresentation, remaining), remaining);
            }];
        NSURL *copy = [incoming URLByAppendingPathComponent:name];
        if (!data.length || ![data writeToURL:copy options:NSDataWritingWithoutOverwriting error:nil]) { fonts = NO; break; }
        remaining -= data.length;
        NSArray *names = familiesIn(copy);
        if (!names.count) { fonts = NO; break; }
        [families addObjectsFromArray:names];
        [copied addObject:name];
    }
    for (NSURL *url in scoped) [url stopAccessingSecurityScopedResource];
    NSString *family = fonts ? SGFontSingleFamily(families) : nil;
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    BOOL replacing = family && copied.count == picked.count;
    NSString *registered = nil;
    if (replacing) {
        removeImportedFiles(storedFiles()); // replacing the files is not a user font selection
        for (NSString *file in copied) {
            NSURL *target = [fontFolder() URLByAppendingPathComponent:file];
            unlink(target.fileSystemRepresentation);
            if (![files moveItemAtURL:[incoming URLByAppendingPathComponent:file] toURL:target error:nil]) {
                family = nil;
                break;
            }
        }
        [store setObject:copied forKey:SGKeyAppFontFiles];
        if (family) {
            [store setObject:family forKey:SGKeyAppFontName];
            registered = registerCustom();
        }
        if (!registered) removeImportedFiles(storedFiles());
    }
    if (staged) [files removeItemAtURL:incoming error:nil];
    NSDictionary *identity = snapshotImport();
    NSDictionary *installed = registered ? identity : nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (generation == sg_importGeneration) sg_registrationPending = NO;
        BOOL current = generation == sg_importGeneration || currentIdentity(installed);
        if (current && replacing) publishCustom(registered, installed);
        // Keep the imported family available even during a pending restart, but never change its
        // selection: a reset/restore may have left the same (including unset) preference values.
        if (registered) {
            if (current && SGFontSelectionUnchanged(selection)) {
                SGSetInt(SGKeyAppFont, SGAppFontCustom);
                tell(SGL(@"settings.font.imported.alert.title", @"Font imported"), [NSString stringWithFormat:SGL(@"settings.font.imported.alert.message", @"%@ becomes the app's font when Spotify starts again."), family]);
            }
            done();
            return;
        }
        if (current) {
            if (replacing) resetCustomSelection();
            else SGRegisterCustomFontAsync(); // validation left the old files in place
        }
        SGPresentInformation(SGTopController(), SGL(@"settings.font.failed.alert.title", @"Font not imported"), fonts && !family ? SGL(@"settings.font.failed.multiple_families.alert.message", @"These files are more than one family. Pick the files of one family together.")
                                               : SGL(@"settings.font.failed.invalid_files.alert.message", @"Choose valid .ttf, .otf, .ttc or .otc font files."));
        done();
    });
    });
}

@interface SGFontPicker : NSObject <UIDocumentPickerDelegate>
@property (nonatomic, copy) void (^done)(void);   // the page's refresh, once the files are in or refused
@end

@implementation SGFontPicker

- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (sg_importing) return;
    dispatch_block_t done = [self.done copy];
    if (!urls.count) { if (done) done(); return; }
    sg_importing = YES;
    import(urls, ^{
        sg_importing = NO;
        if (done) done();
    });
}

@end

static void pickFont(void (^done)(void)) {
    if (sg_importing) return; // the staging directory belongs to the in-flight import
    static SGFontPicker *delegate;
    if (!delegate) delegate = [SGFontPicker new];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeFont] asCopy:NO];
    delegate.done = done;
    picker.delegate = delegate;
    picker.allowsMultipleSelection = YES;
    SGPresentDark(picker);
    [SGTopController() presentViewController:picker animated:YES completion:nil];
}

#pragma mark - the page

// Each choice is drawn in its own font. Core Text makes it, so the font chosen now (Fonts.x hooks UIFont) does
// not dress every row in itself.
static UIFont *previewFont(NSString *nameOrFamily, BOOL family, CGFloat size) {
    CTFontRef font = NULL;
    if (!nameOrFamily) {
        return nil;
    } else if (family) {
        CTFontDescriptorRef descriptor = CTFontDescriptorCreateWithAttributes((__bridge CFDictionaryRef)@{(id)kCTFontFamilyNameAttribute: nameOrFamily});
        font = CTFontCreateWithFontDescriptor(descriptor, size, NULL);
        CFRelease(descriptor);
    } else {
        font = CTFontCreateWithName((__bridge CFStringRef)nameOrFamily, size, NULL);
    }
    return font ? (__bridge_transfer UIFont *)font : nil;
}

static UIFont *builtInFont(SGAppFont choice, CGFloat size) {
    if (choice == SGAppFontSpotify) return previewFont(@"SpotifyMixUI-Regular", NO, size);
    UIFontDescriptor *system = ((__bridge_transfer UIFont *)CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, size, NULL)).fontDescriptor;
    UIFontDescriptorSystemDesign design = choice == SGAppFontRounded ? UIFontDescriptorSystemDesignRounded
        : choice == SGAppFontSerif ? UIFontDescriptorSystemDesignSerif
        : choice == SGAppFontMono ? UIFontDescriptorSystemDesignMonospaced : UIFontDescriptorSystemDesignDefault;
    UIFontDescriptor *descriptor = [system fontDescriptorWithDesign:design] ?: system;
    return (__bridge_transfer UIFont *)CTFontCreateWithFontDescriptor((__bridge CTFontDescriptorRef)descriptor, size, NULL);
}

static NSString *chosenLabel(void) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    SGAppFont font = SGAppFontChosen();
    if (font == SGAppFontCustom) return sg_displayIdentity[@"family"] ?: SGL(@"settings.font.choice.custom", @"Your font");
    if (font == SGAppFontFamily) return [store stringForKey:SGKeyAppFontFamily] ?: SGAppFontNames()[0];
    if (font == SGAppFontLibrary) return SGFontLibraryFont([store stringForKey:SGKeyAppFontLibrary]).name ?: SGAppFontNames()[0];
    return SGAppFontNames()[font];
}

typedef NS_ENUM(NSInteger, SGFontSection) { SGFontBuiltIn, SGFontMore, SGFontFree, SGFontYours };

@interface SGFontPage : SGPage <SGSettingsSearchPages>
@end

@implementation SGFontPage {
    NSArray<NSString *> *_families;
    NSArray<SGLibraryFont *> *_free;   // the free families on this iPhone
    NSDictionary *_displayedImport;
    UIView *_footer;
    id _observer;
    BOOL _visible;             // between viewWillAppear: and viewDidDisappear:
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = SGL(@"settings.font.title", @"Font");
    _families = SGAppFontFamilies();
    _displayedImport = sg_displayIdentity;
    return self;
}

// A one-face import says why bold comes out regular; otherwise the note says how to bring the bold along.
- (void)refreshFooter {
    NSString *own = self.styleCount == 1
        ? SGL(@"settings.font.footer.single_style", @"A font of your own is a .ttf or .otf file from Files. This one has a single style, so bold text comes out regular. Pick all the files of a family together to keep bold. ")
        : SGL(@"settings.font.footer.family_style", @"A font of your own comes from Files: a .ttf or .otf file, or all the files of one family picked together, so bold and italic stay. ");
    _footer = SGNote([own stringByAppendingString:SGL(@"settings.font.footer.restart_note", @"Text Spotify draws itself may keep its own font. Changes apply after you restart Spotify.")]);
    self.tableView.tableFooterView = _footer;
}

- (void)dealloc {
    if (_observer) [NSNotificationCenter.defaultCenter removeObserver:_observer];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self refreshFooter];
    __weak SGFontPage *page = self;
    // Posted on the main thread only (FontLibrary.m): a family registered off main is now drawable, or a
    // family was added or removed.
    _observer = [NSNotificationCenter.defaultCenter addObserverForName:SGFontLibraryChangedNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        SGFontPage *strong = page;
        if (!strong || !strong->_visible) return;   // viewWillAppear: refreshes it when it comes back
        [strong refreshFooter];   // the imported family's style count
        [strong reloadFree];
    }];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    SGFitNote(self.tableView, _footer, 8, 24);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _visible = YES;
    [self refresh];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    _visible = NO;
}

// Installed families, free and imported, are registered off main and drawn in themselves once the library
// announces each one or the imported files land; until then a row keeps the list's font. Nothing here or in
// the cells registers a font synchronously.
- (void)refresh {
    SGFontLibraryRegisterInstalled();
    SGRegisterCustomFontAsync();
    [self refreshFooter];
    [self reloadFree];
}

- (void)reloadFree {
    _displayedImport = sg_displayIdentity;
    _free = [SGFontLibrary() filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(SGLibraryFont *font, NSDictionary *bindings) {
        return SGFontLibraryInstalled(font.identifier);
    }]];
    [self.tableView reloadData];
}

// The imported family once its files are registered; nil before that and when they are gone.
- (NSString *)customFamily {
    return [sg_registeredCustom isEqualToString:_displayedImport[@"family"]] ? sg_registeredCustom : nil;
}

// How many faces the imported family has on this iPhone.
- (NSUInteger)styleCount {
    NSString *name = self.customFamily;
    return name ? [UIFont fontNamesForFamilyName:name].count : 0;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    return 4;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    if (section == SGFontBuiltIn) return (NSInteger)SGAppFontNames().count;
    if (section == SGFontMore) return (NSInteger)_families.count;
    if (section == SGFontFree) return (NSInteger)_free.count + 1;
    return _displayedImport ? 2 : 1;
}

- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    if (section == SGFontBuiltIn) return nil;
    if (section == SGFontFree) return SGSectionHeader(table, SGL(@"settings.font.free.header", @"Free fonts"));
    return SGSectionHeader(table, section == SGFontMore ? SGL(@"settings.font.more.header", @"More fonts") : SGL(@"settings.font.yours.header", @"Your fonts"));
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    return section == SGFontBuiltIn ? SGSectionGap : SGSectionHeaderHeight();
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = SGDequeueCell(table, @"font");
    CGFloat size = SGTitleFont().pointSize;
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    SGAppFont chosen = SGAppFontChosen();
    NSString *title, *subtitle = nil;
    UIFont *font;
    BOOL selected;
    if (path.section == SGFontBuiltIn) {
        title = SGAppFontNames()[(NSUInteger)path.row];
        font = builtInFont(path.row, size);
        selected = chosen == path.row;
    } else if (path.section == SGFontMore) {
        title = _families[(NSUInteger)path.row];
        font = previewFont(title, YES, size);
        selected = chosen == SGAppFontFamily && [title isEqualToString:[store stringForKey:SGKeyAppFontFamily]];
    } else if (path.section == SGFontFree && path.row < (NSInteger)_free.count) {
        SGLibraryFont *free = _free[(NSUInteger)path.row];
        title = free.name;
        font = previewFont(SGFontLibraryRegisteredFamily(free.identifier), YES, size);
        selected = chosen == SGAppFontLibrary && [free.identifier isEqualToString:[store stringForKey:SGKeyAppFontLibrary]];
    } else if (path.section == SGFontFree) {
        SGFillCell(cell, _free.count ? SGL(@"settings.font.free.more.title", @"More free fonts") : SGL(@"settings.font.free.get.title", @"Get free fonts"),
                   SGL(@"settings.font.free.get.subtitle", @"Korean and Latin families under the Open Font License"), nil, nil);
        cell.accessoryView = SGChevronView();
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        cell.accessibilityTraits = UIAccessibilityTraitButton;
        return cell;
    } else if (path.row == 0 && _displayedImport) {
        title = _displayedImport[@"family"];
        font = previewFont(self.customFamily, YES, size);
        selected = chosen == SGAppFontCustom;
        if (self.styleCount) subtitle = [NSString stringWithFormat:SGL(@"settings.font.style_count.format", @"%lu style%@"), (unsigned long)self.styleCount, self.styleCount == 1 ? @"" : @"s"];
    } else {
        SGFillCell(cell, SGL(@"settings.font.add_file.title", @"Add a font file"), nil, SGGreen(), nil);
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        cell.accessibilityTraits = UIAccessibilityTraitButton;
        return cell;
    }
    SGFillCell(cell, title, subtitle, nil, nil);
    UIListContentConfiguration *content = (UIListContentConfiguration *)cell.contentConfiguration;
    if (font) content.textProperties.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody] scaledFontForFont:font maximumPointSize:18];
    cell.contentConfiguration = content;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    if (selected) {
        UIImageView *tick = SGSymbolView(@"checkmark", 13, UIImageSymbolWeightSemibold, 16);
        tick.tintColor = SGGreen();
        cell.accessoryView = tick;
    }
    cell.accessibilityTraits = selected ? UIAccessibilityTraitButton | UIAccessibilityTraitSelected : UIAccessibilityTraitButton;
    return cell;
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (path.section == SGFontBuiltIn) {
        SGSetInt(SGKeyAppFont, path.row);
    } else if (path.section == SGFontMore) {
        [NSUserDefaults.standardUserDefaults setObject:_families[(NSUInteger)path.row] forKey:SGKeyAppFontFamily];
        SGSetInt(SGKeyAppFont, SGAppFontFamily);
    } else if (path.section == SGFontFree && path.row < (NSInteger)_free.count) {
        [NSUserDefaults.standardUserDefaults setObject:_free[(NSUInteger)path.row].identifier forKey:SGKeyAppFontLibrary];
        SGSetInt(SGKeyAppFont, SGAppFontLibrary);
    } else if (path.section == SGFontFree) {
        SGShowPage(self, self.sg_searchPageRows.firstObject.page());
        return;
    } else if (path.row == 0 && _displayedImport) {
        SGSetInt(SGKeyAppFont, SGAppFontCustom);
    } else {
        __weak SGFontPage *page = self;
        pickFont(^{ [page refresh]; });
        return;
    }
    [table reloadData];
}

// Swiping the imported family away deletes its files; Default comes back if it was the choice.
- (UISwipeActionsConfiguration *)tableView:(UITableView *)table trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)path {
    NSDictionary *target = _displayedImport;
    if (path.section != SGFontYours || path.row != 0 || !target) return nil;
    UIContextualAction *delete = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:SGL(@"common.delete", @"Delete")
        handler:^(UIContextualAction *action, UIView *view, void (^done)(BOOL)) {
            removeImported(target, ^{
                [self refresh];
                done(YES);
            });
        }];
    delete.image = [UIImage systemImageNamed:@"trash"];
    return [UISwipeActionsConfiguration configurationWithActions:@[delete]];
}

- (NSArray<SGModRow *> *)sg_searchPageRows {
    return @[SGSearchIdentified(SGPageRow(SGL(@"settings.font.free.header", @"Free fonts"),
        ^UIViewController *{ return SGFontLibraryPage(); }), @"page.freefonts")];
}
@end

NSArray<SGModRow *> *SGAppFontRows(void) {
    SGModRow *font = SGPageRow(SGL(@"settings.font.row.title", @"Font"), ^UIViewController *{ return [SGFontPage new]; });
    font.value = ^NSString *{ return chosenLabel(); };
    return @[SGSearchIdentified(font, @"page.font")];
}

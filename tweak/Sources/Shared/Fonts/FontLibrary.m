// FontLibrary.h says what this is. The catalog below was read from github.com/google/fonts at the commit kCommit
// names: every file's size and SHA-256, and each family's OFL.txt. A file that differs from its line is refused.
#import "Core/SGFileHash.h"
#import "Core/SGDataRoot.h"
#import <CoreText/CoreText.h>
#import <UIKit/UIKit.h>
#import "Core/SGCore.h"
#import "Shared/Fonts/FontLibrary.h"
#import "Shared/Fonts/Fonts.h"

static NSString *const kCommit = @"67bc647ce1910e92f461bcc82aae30f21d21a9cc";
#define kLicense @"OFL.txt"

typedef struct {
    NSString *__unsafe_unretained name;
    long long size;
    NSString *__unsafe_unretained sha256;
} SGFontFileLine;

typedef struct {
    NSString *__unsafe_unretained identifier, *__unsafe_unretained name;
    BOOL korean;
    SGFontFileLine license;
    SGFontFileLine files[5];   // a name of nil ends the list
} SGFontFamilyLine;

static const SGFontFamilyLine kFamilies[] = {
    {@"nanumgothic", @"Nanum Gothic", YES, {kLicense, 4534, @"eeacf16032901d0ed0456876ec77b8f0fda6b3fecec7d972f8543eb602e6c30f"}, {
        {@"NanumGothic-Regular.ttf", 2054744, @"76f45ef4a6bcff344c837c95a7dcc26e017e38b5846d5ae0cdcb5b86be2e2d31"},
        {@"NanumGothic-Bold.ttf", 2073868, @"f96298f9fb18e364d2370f4c3ce948ac67a2b61af992d7234bc15c42b033c674"},
    }},
    {@"nanummyeongjo", @"Nanum Myeongjo", YES, {kLicense, 4497, @"8eb1c1019fe7fe6d0b6e7d7bbbba1d9cbdd969d8c5f26455708f6cfb8a77284c"}, {
        {@"NanumMyeongjo-Regular.ttf", 3058408, @"7ed9e8653a8ed04285d51dc343ffea6eb3d9c73afc27383ea8929ee4ffd03205"},
        {@"NanumMyeongjo-Bold.ttf", 3074720, @"bc9ed8e60d93fe6db054b8fb988481b625f2eef8cb2317ad0e9834681b8fe3f3"},
    }},
    {@"ibmplexsanskr", @"IBM Plex Sans KR", YES, {kLicense, 4456, @"7e6b2818edbd8f6a01ae80641cc8f16a51080d08fb4e532be3a0b6f74adb07da"}, {
        {@"IBMPlexSansKR-Regular.ttf", 2797100, @"53750379270312368cf7641901f43a98dd892e3d9d5798cf25cdc245c85c71c0"},
        {@"IBMPlexSansKR-Medium.ttf", 2866736, @"4a7130f56ce50bf10f9d383f624e50bad2c80bebc63e51f4269ece2c7d919166"},
        {@"IBMPlexSansKR-Bold.ttf", 2875584, @"9d82a8be5330f6d7b53121262867b402baca672eb69b852928f06d185d357f7d"},
    }},
    {@"gothica1", @"Gothic A1", YES, {kLicense, 4359, @"ed95c33f80ccca002e3a360b683c43368f9c5eb024e5b992abb51af3c10b59bc"}, {
        {@"GothicA1-Regular.ttf", 2295400, @"211151bea98098c579610ab1114bb1bfe909057207db561f357b896d076c21ac"},
        {@"GothicA1-Medium.ttf", 2288824, @"c8a0eb56fa6b13448688fed0799d503fe536a8c6b7acfafdfd580edb9c4c2192"},
        {@"GothicA1-Bold.ttf", 2287068, @"2e883fa0ae548000996258b4101f2bb732a28b197264f49621a2cb16d6e9f126"},
    }},
    {@"sunflower", @"Sunflower", YES, {kLicense, 4348, @"a9b40759b5821a0c2ad07cbd2c2a61dca4b3e222e6370a7d5bfb6b373bf4fb10"}, {
        {@"Sunflower-Light.ttf", 758332, @"dd9fb97aa9ec1fdb65e0328513d9c54c114fba41decca1d32a1e1ed992e255c5"},
        {@"Sunflower-Medium.ttf", 770536, @"6e216d6b2f77a850f6b73be25633d09e03385dfa63a3a632f9e7d83a90ea7f79"},
        {@"Sunflower-Bold.ttf", 746300, @"6b033627817f6619433afe82028013dc45a78ff82406b1dbe5b16e1bbc370e0a"},
    }},
    {@"gowundodum", @"Gowun Dodum", YES, {kLicense, 4395, @"a7c73f9521cd646bbdfb6684c99a62311bbd7bce11898dc11ef0b3c69eda1aca"}, {
        {@"GowunDodum-Regular.ttf", 7229088, @"a6e457933227483a11758fd0947bc74422a106d46f0bf057fdaa5af94a30067d"},
    }},
    {@"dohyeon", @"Do Hyeon", YES, {kLicense, 4347, @"de5ff32211a4340b01477af39ee339d639438955e409f79b666d4b9207f3c92c"}, {
        {@"DoHyeon-Regular.ttf", 879764, @"35644be7f28e0a68a447b1f7af351dcde5674b870f24f7b5f43e26d00b4ab653"},
    }},
    {@"jua", @"Jua", YES, {kLicense, 4342, @"44a7c6e4c5572392ae122d3b1d8c6ba6fd640a7797e675384585d947f2773e3c"}, {
        {@"Jua-Regular.ttf", 2119352, @"769677aef240bfc3b9965f2b50748075bff885e6c6992fc591a3fb268279f898"},
    }},
    {@"nanumpenscript", @"Nanum Pen Script", YES, {kLicense, 4534, @"eeacf16032901d0ed0456876ec77b8f0fda6b3fecec7d972f8543eb602e6c30f"}, {
        {@"NanumPenScript-Regular.ttf", 3201664, @"6f0d1ab29c7894010dc88831fb7a0a51edb79136e450344183de5b1a8b52bd43"},
    }},
    {@"poppins", @"Poppins", NO, {kLicense, 4385, @"6be04893d770899a015649c7aa3b582f871b272f8747a92b78b17c3e5c8b2573"}, {
        {@"Poppins-Regular.ttf", 160316, @"7e65201e9b79159e2300267cc885e16c8dcef2424cdfa09a29bfb0980a94a7ba"},
        {@"Poppins-Medium.ttf", 158576, @"90373e7d838d32468438fc3e152dca0bdb12edcab99ea639f158790b1ba1fd05"},
        {@"Poppins-SemiBold.ttf", 157312, @"d3bf1bdaf0550e83da9ac0b1d1d9fe6db086835a83aa28578e609a394b9a0286"},
        {@"Poppins-Bold.ttf", 155996, @"983676516167748b74de6f4771fb384c664fd913acb8b471122ecacf5da5ea6c"},
    }},
    {@"lato", @"Lato", NO, {kLicense, 4407, @"74ba064d03f1f1c4a952da936c3eb71866c34404916734de3cae73b34357e59e"}, {
        {@"Lato-Regular.ttf", 656568, @"d636e4683231f931eda222d588e944d082bfd3bdba02f928bee461c0f185b251"},
        {@"Lato-Bold.ttf", 656544, @"8a0aace75d33794eece4b28187bfc1df0bbd2888b5d8a56e01788c8d65d16be1"},
        {@"Lato-Black.ttf", 664748, @"808c62839c62dbce7de689af7603666fc7f8b81e0df537d8a5212c87580d4337"},
    }},
    {@"firasans", @"Fira Sans", NO, {kLicense, 4370, @"8f24842e9174beda18a556c2ae7d54f5dc444340c19a3a9ef77e23bca366adbd"}, {
        {@"FiraSans-Regular.ttf", 456996, @"c29556a2719bf613ef3d5e070e40d903a8965d9c081beca1375dc1e6e0f93c23"},
        {@"FiraSans-Medium.ttf", 457248, @"cbc1842cbed8c1d1146ba7c9db97d8f28c9bedfd25f41c5b0e1259ca48622328"},
        {@"FiraSans-SemiBold.ttf", 489028, @"db0321f83eb3e9f527b8af384a1b3fefdc1039cf2b06fd39b3f61492bda9561c"},
        {@"FiraSans-Bold.ttf", 489720, @"a4d8e149ecdd4874a0726eb0af894488b3b31c423d6b0017c8f415ed1b795b45"},
    }},
    {@"barlow", @"Barlow", NO, {kLicense, 4377, @"186d750eb496a4c17a76385f82be6aea2ac1cf2de074a811d63786cf374ea73f"}, {
        {@"Barlow-Regular.ttf", 104068, @"95aa02c7c43096e0dd44d787ba6216864a67157e402adab59b35572e0c1577ea"},
        {@"Barlow-Medium.ttf", 103536, @"f8906f762cb73dca441da034bc363b2d8e2e68bc10d5c05e58717646c20cc4b4"},
        {@"Barlow-SemiBold.ttf", 108348, @"86577cb32f8abe3673db53ca0f4221e6856751a4f6730c867e00f720f8bb1fc5"},
        {@"Barlow-Bold.ttf", 108220, @"84e6a4d61e7c3e21f3c50ea6a4f7e5303a3467864c038be6ea3759bab8d547f9"},
    }},
    {@"atkinsonhyperlegible", @"Atkinson Hyperlegible", NO, {kLicense, 4352, @"f32d22b3908fcad2c86a74000614ec22e6a7f66ea7e867e616026a27aebdc143"}, {
        {@"AtkinsonHyperlegible-Regular.ttf", 54348, @"7fb917c89019896d0b52ee84b7cbb3304c18cb90b19a62f5e32712bd23e97669"},
        {@"AtkinsonHyperlegible-Bold.ttf", 55256, @"5a3b0c8cc8ca545155150b4512a1fa248298df121c50d6557e651e61fbdab92f"},
    }},
    {@"ibmplexmono", @"IBM Plex Mono", NO, {kLicense, 4456, @"7e6b2818edbd8f6a01ae80641cc8f16a51080d08fb4e532be3a0b6f74adb07da"}, {
        {@"IBMPlexMono-Regular.ttf", 135580, @"6a3412f058c7d8dfd9170c41e85ade48e5156ecb89356110ca57a0a27734af46"},
        {@"IBMPlexMono-Medium.ttf", 136704, @"a9b4c49bb299e05b5f6c481e7fb5e78943d2793249a0c8874ab574a2d1ea6755"},
        {@"IBMPlexMono-Bold.ttf", 137784, @"ac27abd6450a64dd94467580a02fe6235156d5b92f2926ebbc8e7489df64e0be"},
    }},
    {@"spacemono", @"Space Mono", NO, {kLicense, 4392, @"8e4ee42b2553e1e01504e61cb0d46d148cd8c9e5eacaa3622a7df2d4f2955b9f"}, {
        {@"SpaceMono-Regular.ttf", 99356, @"95837e182baeeada83368f7748db28357f0a1b75c6b84ff7065b5edf933c8e18"},
        {@"SpaceMono-Bold.ttf", 98232, @"405e73d41afb7e5906efce206a326af5c956f38e255f35421c260e861e599c59"},
    }},
};

#pragma mark - the catalog

@interface SGLibraryFont ()
@property (nonatomic, readwrite, copy) NSString *identifier, *name;
@property (nonatomic, readwrite) BOOL korean;
@property (nonatomic, readwrite) NSUInteger styles;
@property (nonatomic, readwrite) long long bytes;
@property (nonatomic, readwrite, copy) NSURL *licenseURL;
@property (nonatomic) const SGFontFamilyLine *line;
@end

@implementation SGLibraryFont
@end

static NSURL *rawURL(NSString *identifier, NSString *file) {
    return [NSURL URLWithString:[NSString stringWithFormat:@"https://raw.githubusercontent.com/google/fonts/%@/ofl/%@/%@", kCommit, identifier, file]];
}

NSArray<SGLibraryFont *> *SGFontLibrary(void) {
    static NSArray<SGLibraryFont *> *all;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray<SGLibraryFont *> *fonts = [NSMutableArray array];
        for (size_t i = 0; i < sizeof kFamilies / sizeof *kFamilies; i++) {
            SGLibraryFont *font = [SGLibraryFont new];
            font.line = &kFamilies[i];
            font.identifier = kFamilies[i].identifier;
            font.name = kFamilies[i].name;
            font.korean = kFamilies[i].korean;
            for (const SGFontFileLine *file = kFamilies[i].files; file < kFamilies[i].files + 5 && file->name; file++) {
                font.styles++;
                font.bytes += file->size;
            }
            font.licenseURL = rawURL(font.identifier, kLicense);
            [fonts addObject:font];
        }
        all = fonts;
    });
    return all;
}

SGLibraryFont *SGFontLibraryFont(NSString *identifier) {
    for (SGLibraryFont *font in SGFontLibrary()) {
        if ([font.identifier isEqualToString:identifier]) return font;
    }
    return nil;
}

// The files a family is made of, its license last.
static NSArray<NSValue *> *linesOf(SGLibraryFont *font) {
    NSMutableArray<NSValue *> *lines = [NSMutableArray array];
    for (const SGFontFileLine *file = font.line->files; file < font.line->files + 5 && file->name; file++) [lines addObject:[NSValue valueWithPointer:file]];
    [lines addObject:[NSValue valueWithPointer:&font.line->license]];
    return lines;
}

#pragma mark - on this iPhone

static NSURL *libraryFolder(void) {
    return [SGDataRoot(NSApplicationSupportDirectory) URLByAppendingPathComponent:@"Font Library" isDirectory:YES];
}

static NSURL *familyFolder(NSString *identifier) {
    return [libraryFolder() URLByAppendingPathComponent:identifier isDirectory:YES];
}

static long long sizeOf(NSURL *url) {
    NSNumber *size = [url resourceValuesForKeys:@[NSURLFileSizeKey] error:nil][NSURLFileSizeKey];
    return size ? size.longLongValue : -1;
}

BOOL SGFontLibraryInstalled(NSString *identifier) {
    SGLibraryFont *font = SGFontLibraryFont(identifier);
    if (!font) return NO;
    NSURL *folder = familyFolder(identifier);
    for (const SGFontFileLine *file = font.line->files; file < font.line->files + 5 && file->name; file++) {
        if (sizeOf([folder URLByAppendingPathComponent:file->name]) != file->size) return NO;
    }
    return YES;
}

// Core Text registration is owned by one serial queue: the paths registered and the family name each
// registered family carries are read and written only on it, so a registration, a removal and a second
// request for the same family never run beside each other. SGFontLibraryRegister and SGFontLibraryRemove
// wait for it; SGFontLibraryRegisterInstalled does not.
static dispatch_queue_t registrationQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("spotifyglass.fontLibrary.registration", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

// Registration queue.
static NSMutableSet<NSString *> *registered(void) {
    static NSMutableSet<NSString *> *paths;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ paths = [NSMutableSet set]; });
    return paths;
}

// Registration queue.
static NSMutableDictionary<NSString *, NSString *> *registeredFamilies(void) {
    static NSMutableDictionary<NSString *, NSString *> *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ names = [NSMutableDictionary dictionary]; });
    return names;
}

// The family name each registered family's files carry as the pages see it, so they can ask on every row
// without reading a font file again. Main thread; filled from the registration queue's answers.
static NSMutableDictionary<NSString *, NSString *> *families(void) {
    static NSMutableDictionary<NSString *, NSString *> *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ names = [NSMutableDictionary dictionary]; });
    return names;
}

// The font files of the family on disk, without the license.
static NSArray<NSURL *> *fontFiles(SGLibraryFont *font) {
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    for (const SGFontFileLine *file = font.line->files; file < font.line->files + 5 && file->name; file++) {
        [urls addObject:[familyFolder(font.identifier) URLByAppendingPathComponent:file->name]];
    }
    return urls;
}

// Registration queue.
static NSString *registerOnQueue(SGLibraryFont *font) {
    NSString *identifier = font.identifier;
    NSString *known = registeredFamilies()[identifier];
    if (known) return known;
    if (!SGFontLibraryInstalled(identifier)) return nil;
    NSString *family = nil;
    for (NSURL *url in fontFiles(font)) {
        if (!family) {
            NSArray *faces = CFBridgingRelease(CTFontManagerCreateFontDescriptorsFromURL((__bridge CFURLRef)url));
            id face = faces.firstObject;
            if (face) family = CFBridgingRelease(CTFontDescriptorCopyAttribute((__bridge CTFontDescriptorRef)face, kCTFontFamilyNameAttribute));
        }
        if ([registered() containsObject:url.path]) continue;
        CFErrorRef error = NULL;
        if (CTFontManagerRegisterFontsForURL((__bridge CFURLRef)url, kCTFontManagerScopeProcess, &error)) {
            [registered() addObject:url.path];
        } else {
            NSError *failure = CFBridgingRelease(error);
            // Already registered by this process is as good as registered.
            if (failure.code == kCTFontManagerErrorAlreadyRegistered) [registered() addObject:url.path];
            else SGLog(@"fonts: %@ not registered: %@", url.lastPathComponent, failure.localizedDescription);
        }
    }
    if (!family.length || ![UIFont fontNamesForFamilyName:family].count) return nil;
    registeredFamilies()[identifier] = family;
    return family;
}

static void changed(NSString *identifier) {
    [NSNotificationCenter.defaultCenter postNotificationName:SGFontLibraryChangedNotification object:nil userInfo:identifier ? @{@"identifier": identifier} : nil];
}

// Main thread. Whether the family was new to the pages.
static BOOL publish(NSString *identifier, NSString *family) {
    if ([families()[identifier] isEqualToString:family]) return NO;
    families()[identifier] = family;
    return YES;
}

NSString *SGFontLibraryRegister(NSString *identifier) {
    SGLibraryFont *font = SGFontLibraryFont(identifier);
    if (!font) return nil;
    NSString *known = families()[identifier];
    if (known) return known;
    __block NSString *family;
    dispatch_sync(registrationQueue(), ^{ family = registerOnQueue(font); });
    if (family) publish(identifier, family);
    return family;
}

NSString *SGFontLibraryRegisteredFamily(NSString *identifier) {
    return families()[identifier];
}

void SGFontLibraryRegisterAsync(NSString *identifier, void (^done)(NSString *family)) {
    SGLibraryFont *font = SGFontLibraryFont(identifier);
    dispatch_async(registrationQueue(), ^{
        NSString *family = font ? registerOnQueue(font) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            // A removal that ran after the registration has taken the files and the family away.
            BOOL here = family && SGFontLibraryInstalled(identifier);
            if (here && publish(identifier, family)) changed(identifier);
            if (done) done(here ? family : nil);
        });
    });
}

void SGFontLibraryRegisterInstalled(void) {
    for (SGLibraryFont *font in SGFontLibrary()) SGFontLibraryRegisterAsync(font.identifier, nil);
}

void SGFontLibraryRemove(NSString *identifier) {
    SGLibraryFont *font = SGFontLibraryFont(identifier);
    if (!font) return;
    dispatch_sync(registrationQueue(), ^{
        for (NSURL *url in fontFiles(font)) {
            if ([registered() containsObject:url.path]) {
                CTFontManagerUnregisterFontsForURL((__bridge CFURLRef)url, kCTFontManagerScopeProcess, NULL);
                [registered() removeObject:url.path];
            }
        }
        [NSFileManager.defaultManager removeItemAtURL:familyFolder(identifier) error:nil];
        [registeredFamilies() removeObjectForKey:identifier];
    });
    [families() removeObjectForKey:identifier];
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    if (SGAppFontChosen() == SGAppFontLibrary && [[store stringForKey:SGKeyAppFontLibrary] isEqualToString:identifier]) {
        [store removeObjectForKey:SGKeyAppFont];
        [store removeObjectForKey:SGKeyAppFontLibrary];
        SGPrefsChanged();
    }
    changed(identifier);
}

#pragma mark - downloading

// One family's files, one after the other, into a folder of its own beside the library's families, moved into
// place once every one has checked out. Its delegate queue is serial and off main; what the page reads is set
// on main.
@interface SGFontDownload : NSObject <NSURLSessionDownloadDelegate>
@end

static SGFontDownload *sg_download;   // main thread
static double sg_progress;            // main thread

@implementation SGFontDownload {
    SGLibraryFont *_font;
    NSArray<NSValue *> *_lines;
    NSUInteger _index;
    long long _done, _total;
    NSURLSession *_session;
    NSURLSessionDownloadTask *_task;
    NSURL *_incoming;
    NSString *_failure;     // set once the download has failed or been cancelled
    BOOL _accepted;         // the file the current task brought checked out
    CFAbsoluteTime _posted;
    void (^_completion)(NSString *error);
}

- (instancetype)initWithFont:(SGLibraryFont *)font completion:(void (^)(NSString *error))completion {
    if (!(self = [super init])) return nil;
    _font = font;
    _lines = linesOf(font);
    for (NSValue *line in _lines) _total += ((const SGFontFileLine *)line.pointerValue)->size;
    _completion = [completion copy];
    _incoming = [libraryFolder() URLByAppendingPathComponent:[@".incoming-" stringByAppendingString:font.identifier] isDirectory:YES];
    NSOperationQueue *queue = [NSOperationQueue new];
    queue.maxConcurrentOperationCount = 1;
    queue.qualityOfService = NSQualityOfServiceUserInitiated;
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.timeoutIntervalForRequest = 60;
    configuration.timeoutIntervalForResource = 600;
    _session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:queue];
    return self;
}

- (void)start {
    [_session.delegateQueue addOperationWithBlock:^{
        NSFileManager *files = NSFileManager.defaultManager;
        [files removeItemAtURL:self->_incoming error:nil];
        NSError *error = nil;
        if (![files createDirectoryAtURL:self->_incoming withIntermediateDirectories:YES attributes:nil error:&error]) {
            [self fail:[NSString stringWithFormat:SGL(@"settings.font.library.error.disk", @"The font could not be saved on this iPhone: %@"), error.localizedDescription]];
            return;
        }
        [self next];
    }];
}

- (const SGFontFileLine *)current {
    return (const SGFontFileLine *)_lines[_index].pointerValue;
}

- (NSString *)identifier {
    return _font.identifier;
}

// Delegate queue.
- (void)next {
    if (_failure) return;
    if (_index == _lines.count) {
        [self finish];
        return;
    }
    _accepted = NO;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:rawURL(_font.identifier, self.current->name)];
    _task = [_session downloadTaskWithRequest:request];
    [_task resume];
}

// Delegate queue: every file is in the incoming folder, so it takes the family's place.
- (void)finish {
    NSFileManager *files = NSFileManager.defaultManager;
    NSURL *target = familyFolder(_font.identifier);
    NSError *error = nil;
    [files removeItemAtURL:target error:nil];
    if (![files moveItemAtURL:_incoming toURL:target error:&error]) {
        [self fail:[NSString stringWithFormat:SGL(@"settings.font.library.error.disk", @"The font could not be saved on this iPhone: %@"), error.localizedDescription]];
        return;
    }
    [_session finishTasksAndInvalidate];
    dispatch_async(dispatch_get_main_queue(), ^{ [self endWith:nil]; });
}

// Delegate queue. An empty message is a cancel.
- (void)fail:(NSString *)message {
    if (_failure) return;
    _failure = message;
    [_task cancel];
    [_session invalidateAndCancel];
    [NSFileManager.defaultManager removeItemAtURL:_incoming error:nil];
    dispatch_async(dispatch_get_main_queue(), ^{ [self endWith:message]; });
}

- (void)cancel {
    [_session.delegateQueue addOperationWithBlock:^{ [self fail:@""]; }];
}

// Main thread.
- (void)endWith:(NSString *)error {
    if (sg_download != self) return;
    sg_download = nil;
    sg_progress = 0;
    SGLog(@"fonts: %@ %@", self->_font.identifier, error ? (error.length ? [@"failed: " stringByAppendingString:error] : @"cancelled") : @"downloaded");
    if (self->_completion) self->_completion(error);
    self->_completion = nil;
    changed(self->_font.identifier);
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didWriteData:(int64_t)bytes
 totalBytesWritten:(int64_t)written totalBytesExpectedToWrite:(int64_t)expected {
    if (_failure || task != _task) return;
    double progress = _total > 0 ? MIN(1.0, (double)(_done + MIN(written, self.current->size)) / _total) : 0;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - _posted < 0.1) return;
    _posted = now;
    NSString *identifier = _font.identifier;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (sg_download != self) return;
        sg_progress = progress;
        changed(identifier);
    });
}

// The file must be moved before this returns, or the system deletes it.
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didFinishDownloadingToURL:(NSURL *)location {
    if (_failure || task != _task) return;
    NSInteger status = [task.response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)task.response).statusCode : 0;
    if (status != 200) {
        [self fail:[NSString stringWithFormat:SGL(@"settings.font.library.error.server", @"GitHub answered with an error (%ld). Try again later."), (long)status]];
        return;
    }
    const SGFontFileLine *line = self.current;
    if (sizeOf(location) != line->size || ![SGFileSHA256(location) isEqualToString:line->sha256]) {
        [self fail:SGL(@"settings.font.library.error.damaged", @"A file did not arrive intact. Try again.")];
        return;
    }
    NSError *error = nil;
    if (![NSFileManager.defaultManager moveItemAtURL:location toURL:[_incoming URLByAppendingPathComponent:line->name] error:&error]) {
        [self fail:[NSString stringWithFormat:SGL(@"settings.font.library.error.disk", @"The font could not be saved on this iPhone: %@"), error.localizedDescription]];
        return;
    }
    _accepted = YES;
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (_failure || task != _task) return;
    if (error || !_accepted) {
        [self fail:[NSString stringWithFormat:SGL(@"settings.font.library.error.network", @"The download stopped: %@"),
                    error.localizedDescription ?: SGL(@"settings.font.library.error.no_file", @"no file came back")]];
        return;
    }
    _done += self.current->size;
    _index++;
    [self next];
}

@end

NSString *SGFontLibraryDownloading(void) {
    return sg_download.identifier;
}

double SGFontLibraryProgress(void) {
    return sg_progress;
}

void SGFontLibraryDownload(NSString *identifier, void (^done)(NSString *error)) {
    SGLibraryFont *font = SGFontLibraryFont(identifier);
    if (!font) return;
    if (sg_download) {
        if (done) done(SGL(@"settings.font.library.error.busy", @"Another font is downloading. Wait for it to finish, or stop it first."));
        return;
    }
    sg_download = [[SGFontDownload alloc] initWithFont:font completion:done];
    sg_progress = 0;
    changed(identifier);
    [sg_download start];
}

void SGFontLibraryCancel(void) {
    [sg_download cancel];
}

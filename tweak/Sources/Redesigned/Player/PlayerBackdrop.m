// Player redesign: pure black, or a photo of the user's own, behind the player in place of the artwork's field.
//
// Either is a view laid over the field, on top of it and as far as its bleed reaches, so the pull that dismisses
// the player and the bounce at the end of the cards show black too; the field under it is covered and held still
// (PlayerField.x), and is made as the artwork's last choice, so going back to the artwork needs no restart. The
// photo fills the screen from its middle, as a wallpaper does, and is darkened the way the Animated artwork's clip
// is (SGRPlayerClipDim): by how bright it is, so white text over it keeps 4.5:1 (7:1 with Increase Contrast), and a
// little more, with a blur, behind the lyrics.
//
// The photo is picked from the photo library (PHPicker, which needs no permission to the library), drawn at
// kLongestSide pixels on its longer side at most, and kept as a JPEG in Library/Application Support/Retrine. It is
// read once a launch, when first shown. Nothing is uploaded.
//
// Threading: views and the prepared cache are main-thread only. Reading, decoding and brightness
// measurement run off main; import generations and file commits share one serial queue.
#import <PhotosUI/PhotosUI.h>
#import "Core/SGCore.h"
#import "Core/SGDataRoot.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Player.h"

NSNotificationName const SGRPlayerPhotoDidChangeNotification = @"spotifyglass.redesign.player.photoDidChange";
static const CGFloat kLongestSide = 2048;
static char kBackdropKey;

static NSURL *photoURL(void) {
    return [SGDataRoot(NSApplicationSupportDirectory) URLByAppendingPathComponent:@"PlayerPhoto.jpg"];
}

static UIImage *sg_photo;
static BOOL sg_photoRead, sg_photoLoading;
static CGFloat sg_photoBright;
static NSMutableArray<void (^)(BOOL)> *sg_photoWaiters;
static NSUInteger sg_importGeneration;   // main: selections and completion delivery
static NSUInteger sg_storeGeneration;    // photoQueue: generation admission and file commits

static dispatch_queue_t photoQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("spotifyglass.player.photo", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

// Draw upright into a decoded bitmap off main, at the storage size. This same prepared image is
// published after an import; neither the main thread nor a redisplay reopens or decodes its JPEG.
static UIImage *preparePhoto(UIImage *image) {
    CGSize pixels = CGSizeMake(image.size.width * image.scale, image.size.height * image.scale);
    CGFloat longer = MAX(pixels.width, pixels.height);
    if (longer <= 0) return nil;
    CGFloat shrink = MIN(1, kLongestSide / longer);
    CGSize size = CGSizeMake(MAX(1, round(pixels.width * shrink)), MAX(1, round(pixels.height * shrink)));
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1;
    format.opaque = YES;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [image drawInRect:(CGRect){CGPointZero, size}];
    }];
}

// Main only: the pixels and their measurement become visible together, before any observer reloads.
static void publishPhoto(UIImage *image, CGFloat brightness) {
    sg_photo = image;
    sg_photoBright = brightness;
    sg_photoRead = YES;
    sg_photoLoading = NO;
    NSArray<void (^)(BOOL)> *waiters = sg_photoWaiters;
    sg_photoWaiters = nil;
    [NSNotificationCenter.defaultCenter postNotificationName:SGRPlayerPhotoDidChangeNotification object:nil];
    for (void (^done)(BOOL) in waiters) done(image != nil);
}

void SGRPlayerLoadPhoto(void (^done)(BOOL available)) {
    if (sg_photoRead) {
        if (done) done(sg_photo != nil);
        return;
    }
    if (done) {
        if (!sg_photoWaiters) sg_photoWaiters = [NSMutableArray array];
        [sg_photoWaiters addObject:[done copy]];
    }
    if (sg_photoLoading) return;
    sg_photoLoading = YES;
    dispatch_async(photoQueue(), ^{
        NSURL *file = photoURL();
        UIImage *image = file ? preparePhoto([UIImage imageWithContentsOfFile:file.path]) : nil;
        CGFloat brightness = image ? SGRPlayerImageBrightEnd(image.CGImage) : 0;
        dispatch_async(dispatch_get_main_queue(), ^{
            // A prepared import can satisfy the pending read before its callback is delivered.
            if (!sg_photoRead && file) publishPhoto(image, brightness);
            else if (!sg_photoRead) {
                sg_photoLoading = NO;
                NSArray *waiters = sg_photoWaiters;
                sg_photoWaiters = nil;
                for (void (^waiter)(BOOL) in waiters) waiter(NO);
            }
        });
    });
}

static UIImage *storedPhoto(void) {
    SGRPlayerLoadPhoto(nil);
    return sg_photo;
}

#pragma mark - the view

@interface SGRPlayerBackdropView : UIView
// The part of the view the screen shows at rest, which the photo fills; the whole bounds when empty.
@property (nonatomic) CGRect screen;
// What it draws now, read again by -reload.
@property (nonatomic, readonly) SGRPlayerBackgroundKind kind;
- (void)reload;
- (void)setLyrics:(BOOL)lyrics animated:(BOOL)animated;
@end

@implementation SGRPlayerBackdropView {
    UIImageView *_photo;
    CALayer *_dim;
    UIVisualEffectView *_blur;
    BOOL _lyrics;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.accessibilityElementsHidden = YES;
    self.backgroundColor = UIColor.blackColor;
    self.clipsToBounds = YES;
    _photo = [UIImageView new];
    _photo.contentMode = UIViewContentModeScaleAspectFill;
    _photo.clipsToBounds = YES;
    [self addSubview:_photo];
    _dim = [CALayer layer];
    _dim.backgroundColor = UIColor.blackColor.CGColor;
    [self.layer addSublayer:_dim];
    _blur = [[UIVisualEffectView alloc] initWithEffect:nil];
    _blur.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [self addSubview:_blur];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(reload) name:SGRPlayerPhotoDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(updateDim) name:UIAccessibilityDarkerSystemColorsStatusDidChangeNotification object:nil];
    [self reload];
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)reload {
    _kind = SGRPlayerBackground();
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _photo.image = _kind == SGRPlayerBackgroundPhoto ? storedPhoto() : nil;
    [self updateDim];
    [CATransaction commit];
    _blur.effect = _lyrics && _photo.image ? [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark] : nil;
}

- (void)updateDim {
    CGFloat dim = _photo.image ? SGRPlayerClipDim(sg_photoBright, UIAccessibilityDarkerSystemColorsEnabled(), _lyrics) : 0;
    _dim.opacity = (float)dim;
}

- (void)setLyrics:(BOOL)lyrics animated:(BOOL)animated {
    if (lyrics == _lyrics) return;
    _lyrics = lyrics;
    BOOL blurred = lyrics && _photo.image;
    [CATransaction begin];
    [CATransaction setDisableActions:!animated];
    [CATransaction setAnimationDuration:SGRCrossfade];
    [self updateDim];
    [CATransaction commit];
    void (^apply)(void) = ^{ self->_blur.effect = blurred ? [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark] : nil; };
    if (animated) SGRAnimate(SGRMotionFade, apply, nil);
    else apply();
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _photo.frame = CGRectIsEmpty(self.screen) ? bounds : self.screen;
    _dim.frame = bounds;
    _blur.frame = bounds;
    [CATransaction commit];
}

@end

#pragma mark - over the player's field

static __weak SGRPlayerBackdropView *sg_backdrop;

void SGRPlayerBackdropLaidOut(SGRArtworkField *field) {
    if (!field) return;
    SGRPlayerBackdropView *view = objc_getAssociatedObject(field, &kBackdropKey);
    if (SGRPlayerBackgroundFromArtwork(SGRPlayerBackground())) {
        if (!view) return;
        [view removeFromSuperview];
        objc_setAssociatedObject(field, &kBackdropKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        field.covered = NO;
        SGRPlayerHoldField();
        SGLog(@"redesign player: black or the photo taken away, the artwork behind the player");
        return;
    }
    BOOL made = !view;
    if (made) {
        view = [[SGRPlayerBackdropView alloc] initWithFrame:field.bounds];
        objc_setAssociatedObject(field, &kBackdropKey, view, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [view setLyrics:SGRPlayerLyricsOpen() animated:NO];
        SGLog(@"redesign player: %@ behind the player", SGRPlayerBackground() == SGRPlayerBackgroundPhoto ? @"the photo" : @"black");
    }
    sg_backdrop = view;
    if (view.kind != SGRPlayerBackground()) [view reload];   // switched between black and the photo
    if (view.superview != field || field.subviews.lastObject != view) [field addSubview:view];
    // The field under it holds still from now on (PlayerField.x's fieldHeld).
    if (made) SGRPlayerHoldField();
    UIEdgeInsets bleed = field.bleed;
    CGSize size = field.bounds.size;
    CGRect frame = CGRectMake(0, -bleed.top, size.width, size.height + bleed.top + bleed.bottom);
    if (!CGRectEqualToRect(view.frame, frame)) view.frame = frame;
    CGFloat screen = field.window.bounds.size.height ?: size.height;
    CGRect shown = CGRectMake(0, bleed.top, size.width, screen);
    if (!CGRectEqualToRect(view.screen, shown)) {
        view.screen = shown;
        [view setNeedsLayout];
    }
    field.covered = YES;
}

BOOL SGRPlayerBackdropShowing(void) {
    return sg_backdrop.superview != nil;
}

void SGRPlayerBackdropLyricsChanged(void) {
    SGRPlayerBackdropView *view = sg_backdrop;
    [view setLyrics:SGRPlayerLyricsOpen() animated:view.window != nil];
}

UIView *SGRPlayerBackdropPreview(void) {
    if (SGRPlayerBackgroundFromArtwork(SGRPlayerBackground())) return nil;
    return [[SGRPlayerBackdropView alloc] initWithFrame:CGRectZero];
}

#pragma mark - picking the photo

@interface SGRPlayerPhotoPicker : NSObject <PHPickerViewControllerDelegate>
@property (nonatomic, copy) void (^done)(BOOL stored);
@end

static SGRPlayerPhotoPicker *sg_picker;   // kept while the picker is up; its delegate is weak

@implementation SGRPlayerPhotoPicker

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    void (^done)(BOOL) = self.done;
    sg_picker = nil;
    [picker dismissViewControllerAnimated:YES completion:nil];
    NSItemProvider *provider = results.firstObject.itemProvider;
    if (![provider canLoadObjectOfClass:UIImage.class]) {
        if (done) done(NO);
        return;
    }
    NSUInteger generation = ++sg_importGeneration;
    // Admit the selection before starting its provider request. A later selection's admission and an
    // older request's check/write are ordered on this queue, never a check followed by an unlocked write.
    dispatch_async(photoQueue(), ^{ sg_storeGeneration = generation; });
    [provider loadObjectOfClass:UIImage.class completionHandler:^(id<NSItemProviderReading> object, NSError *error) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            UIImage *image = [(id)object isKindOfClass:UIImage.class] ? preparePhoto((UIImage *)object) : nil;
            NSData *data = image ? UIImageJPEGRepresentation(image, 0.9) : nil;
            CGFloat brightness = image ? SGRPlayerImageBrightEnd(image.CGImage) : 0;
            dispatch_async(photoQueue(), ^{
                if (generation != sg_storeGeneration) {
                    dispatch_async(dispatch_get_main_queue(), ^{ if (done) done(NO); });
                    return;
                }
                NSURL *url = photoURL();
                NSError *failure = error;
                BOOL stored = data && url && [NSFileManager.defaultManager createDirectoryAtURL:url.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&failure]
                    && [data writeToURL:url options:NSDataWritingAtomic error:&failure];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (stored) {
                        publishPhoto(image, brightness);
                        SGLog(@"redesign player: a photo of %lu KB stored for behind the player", (unsigned long)(data.length / 1024));
                    } else {
                        SGLog(@"redesign player: the picked photo could not be stored: %@", failure);
                    }
                    if (done) done(stored && generation == sg_importGeneration);
                });
            });
        });
    }];
}

@end

void SGRPlayerPickPhoto(UIViewController *from, void (^done)(BOOL stored)) {
    if (!from) {
        if (done) done(NO);
        return;
    }
    PHPickerConfiguration *configuration = [PHPickerConfiguration new];
    configuration.filter = PHPickerFilter.imagesFilter;
    configuration.selectionLimit = 1;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
    sg_picker = [SGRPlayerPhotoPicker new];
    sg_picker.done = done;
    picker.delegate = sg_picker;
    [from presentViewController:picker animated:YES completion:nil];
}

// Share cards (ShareCards.h): a 4:5 picture, the size a social post takes whole, of the song or of lines of its
// lyrics over its cover blurred and darkened, so white reads over any cover. What goes on it (the cover, the title
// and the artist as the player shows them) is read on the main thread; the drawing runs on a worker, and the share
// sheet comes up once it is done.
#import "Core/SGImageContext.h"
#import "Core/SGCore.h"
#import "Core/SGGlass.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Player/PlayerState.h"
#import "Headers/SPTPlayer.h"
#import "Redesigned/Kit/SGRBridges.h"
#import "Player.h"
#import "ShareCards.h"

@implementation SGRLyricCardLine
@end

static const CGSize kCardPixels = {1080, 1350};
static const CGFloat kMarginPixels = 96;
// The blurred cover overfills the card so its soft edges fall outside it. It is blurred this many pixels across,
// which loses nothing the blur keeps, by a radius of this share of that.
static const CGFloat kBackdropOverfill = 1.15, kBlurPixels = 256, kBlurRadiusShare = 1.0 / 12;
static const CGFloat kLyricShade = 0.38, kSongShade = 0.32;   // black over the blurred cover
static const CGFloat kDimText = 0.72;   // the artist's and the pronunciation's white

// The lyric card: the cover small at the top with the title and the artist beside it, the lines under them.
static const CGFloat kThumbPixels = 132, kThumbRadius = 18, kThumbGap = 32, kHeaderLineGap = 6;
static const CGFloat kHeaderTitlePoints = 42, kHeaderArtistPoints = 34;
static const CGFloat kLinesTopGap = 72;
// The lines are set as large as the room lets them be, from the first size down to the last.
static const CGFloat kLinesLargestPoints = 76, kLinesSmallestPoints = 30, kLinesStepPoints = 4;
static const CGFloat kPronunciationShare = 0.62, kLineSpacingShare = 0.12, kParagraphSpacingShare = 0.45;

// The song card: the cover large and rounded over its shadow, the title and the artist centred under it.
static const CGFloat kArtPixels = 720, kArtTop = 170, kArtRadius = 40, kArtShadowDrop = 30, kArtShadowBlur = 60, kArtShadow = 0.55;
static const CGFloat kPlaceholderWhite = 0.12;   // where a track has no cover in yet
static const CGFloat kSongTitlePoints = 64, kSongArtistPoints = 42, kSongTextTop = 70, kSongTextGap = 12, kSongSideMargin = 80;
static const NSUInteger kSongTitleLines = 2;

// The playing track's cover as the redesign has it, nil until that track's own picture is in.
static UIImage *playingCover(void) {
    NSString *uri = nil;
    UIImage *cover = SGRNowPlayingArtwork(&uri, NULL);
    NSString *playing = SGURIString(SGPlayerState().track.URI);
    return playing.length && [uri isEqualToString:playing] ? cover : nil;
}

// The title and the artist as the player shows them, simplified or translated as the Lyrics page sets.
static void songText(SPTPlayerTrack *track, NSString *trackID, NSString **title, NSString **artist) {
    *title = SGRShownTitle(trackID, track.trackTitle, track.artistName, artist);
}

// Snapshot the display-dependent range on main. The worker draws strings and
// images into private bitmap contexts; it never needs a view or a screen.
static UIGraphicsImageRendererFormat *cardFormat(void) {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1;
    format.opaque = YES;
    return format;
}

static UIImage *blurred(UIImage *cover, UIGraphicsImageRendererFormat *format) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(kBlurPixels, kBlurPixels) format:format];
    UIImage *small = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [cover drawInRect:CGRectMake(0, 0, kBlurPixels, kBlurPixels)];
    }];
    CIImage *input = [CIImage imageWithCGImage:small.CGImage];
    CIFilter *blur = [CIFilter filterWithName:@"CIGaussianBlur"];
    [blur setValue:input.imageByClampingToExtent forKey:kCIInputImageKey];
    [blur setValue:@(kBlurPixels * kBlurRadiusShare) forKey:kCIInputRadiusKey];
    CIImage *output = [blur.outputImage imageByCroppingToRect:input.extent];
    CGImageRef image = output ? [SGOneOffImageContext() createCGImage:output fromRect:input.extent] : NULL;
    if (!image) return nil;
    UIImage *result = [UIImage imageWithCGImage:image];
    CGImageRelease(image);
    return result;
}

// Black, then the cover blurred over the whole card and darkened by `shade`.
static void drawBackdrop(UIImage *cover, CGFloat shade, UIGraphicsImageRendererFormat *format) {
    CGRect bounds = {CGPointZero, kCardPixels};
    [UIColor.blackColor setFill];
    UIRectFill(bounds);
    UIImage *back = cover ? blurred(cover, format) : nil;
    if (!back) return;
    CGFloat side = MAX(kCardPixels.width, kCardPixels.height) * kBackdropOverfill;
    [back drawInRect:CGRectMake((kCardPixels.width - side) / 2, (kCardPixels.height - side) / 2, side, side)];
    [[UIColor colorWithWhite:0 alpha:shade] setFill];
    UIRectFillUsingBlendMode(bounds, kCGBlendModeNormal);
}

static void drawRounded(UIImage *cover, CGRect rect, CGFloat radius, CGContextRef context) {
    CGContextSaveGState(context);
    [[UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:radius] addClip];
    if (cover) {
        [cover drawInRect:rect];
    } else {
        [[UIColor colorWithWhite:1 alpha:kPlaceholderWhite] setFill];
        UIRectFill(rect);
    }
    CGContextRestoreGState(context);
}

// Each line a paragraph against its own side, its pronunciation on a line of the same paragraph (U+2028) so the two
// keep to one side and the room between lines falls after the pair.
static NSAttributedString *linesText(NSArray<SGRLyricCardLine *> *lines, BOOL pronunciation, CGFloat points) {
    NSMutableAttributedString *text = [NSMutableAttributedString new];
    UIFont *words = [UIFont systemFontOfSize:points weight:UIFontWeightHeavy];
    UIFont *spoken = [UIFont systemFontOfSize:round(points * kPronunciationShare) weight:UIFontWeightSemibold];
    for (NSUInteger i = 0; i < lines.count; i++) {
        SGRLyricCardLine *line = lines[i];
        NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
        style.alignment = line.rightToLeft ? NSTextAlignmentRight : NSTextAlignmentLeft;
        style.baseWritingDirection = line.rightToLeft ? NSWritingDirectionRightToLeft : NSWritingDirectionLeftToRight;
        style.lineSpacing = points * kLineSpacingShare;
        style.paragraphSpacing = points * kParagraphSpacingShare;
        NSString *reading = pronunciation ? line.pronunciation : nil;
        NSUInteger start = text.length;
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:line.text attributes:@{
            NSFontAttributeName: words, NSForegroundColorAttributeName: UIColor.whiteColor}]];
        if (reading.length) {
            [text appendAttributedString:[[NSAttributedString alloc] initWithString:[@"\u2028" stringByAppendingString:reading] attributes:@{
                NSFontAttributeName: spoken, NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:kDimText]}]];
        }
        if (i + 1 < lines.count) [text appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:@{NSFontAttributeName: words}]];
        [text addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(start, text.length - start)];
    }
    return text;
}

static NSDictionary *oneLine(UIFont *font, UIColor *color, NSTextAlignment alignment) {
    NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
    style.alignment = alignment;
    style.lineBreakMode = NSLineBreakByTruncatingTail;
    return @{NSFontAttributeName: font, NSForegroundColorAttributeName: color, NSParagraphStyleAttributeName: style};
}

// `rightToLeft`: the phone's language reads right to left, so the cover leads from the right.
static UIImage *lyricCardImage(NSArray<SGRLyricCardLine *> *lines, BOOL pronunciation, NSString *title, NSString *artist,
                               UIImage *cover, BOOL rightToLeft, UIGraphicsImageRendererFormat *format) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:kCardPixels format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        drawBackdrop(cover, kLyricShade, format);
        CGFloat width = kCardPixels.width;
        CGRect thumb = CGRectMake(rightToLeft ? width - kMarginPixels - kThumbPixels : kMarginPixels, kMarginPixels, kThumbPixels, kThumbPixels);
        drawRounded(cover, thumb, kThumbRadius, context.CGContext);
        CGFloat textWidth = width - 2 * kMarginPixels - kThumbPixels - kThumbGap;
        CGFloat textLeft = rightToLeft ? kMarginPixels : CGRectGetMaxX(thumb) + kThumbGap;
        UIFont *titleFont = [UIFont systemFontOfSize:kHeaderTitlePoints weight:UIFontWeightBold];
        UIFont *artistFont = [UIFont systemFontOfSize:kHeaderArtistPoints weight:UIFontWeightMedium];
        CGFloat titleHeight = ceil(titleFont.lineHeight), artistHeight = ceil(artistFont.lineHeight);
        CGFloat titleTop = CGRectGetMinY(thumb) + (kThumbPixels - titleHeight - kHeaderLineGap - artistHeight) / 2;
        NSTextAlignment side = rightToLeft ? NSTextAlignmentRight : NSTextAlignmentLeft;
        [(title ?: @"") drawInRect:CGRectMake(textLeft, titleTop, textWidth, titleHeight) withAttributes:oneLine(titleFont, UIColor.whiteColor, side)];
        [(artist ?: @"") drawInRect:CGRectMake(textLeft, titleTop + titleHeight + kHeaderLineGap, textWidth, artistHeight)
                     withAttributes:oneLine(artistFont, [UIColor colorWithWhite:1 alpha:kDimText], side)];

        // The lines centred in the room under the header, as large as it lets them be.
        CGFloat top = CGRectGetMaxY(thumb) + kLinesTopGap;
        CGRect room = CGRectMake(kMarginPixels, top, width - 2 * kMarginPixels, kCardPixels.height - kMarginPixels - top);
        NSAttributedString *text = nil;
        CGFloat used = 0;
        for (CGFloat points = kLinesLargestPoints; points >= kLinesSmallestPoints; points -= kLinesStepPoints) {
            text = linesText(lines, pronunciation, points);
            used = ceil([text boundingRectWithSize:CGSizeMake(room.size.width, CGFLOAT_MAX)
                                           options:NSStringDrawingUsesLineFragmentOrigin context:nil].size.height);
            if (used <= room.size.height) break;
        }
        CGFloat y = top + MAX(0, (room.size.height - used) / 2);
        [text drawWithRect:CGRectMake(room.origin.x, y, room.size.width, CGRectGetMaxY(room) - y)
                   options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingTruncatesLastVisibleLine context:nil];
    }];
}

static UIImage *songCardImage(UIImage *cover, NSString *title, NSString *artist, UIGraphicsImageRendererFormat *format) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:kCardPixels format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        drawBackdrop(cover, kSongShade, format);
        CGContextRef cg = context.CGContext;
        CGRect art = CGRectMake((kCardPixels.width - kArtPixels) / 2, kArtTop, kArtPixels, kArtPixels);
        CGContextSaveGState(cg);
        CGContextSetShadowWithColor(cg, CGSizeMake(0, kArtShadowDrop), kArtShadowBlur, [UIColor colorWithWhite:0 alpha:kArtShadow].CGColor);
        [[UIBezierPath bezierPathWithRoundedRect:art cornerRadius:kArtRadius] fill];
        CGContextRestoreGState(cg);
        drawRounded(cover, art, kArtRadius, cg);

        NSMutableParagraphStyle *centred = [NSMutableParagraphStyle new];
        centred.alignment = NSTextAlignmentCenter;
        UIFont *titleFont = [UIFont systemFontOfSize:kSongTitlePoints weight:UIFontWeightHeavy];
        NSAttributedString *shownTitle = [[NSAttributedString alloc] initWithString:title ?: @"" attributes:@{
            NSFontAttributeName: titleFont, NSForegroundColorAttributeName: UIColor.whiteColor, NSParagraphStyleAttributeName: centred}];
        CGFloat textWidth = kCardPixels.width - 2 * kSongSideMargin, textTop = CGRectGetMaxY(art) + kSongTextTop;
        CGRect titleRoom = CGRectMake(kSongSideMargin, textTop, textWidth, ceil(titleFont.lineHeight * kSongTitleLines));
        NSStringDrawingOptions options = NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingTruncatesLastVisibleLine;
        CGFloat titleHeight = MIN(titleRoom.size.height, ceil([shownTitle boundingRectWithSize:CGSizeMake(textWidth, CGFLOAT_MAX)
                                                                                      options:NSStringDrawingUsesLineFragmentOrigin context:nil].size.height));
        [shownTitle drawWithRect:titleRoom options:options context:nil];
        UIFont *artistFont = [UIFont systemFontOfSize:kSongArtistPoints weight:UIFontWeightSemibold];
        [(artist ?: @"") drawInRect:CGRectMake(kSongSideMargin, textTop + titleHeight + kSongTextGap, textWidth, ceil(artistFont.lineHeight))
                     withAttributes:oneLine(artistFont, [UIColor colorWithWhite:1 alpha:kDimText], NSTextAlignmentCenter)];
    }];
}

// The share sheet with the card, on `host` (the top controller when nil), from `item` or else `source`.
static void presentCard(UIImage *card, UIViewController *host, UIView *source, UIBarButtonItem *item, void (^done)(BOOL shared)) {
    UIViewController *presenter = host ?: SGTopController();
    if (!presenter) {
        SGLog(@"share card: no controller to present the share sheet on");
        if (done) done(NO);
        return;
    }
    UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:@[card] applicationActivities:nil];
    if (item) {
        sheet.popoverPresentationController.barButtonItem = item;
    } else {
        UIView *anchor = source.window ? source : presenter.view;
        sheet.popoverPresentationController.sourceView = anchor;
        sheet.popoverPresentationController.sourceRect = anchor.bounds;
    }
    sheet.completionWithItemsHandler = ^(UIActivityType type, BOOL completed, NSArray *items, NSError *error) {
        if (done) done(completed);
    };
    SGPresentDark(sheet);
    [presenter presentViewController:sheet animated:YES completion:nil];
}

void SGRShareSongCard(UIView *source) {
    SPTPlayerTrack *track = SGPlayerState().track;
    if (!track) return;
    NSString *title = nil, *artist = nil;
    songText(track, SGKaraokePlayingTrack(), &title, &artist);
    UIImage *cover = playingCover();
    __weak UIView *anchor = source;
    UIGraphicsImageRendererFormat *format = cardFormat();
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        CFAbsoluteTime began = CFAbsoluteTimeGetCurrent();
        UIImage *card = songCardImage(cover, title, artist, format);
        CFAbsoluteTime took = CFAbsoluteTimeGetCurrent() - began;
        dispatch_async(dispatch_get_main_queue(), ^{
            SGLog(@"share card: the song's, %@ cover, drawn in %.0f ms", cover ? @"with its" : @"without a", took * 1000);
            presentCard(card, nil, anchor, nil, nil);
        });
    });
}

void SGRShareLyricCard(NSArray<SGRLyricCardLine *> *lines, BOOL pronunciation, NSString *trackID, UIViewController *host,
                       UIBarButtonItem *item, void (^done)(BOOL shared)) {
    NSString *title = nil, *artist = nil;
    songText(SGKaraokeTrackFor(trackID), trackID, &title, &artist);
    UIImage *cover = [trackID isEqualToString:SGKaraokePlayingTrack()] ? playingCover() : nil;
    BOOL rightToLeft = UIApplication.sharedApplication.userInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    NSArray<SGRLyricCardLine *> *shown = [lines copy];
    __weak UIViewController *presenter = host;
    UIGraphicsImageRendererFormat *format = cardFormat();
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        CFAbsoluteTime began = CFAbsoluteTimeGetCurrent();
        UIImage *card = lyricCardImage(shown, pronunciation, title, artist, cover, rightToLeft, format);
        CFAbsoluteTime took = CFAbsoluteTimeGetCurrent() - began;
        dispatch_async(dispatch_get_main_queue(), ^{
            UIViewController *on = presenter;
            if (!on.view.window) {
                if (done) done(NO);
                return;
            }
            SGLog(@"share card: %lu lines of the lyrics, pronunciation %@, drawn in %.0f ms", (unsigned long)shown.count,
                  pronunciation ? @"on" : @"off", took * 1000);
            presentCard(card, on, nil, item, done);
        });
    });
}

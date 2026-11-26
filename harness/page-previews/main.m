// The live preview cards of the redesign's page settings (Redesigned/Kit/SGRPagePreview.m), on the pages the real
// builders make (PlaylistSettings.m, HomeSettings.m, SearchSettings.m, AlbumSettings.m, ArtistSettings.m), under real
// UIKit in an iOS simulator (build.sh). Each card is drawn in its default state, then the page's settings are changed while it is
// on screen and it is drawn again; then with a light and a dark accent color, and at a large text size. Each state's
// card is written to build/png/<page>-<state>.png, and the default page whole to build/png/<page>-page.png.
//
// Checked: what VoiceOver reads off each card in each state (the parts shown, by name), that a change while the card
// is in sight animates and one while it is scrolled out of sight is left undrawn until the card is back in sight,
// then drawn at once, that a part a switch brings back below the card's foot is scrolled into sight
// (<page>-revealed.png), that Home's page color goes with the Top picks colors (home-no-colour.png) and the artist's
// field with the photo shown, and that the card grows with the text.
//
// The `rtl` launch (build.sh's second, the app right to left) runs the same checks, its PNGs named <...>-rtl.png, then
// the mirror check against the layouts the left to right launch noted (png/mirror-ltr.plist): every view of each card,
// in the card's coordinates, on the other side of the card, but for the header's controls, which keep their order as
// the real header does (SGRHeaderInfo.m); each label's text, as drawn, on the other side too; and the back button's
// chevron the left to right one turned around.
// Exits nonzero on the first failure (harness-fail.h).
#import <UIKit/UIKit.h>
#import "../harness-fail.h"
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Redesigned/Kit/SGRAccent.h"
#import "Redesigned/Kit/SGRPagePreview.h"
#import "Redesigned/Kit/SGRHeaderInfo.h"
#import "Redesigned/Playlist/Playlist.h"
#import "Redesigned/Home/Home.h"
#import "Redesigned/Search/Search.h"
#import "Redesigned/Album/Album.h"
#import "Redesigned/Album/AlbumNotes.h"
#import "Redesigned/Artist/Artist.h"

static NSString *outDir;
static UIWindow *window;
static UINavigationController *nav;
static BOOL rtlRun;   // the `rtl` launch

static BOOL readsRightToLeft(UIView *view) {
    return view.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
}

static void spin(NSTimeInterval seconds) {
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

// Every setting of the mod's gone, as on a fresh install, then the shelves Home has seen lately.
static void reset(void) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    for (NSString *key in store.dictionaryRepresentation.allKeys) {
        if ([key hasPrefix:@"spotifyglass."]) [store removeObjectForKey:key];
    }
    NSDate *now = NSDate.date;
    NSArray<NSString *> *seen = @[@"Recents", @"Made For You", @"Jump back in"];
    NSMutableDictionary *table = [NSMutableDictionary dictionary];
    [seen enumerateObjectsUsingBlock:^(NSString *identity, NSUInteger i, BOOL *stop) {
        table[identity] = @{@"first": [now dateByAddingTimeInterval:-86400.0 * (3 - i)], @"last": now};
    }];
    [store setObject:table forKey:SGRKeyHomeShelvesSeen];
    SGPrefsChanged();
}

static SGRPagePreview *cardIn(UIView *view) {
    if ([view isKindOfClass:SGRPagePreview.class]) return (SGRPagePreview *)view;
    for (UIView *sub in view.subviews) {
        SGRPagePreview *card = cardIn(sub);
        if (card) return card;
    }
    return nil;
}

static UITableView *tableOf(UIViewController *page) {
    return ((UITableViewController *)page).tableView;
}

static SGRPagePreview *show(UIViewController *(^builder)(void)) {
    UIViewController *page = builder();
    nav.viewControllers = @[page];
    [nav.view layoutIfNeeded];
    [page.view layoutIfNeeded];
    spin(0.4);
    SGRPagePreview *card = cardIn(tableOf(page).tableHeaderView);
    if (!card) HARNESS_FAIL(@"no preview card on %@", page.title);
    if (card.bounds.size.height < 1) HARNESS_FAIL(@"the card on %@ has no height", page.title);
    if (readsRightToLeft(card) != rtlRun) HARNESS_FAIL(@"the card on %@ reads %@", page.title, rtlRun ? @"left to right" : @"right to left");
    return card;
}

static BOOL animating(UIView *view) {
    if (view.layer.animationKeys.count) return YES;
    for (UIView *sub in view.subviews) if (animating(sub)) return YES;
    return NO;
}

static void writePNG(UIView *view, NSString *name) {
    if (rtlRun) name = [name stringByAppendingString:@"-rtl"];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:view.bounds];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [view drawViewHierarchyInRect:view.bounds afterScreenUpdates:YES];
    }];
    NSString *path = [outDir stringByAppendingPathComponent:[name stringByAppendingString:@".png"]];
    if (![UIImagePNGRepresentation(image) writeToFile:path atomically:YES]) HARNESS_FAIL(@"could not write %@", path);
    printf("wrote %s\n", path.UTF8String);
}

static void expectValue(SGRPagePreview *card, NSString *expected, NSString *state) {
    if (![card.accessibilityValue isEqualToString:expected]) {
        HARNESS_FAIL(@"%@: VoiceOver reads \"%@\", expected \"%@\"", state, card.accessibilityValue, expected);
    }
    printf("PASS %s reads \"%s\"\n", state.UTF8String, expected.UTF8String);
}

// One page: `defaults` and `changed` are what VoiceOver reads off its card before and after `change`.
static void runPage(NSString *name, UIViewController *(^builder)(void), NSString *defaults, void (^change)(void), NSString *changed) {
    reset();
    SGRPagePreview *card = show(builder);
    expectValue(card, defaults, [name stringByAppendingString:@" default"]);
    writePNG(card, [name stringByAppendingString:@"-default"]);
    writePNG(nav.view, [name stringByAppendingString:@"-page"]);

    // Changed on screen: the card moves to it, over the layout motion.
    change();
    spin(0.05);
    if (!animating(card)) HARNESS_FAIL(@"%@: a change in sight drew at once", name);
    printf("PASS %s change in sight animates\n", name.UTF8String);
    spin(1.0);
    expectValue(card, changed, [name stringByAppendingString:@" changed"]);
    writePNG(card, [name stringByAppendingString:@"-changed"]);

    // The defaults again, with the card scrolled out of sight: left undrawn until it is back in sight, then drawn at
    // once. Room under the rows (the page's insets are its own), so a short page scrolls its header away too.
    UITableView *table = tableOf(nav.topViewController);
    table.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1, window.bounds.size.height)];
    [window layoutIfNeeded];
    [table setContentOffset:CGPointMake(0, CGRectGetMaxY(table.tableHeaderView.frame)) animated:NO];
    [window layoutIfNeeded];
    if (CGRectIntersectsRect([card convertRect:card.bounds toView:nil], window.bounds)) {
        HARNESS_FAIL(@"%@: the card did not scroll away (%@ at offset %.0f)", name, NSStringFromCGRect([card convertRect:card.bounds toView:nil]), table.contentOffset.y);
    }
    reset();
    spin(0.05);
    if (animating(card)) HARNESS_FAIL(@"%@: a change out of sight animated", name);
    expectValue(card, changed, [name stringByAppendingString:@" undrawn out of sight"]);
    [table setContentOffset:CGPointMake(0, -table.adjustedContentInset.top) animated:NO];
    [window layoutIfNeeded];
    spin(0.05);
    if (animating(card)) HARNESS_FAIL(@"%@: a change made out of sight animated as the card came back", name);
    expectValue(card, defaults, [name stringByAppendingString:@" back in sight"]);
}

// Home's page color goes with the Top picks cards' colors (HomeTopPicks.x clears both).
static void runHomeTint(void) {
    reset();
    SGRPagePreview *card = show(^UIViewController *{ return SGRHomeSettingsPage(); });
    if (!card.topTint) HARNESS_FAIL(@"home: no page color with the cards' colors on");
    SGSetEnabled(SGRKeyHomeTopPicksColour, NO);
    spin(1.0);
    if (card.topTint) HARNESS_FAIL(@"home: the page color stayed with the cards' colors off");
    printf("PASS home page color goes with the cards' colors\n");
    writePNG(card, @"home-no-colour");
}

// The artist's page takes its field from the photo shown, Apple Music's too (ArtistHeader.x).
static void runArtistField(void) {
    reset();
    SGRPagePreview *card = show(^UIViewController *{ return SGRArtistSettingsPage(); });
    UIColor *spotify = card.fieldColor;
    SGSetEnabled(SGRKeyArtistApplePhoto, YES);
    spin(1.0);
    if ([card.fieldColor isEqual:spotify]) HARNESS_FAIL(@"artist: the field kept Spotify's photo's color under Apple Music's");
    printf("PASS artist field follows the photo\n");
}

static UIView *partNamed(UIView *view, NSString *name) {
    if ([view.accessibilityLabel isEqualToString:name] && ![view isKindOfClass:SGRPagePreview.class]) return view;
    for (UIView *sub in view.subviews) {
        UIView *found = partNamed(sub, name);
        if (found) return found;
    }
    return nil;
}

// One switch for a part below the card's foot: the mock scrolls to it.
static void runReveal(NSString *name, UIViewController *(^builder)(void), void (^change)(void), NSString *part) {
    reset();
    SGRPagePreview *card = show(builder);
    change();
    spin(1.0);
    UIView *view = partNamed(card, part);
    if (!view) HARNESS_FAIL(@"%@: no part named %@ shows", name, part);
    CGFloat top = CGRectGetMinY([view convertRect:view.bounds toView:card]);
    if (top < 0 || top >= card.bounds.size.height) HARNESS_FAIL(@"%@: %@ is out of the card's sight (top at %.0f)", name, part, top);
    printf("PASS %s scrolls to %s\n", name.UTF8String, part.UTF8String);
    writePNG(card, [name stringByAppendingString:@"-revealed"]);
}

// The accent colors, light and dark, picked on the Appearance page while this one is away; and a large text size,
// which the card grows with.
static void runLooks(NSString *name, UIViewController *(^builder)(void)) {
    reset();
    CGFloat height = show(builder).bounds.size.height;
    NSDictionary<NSString *, NSNumber *> *accents = @{@"accent-light": @0xFFD60A, @"accent-dark": @0x2A1B6E};
    for (NSString *accent in accents) {
        reset();
        SGSetInt(SGRKeyAccent, accents[accent].integerValue);
        writePNG(show(builder), [NSString stringWithFormat:@"%@-%@", name, accent]);
    }
    reset();
    window.traitOverrides.preferredContentSizeCategory = UIContentSizeCategoryAccessibilityExtraLarge;
    SGRPagePreview *large = show(builder);
    if (large.bounds.size.height <= height) HARNESS_FAIL(@"%@: the card did not grow with the text (%.0f, %.0f)", name, height, large.bounds.size.height);
    printf("PASS %s card grows with the text (%.0f to %.0f pt)\n", name.UTF8String, height, large.bounds.size.height);
    writePNG(large, [name stringByAppendingString:@"-large-text"]);
    [window.traitOverrides removeTrait:UITraitPreferredContentSizeCategory.class];
}

static UIView *identified(UIView *view, NSString *identifier) {
    if ([view.accessibilityIdentifier isEqual:identifier]) return view;
    for (UIView *child in view.subviews) {
        UIView *found = identified(child, identifier);
        if (found) return found;
    }
    return nil;
}

static BOOL visibleText(UIView *view, NSString *text) {
    if (view.hidden || view.alpha < 0.01) return NO;
    if ([view isKindOfClass:UILabel.class] && [((UILabel *)view).text isEqual:text]) return YES;
    for (UIView *child in view.subviews) if (visibleText(child, text)) return YES;
    return NO;
}

static void runCoverChoices(void) {
    reset();
    for (int album = 0; album < 2; album++) for (int playlist = 0; playlist < 2; playlist++) {
        SGSetInt(SGRKeyAlbumFullCover, album);
        SGSetInt(SGRKeyPlaylistFullCover, playlist);
        for (NSNumber *isAlbum in @[@YES, @NO]) {
            SGRPagePreview *card = show(^UIViewController *{
                return isAlbum.boolValue ? SGRAlbumSettingsPage() : SGRPlaylistSettingsPage();
            });
            UIView *art = identified(card, @"retrine.preview.header.artwork");
            BOOL full = isAlbum.boolValue ? album : playlist;
            if (!art || art.bounds.size.width <= 0) HARNESS_FAIL(@"missing cover preview");
            if (full && CGRectGetMinX(art.frame) != 0) HARNESS_FAIL(@"Full screen cover must reach both edges");
            if (!full && (CGRectGetMinX(art.frame) <= 0 || fabs(art.bounds.size.width - art.bounds.size.height) > 0.5))
                HARNESS_FAIL(@"Card cover must remain an inset square");
            // Change the other page while this card stays visible: no effect on its cover.
            CGRect before = art.frame;
            SGSetInt(isAlbum.boolValue ? SGRKeyPlaylistFullCover : SGRKeyAlbumFullCover, !full);
            spin(0.4);
            if (!CGRectEqualToRect(before, art.frame)) HARNESS_FAIL(@"other page's cover setting leaked");
            SGSetInt(SGRKeyAlbumFullCover, album); SGSetInt(SGRKeyPlaylistFullCover, playlist);
        }
    }
    reset();
    SGRPagePreview *card = show(^UIViewController *{ return SGRAlbumSettingsPage(); });
    if (!visibleText(card, @"Your plays: 12")) HARNESS_FAIL(@"personal counts remain the default");
    SGSetInt(SGRKeyAlbumPlayCountsSource, 1);
    spin(0.4);
    if (!visibleText(card, @"Spotify plays: 12")) HARNESS_FAIL(@"row preview must name Spotify source");
    SGSetInt(SGRKeyAlbumPlayCountsPlace, SGRAlbumPlayCountsInMenu);
    spin(0.4);
    if (!visibleText(card, @"Spotify plays: 12")) HARNESS_FAIL(@"menu preview must name Spotify source");
    SGSetInt(SGRKeyAlbumPlayCountsSource, 0);
    spin(0.4);
    if (!visibleText(card, @"Your plays: 12")) HARNESS_FAIL(@"menu preview must restore personal source");
    printf("PASS four cover combinations and both count sources in row/menu previews\n");
}

#pragma mark - the mirror check

static NSString *const kControlsID = @"retrine.preview.header.controls", *const kBackID = @"retrine.preview.back";
// Drawn at this scale for the ink and the chevron's pixels.
static const CGFloat kDrawScale = 3;
// A label's text drawn right to left sits within this of the left to right one's mirror: the glyphs themselves are
// not mirrored, so their side bearings swap ends.
static const CGFloat kInkTolerance = 1.5;
// Frames are mirrored exactly, give or take rounding.
static const CGFloat kFrameTolerance = 0.01;
// Pixels whose brightness differs by more than this count as unlike. The chevron is the bright pixels on its round
// button: it matches its mirror within the share kChevronMatch of unlike pixels to bright ones, and is unlike itself
// turned around past kChevronAsymmetry.
static const uint8_t kAlphaStep = 64, kBright = 192;
static const double kChevronMatch = 0.05, kChevronAsymmetry = 0.5;

// The brightness of what `draw` draws over black into `size`, `kDrawScale` pixels a point, rows top down.
static NSData *coverage(CGSize size, size_t *columns, void (^draw)(void)) {
    size_t w = (size_t)ceil(size.width * kDrawScale), h = (size_t)ceil(size.height * kDrawScale);
    NSMutableData *data = [NSMutableData dataWithLength:w * h];
    CGColorSpaceRef gray = CGColorSpaceCreateDeviceGray();
    CGContextRef context = CGBitmapContextCreate(data.mutableBytes, w, h, 8, w, gray, (CGBitmapInfo)kCGImageAlphaNone);
    CGColorSpaceRelease(gray);
    if (!context) HARNESS_FAIL(@"no bitmap of %zux%zu", w, h);
    CGContextTranslateCTM(context, 0, h);
    CGContextScaleCTM(context, kDrawScale, -kDrawScale);
    UIGraphicsPushContext(context);
    draw();
    UIGraphicsPopContext();
    CGContextRelease(context);
    *columns = w;
    return data;
}

static CGRect inkOf(UILabel *label, UIView *card) {
    CGSize size = label.bounds.size;
    if (!label.text.length || size.width < 1 || size.height < 1) return CGRectNull;
    size_t w = 0;
    NSData *data = coverage(size, &w, ^{ [label drawTextInRect:label.bounds]; });
    const uint8_t *alpha = data.bytes;
    size_t h = data.length / w, first = SIZE_MAX, last = 0;
    for (size_t y = 0; y < h; y++) for (size_t x = 0; x < w; x++) {
        if (alpha[y * w + x] < kAlphaStep) continue;
        first = MIN(first, x);
        last = MAX(last, x);
    }
    if (first == SIZE_MAX) return CGRectNull;
    CGRect ink = CGRectMake(first / kDrawScale, 0, (last + 1 - first) / kDrawScale, size.height);
    return [label convertRect:ink toView:card];
}

// The views under `view` top down, as the card lays them out, in the card's coordinates; not into a label's or an
// image view's insides. Each: its class (kind), frame, whether it is in the header's controls (fixed), a label's
// text as drawn (ink), and the back button's brightness (pixels, `columns` wide).
static void collect(UIView *view, UIView *card, BOOL fixed, NSMutableArray<NSDictionary *> *into) {
    for (UIView *sub in view.subviews) {
        NSMutableDictionary *placed = [NSMutableDictionary dictionary];
        placed[@"kind"] = NSStringFromClass(sub.class);
        placed[@"frame"] = NSStringFromCGRect([sub convertRect:sub.bounds toView:card]);
        placed[@"fixed"] = @(fixed);
        CGRect ink = [sub isKindOfClass:UILabel.class] ? inkOf((UILabel *)sub, card) : CGRectNull;
        if (!CGRectIsNull(ink)) placed[@"ink"] = NSStringFromCGRect(ink);
        if ([sub.accessibilityIdentifier isEqual:kBackID]) {
            // Drawn with the round button it sits in, as the screen draws it: the image view turns its image on the
            // way to the screen, not in a drawing of its own.
            UIView *button = sub.superview;
            size_t columns = 0;
            placed[@"pixels"] = coverage(button.bounds.size, &columns, ^{ [button drawViewHierarchyInRect:button.bounds afterScreenUpdates:YES]; });
            placed[@"columns"] = @(columns);
        }
        [into addObject:placed];
        if ([sub isKindOfClass:UILabel.class] || [sub isKindOfClass:UIImageView.class]) continue;
        collect(sub, card, fixed || [sub.accessibilityIdentifier isEqual:kControlsID], into);
    }
}

// The pixels unlike between `a` and `b` turned around, as a share of the bright ones in either.
static double unlike(NSData *a, NSData *b, size_t columns) {
    if (a.length != b.length || !columns) return INFINITY;
    const uint8_t *pa = a.bytes, *pb = b.bytes;
    size_t rows = a.length / columns, count = 0, bright = 0;
    for (size_t y = 0; y < rows; y++) for (size_t x = 0; x < columns; x++) {
        int left = pa[y * columns + x], right = pb[y * columns + columns - 1 - x];
        if (abs(left - right) > kAlphaStep) count++;
        if (left >= kBright || right >= kBright) bright++;
    }
    return bright ? (double)count / (double)bright : INFINITY;
}

static BOOL near(CGFloat a, CGFloat b, CGFloat tolerance) {
    return fabs(a - b) <= tolerance;
}

static NSUInteger chevronsChecked;
// The left to right launch's layouts by page, written for the right to left one (UIKit takes a label's natural
// alignment and an image's turn from the app's direction, so a trait override in one launch would not stand in for
// the other).
static NSMutableDictionary<NSString *, NSDictionary *> *layouts;

static NSString *layoutsPath(void) {
    return [outDir stringByAppendingPathComponent:@"mirror-ltr.plist"];
}

// Right to left, `rtl` against the left to right `ltr` of the card `width` wide.
static void compareMirrored(NSString *name, NSArray<NSDictionary *> *ltr, NSArray<NSDictionary *> *rtl, CGFloat width) {
    if (ltr.count != rtl.count) HARNESS_FAIL(@"%@: %lu views left to right, %lu right to left", name, (unsigned long)ltr.count, (unsigned long)rtl.count);
    NSUInteger labels = 0;
    for (NSUInteger i = 0; i < ltr.count; i++) {
        NSDictionary *a = ltr[i], *b = rtl[i];
        NSString *kind = a[@"kind"];
        if (![kind isEqual:b[@"kind"]]) HARNESS_FAIL(@"%@: view %lu is a %@ left to right, a %@ right to left", name, (unsigned long)i, kind, b[@"kind"]);
        CGRect from = CGRectFromString(a[@"frame"]), to = CGRectFromString(b[@"frame"]);
        BOOL fixed = [a[@"fixed"] boolValue];
        CGFloat x = fixed ? from.origin.x : width - CGRectGetMaxX(from);
        if (!near(to.origin.x, x, kFrameTolerance) || !near(to.origin.y, from.origin.y, kFrameTolerance) ||
            !near(to.size.width, from.size.width, kFrameTolerance) || !near(to.size.height, from.size.height, kFrameTolerance)) {
            HARNESS_FAIL(@"%@: %@ %lu at %@ right to left, expected x %.2f (%@ left to right%@)", name, kind, (unsigned long)i,
                         NSStringFromCGRect(to), x, NSStringFromCGRect(from), fixed ? @", kept in place" : @", mirrored");
        }
        if ((a[@"ink"] != nil) != (b[@"ink"] != nil)) HARNESS_FAIL(@"%@: label %lu draws text in one direction only", name, (unsigned long)i);
        if (a[@"ink"]) {
            labels++;
            CGRect inkFrom = CGRectFromString(a[@"ink"]), inkTo = CGRectFromString(b[@"ink"]);
            CGFloat inkX = width - CGRectGetMaxX(inkFrom);
            if (!near(inkTo.origin.x, inkX, kInkTolerance)) {
                HARNESS_FAIL(@"%@: label %lu's text starts at x %.1f right to left, expected %.1f (left to right %@ in %@)", name, (unsigned long)i,
                             inkTo.origin.x, inkX, NSStringFromCGRect(inkFrom), NSStringFromCGRect(from));
            }
        }
        if ((a[@"pixels"] != nil) != (b[@"pixels"] != nil)) HARNESS_FAIL(@"%@: the back chevron is drawn in one direction only", name);
        if (a[@"pixels"]) {
            size_t columns = [a[@"columns"] unsignedLongValue];
            double turned = unlike(b[@"pixels"], a[@"pixels"], columns), asymmetry = unlike(a[@"pixels"], a[@"pixels"], columns);
            if (asymmetry <= kChevronAsymmetry) HARNESS_FAIL(@"%@: the back chevron looks the same turned around (%.3f), so its turn proves nothing", name, asymmetry);
            if (turned > kChevronMatch) HARNESS_FAIL(@"%@: the back chevron right to left is not the left to right one turned around (%.3f unlike)", name, turned);
            printf("PASS %s back chevron turned around (%.3f unlike its mirror, %.3f unlike itself turned)\n", name.UTF8String, turned, asymmetry);
            chevronsChecked++;
        }
    }
    printf("PASS %s mirrors right to left (%lu views, %lu labels' text)\n", name.UTF8String, (unsigned long)ltr.count, (unsigned long)labels);
}

// One page, its settings as `setup` leaves them: left to right its layout is noted, right to left compared with it.
static void runMirror(NSString *name, UIViewController *(^builder)(void), void (^setup)(void)) {
    reset();
    if (setup) setup();
    SGRPagePreview *card = show(builder);
    NSMutableArray<NSDictionary *> *views = [NSMutableArray array];
    collect(card, card, NO, views);
    CGFloat width = card.bounds.size.width;
    if (!rtlRun) {
        layouts[name] = @{@"width": @(width), @"views": views};
        return;
    }
    NSDictionary *ltr = layouts[name];
    if (!ltr) HARNESS_FAIL(@"%@: no left to right layout in %@", name, layoutsPath());
    if ([ltr[@"width"] doubleValue] != width) HARNESS_FAIL(@"%@: the card is %.1f wide right to left, %.1f left to right", name, width, [ltr[@"width"] doubleValue]);
    compareMirrored(name, ltr[@"views"], views, width);
}

static void runMirrors(void) {
    if (rtlRun) {
        layouts = [NSMutableDictionary dictionaryWithContentsOfFile:layoutsPath()];
        if (!layouts) HARNESS_FAIL(@"no left to right layouts at %@: run left to right first", layoutsPath());
    } else {
        layouts = [NSMutableDictionary dictionary];
    }
    runMirror(@"playlist", ^UIViewController *{ return SGRPlaylistSettingsPage(); }, nil);
    runMirror(@"search", ^UIViewController *{ return SGRPagePreviewPage(@"Search", SGRSearchPreview(), SGRestartNote, SGRSearchSections()); }, nil);
    runMirror(@"home", ^UIViewController *{ return SGRHomeSettingsPage(); }, nil);
    runMirror(@"home-plain", ^UIViewController *{ return SGRHomeSettingsPage(); }, ^{ SGSetEnabled(SGRKeyHomeLook, NO); });
    runMirror(@"album", ^UIViewController *{ return SGRAlbumSettingsPage(); }, nil);
    runMirror(@"album-menu", ^UIViewController *{ return SGRAlbumSettingsPage(); }, ^{ SGSetInt(SGRKeyAlbumPlayCountsPlace, SGRAlbumPlayCountsInMenu); });
    runMirror(@"artist", ^UIViewController *{ return SGRArtistSettingsPage(); }, nil);
    if (!rtlRun) {
        if (![layouts writeToFile:layoutsPath() atomically:YES]) HARNESS_FAIL(@"could not write %@", layoutsPath());
        printf("noted the left to right layouts for the mirror check\n");
    } else if (!chevronsChecked) {
        HARNESS_FAIL(@"no back chevron was found to check");
    }
}

static void runChecks(void) {
    reset();
    SGRPagePreview *details = show(^UIViewController *{ return SGRPlaylistSettingsPage(); });
    UIView *controls = identified(details, @"retrine.preview.header.controls");
    if (!controls) HARNESS_FAIL(@"missing playlist preview controls");
    CGFloat full = CGRectGetMinY(controls.frame), headerHeight = controls.superview.bounds.size.height;
    UIView *face = identified(details, @"retrine.preview.header.creatorPicture");
    UIView *name = identified(details, @"retrine.preview.header.detail");
    if (!face || face.hidden || !name || name.hidden) HARNESS_FAIL(@"missing preview creator or picture");
    SGSetEnabled(SGRKeyPlaylistCreatorPicture, NO);
    spin(0.5);
    CGFloat noPicture = CGRectGetMinY(controls.frame);
    if (!face.hidden || name.hidden || noPicture != full)
        HARNESS_FAIL(@"hiding the picture must preserve the name and controls position");
    writePNG(details, @"playlist-picture-off");
    SGSetEnabled(SGRKeyPlaylistCreatorLine, NO);
    SGSetEnabled(SGRKeyPlaylistCreatorPicture, YES);
    spin(0.5);
    CGFloat noLine = CGRectGetMinY(controls.frame);
    if (noLine >= noPicture) HARNESS_FAIL(@"hiding creator and length left the controls in place");
    writePNG(details, @"playlist-line-off");
    SGSetEnabled(SGRKeyPlaylistCreatorLine, YES);
    SGSetEnabled(SGRKeyPlaylistDescription, NO);
    spin(0.5);
    if (CGRectGetMinY(controls.frame) != full || controls.superview.bounds.size.height >= headerHeight)
        HARNESS_FAIL(@"description must close below controls independently");
    writePNG(details, @"playlist-description-off");
    SGSetEnabled(SGRKeyPlaylistCreatorLine, NO);
    SGSetEnabled(SGRKeyPlaylistCreatorPicture, NO);
    spin(0.5);
    if (CGRectGetMinY(controls.frame) != noLine || CGRectGetMaxY(controls.frame) != controls.superview.bounds.size.height)
        HARNESS_FAIL(@"all off must leave no metadata space");
    writePNG(details, @"playlist-all-off");
    runCoverChoices();
    runPage(@"playlist", ^UIViewController *{ return SGRPlaylistSettingsPage(); },
            @"Open cover on tap and Sort and Mix",
            ^{
                SGSetEnabled(SGRKeyPlaylistCoverViewer, NO);
                SGSetEnabled(SGRKeyPlaylistHideCuration, NO);
                SGSetEnabled(SGRKeyPlaylistMenuSortMix, NO);
            }, @"Curation pills");

    runPage(@"search", ^UIViewController *{ return SGRPagePreviewPage(@"Search", SGRSearchPreview(), SGRestartNote, SGRSearchSections()); },
            @"Tinted glass",
            ^{
                SGSetEnabled(SGRKeySearchHideWatchFeeds, NO);
                SGSetEnabled(SGRKeySearchHideOther, NO);
                SGSetEnabled(SGRKeySearchGlassCards, NO);
            }, @"Everything else, Video carousels, and Category cards");

    runPage(@"home", ^UIViewController *{ return SGRHomeSettingsPage(); },
            @"Home look, Top picks, Shortcuts, DJ, Made For You, and Jump back in",
            ^{
                SGSetEnabled(SGRKeyHomeTopPicksHeading, YES);
                SGSetEnabled(SGRKeyHomeKeepTitle, YES);
                SGSetEnabled(SGRKeyHomeHideDJ, YES);
                SGSetEnabled(SGRKeyHomeSongSuggestions, YES);
                SGSetEnabled(SGRKeyHomePreviews, YES);
                SGSetEnabled(SGRHomeShelfHideKey(@"Made For You"), YES);
                [NSUserDefaults.standardUserDefaults setObject:@"Jump back in" forKey:SGRKeyHomeTopPicksFrom];
            }, @"Home look and Title stays on scroll, Top picks, Shortcuts, Song suggestions, Video and playlist previews, and Recents");
    // Without the Home look: no Top picks, Spotify's tiles and title, the first shelf back in its place.
    runPage(@"home-plain", ^UIViewController *{ return SGRHomeSettingsPage(); },
            @"Home look, Top picks, Shortcuts, DJ, Made For You, and Jump back in",
            ^{ SGSetEnabled(SGRKeyHomeLook, NO); },
            @"Shortcuts, DJ, Recents, Made For You, and Jump back in");

    runPage(@"album", ^UIViewController *{ return SGRAlbumSettingsPage(); },
            @"Animated covers, Play counts, and Album notes",
            ^{
                SGSetEnabled(SGRKeyAlbumMotion, NO);
                SGSetInt(SGRKeyAlbumNotesPlace, SGRAlbumNotesUnderPlay);
                SGSetInt(SGRKeyAlbumPlayCountsPlace, SGRAlbumPlayCountsInMenu);
                SGSetEnabled(SGRKeyAlbumHideTrackArtists, NO);
                SGSetEnabled(SGRKeyAlbumHideMoreBy, NO);
                SGSetEnabled(SGRKeyAlbumHideVideos, NO);
            }, @"Album notes, More by the artist, Related music videos, and Play counts");

    runPage(@"artist", ^UIViewController *{ return SGRArtistSettingsPage(); },
            @"Artist logos and Animated artist artwork, Release countdown, Artist pick, and About",
            ^{
                SGSetEnabled(SGRKeyArtistLogo, NO);
                SGSetEnabled(SGRKeyArtistMotion, NO);
                SGSetEnabled(SGRKeyArtistApplePhoto, YES);
                SGSetEnabled(SGRKeyArtistHideVideos, NO);
                SGSetEnabled(SGRKeyArtistHideTabs, NO);
                SGSetEnabled(SGRKeyArtistHidePick, YES);
                SGSetEnabled(SGRKeyArtistHideCountdown, YES);
            }, @"Apple Music artist photo, Music, Video and Merch tabs, Videos, and About");

    runHomeTint();
    runArtistField();
    runReveal(@"home",^UIViewController *{ return SGRHomeSettingsPage(); }, ^{ SGSetEnabled(SGRKeyHomePreviews, YES); },
              @"Video and playlist previews");
    runReveal(@"album", ^UIViewController *{ return SGRAlbumSettingsPage(); }, ^{ SGSetEnabled(SGRKeyAlbumHideMerch, NO); }, @"Merch");
    runReveal(@"artist", ^UIViewController *{ return SGRArtistSettingsPage(); }, ^{ SGSetEnabled(SGRKeyArtistHideVideos, NO); }, @"Videos");

    runLooks(@"playlist", ^UIViewController *{ return SGRPlaylistSettingsPage(); });
    runLooks(@"search", ^UIViewController *{ return SGRPagePreviewPage(@"Search", SGRSearchPreview(), SGRestartNote, SGRSearchSections()); });
    runLooks(@"home", ^UIViewController *{ return SGRHomeSettingsPage(); });
    runLooks(@"album", ^UIViewController *{ return SGRAlbumSettingsPage(); });
    runLooks(@"artist", ^UIViewController *{ return SGRArtistSettingsPage(); });
    runMirrors();

    [NSUserDefaults.standardUserDefaults removePersistentDomainForName:NSBundle.mainBundle.bundleIdentifier];
    printf("page previews: all checks passed\n");
    fflush(stdout);
    exit(0);
}

@interface HarnessApp : UIResponder <UIApplicationDelegate>
@end

@implementation HarnessApp
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        fputs("[harness] FAIL the checks timed out\n", stderr);
        exit(1);
    });
    return YES;
}
@end

@interface HarnessScene : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation HarnessScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    window = [[UIWindow alloc] initWithWindowScene:windowScene];
    window.frame = windowScene.coordinateSpace.bounds;
    window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    nav = [UINavigationController new];
    window.rootViewController = nav;
    [window makeKeyAndVisible];
    self.window = window;
    // From a timer, not the main queue: the checks spin the run loop, and the main queue runs none of the cards'
    // blocks while one of its own is running.
    [NSTimer scheduledTimerWithTimeInterval:0 repeats:NO block:^(NSTimer *timer) { runChecks(); }];
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        outDir = [NSString stringWithUTF8String:getenv("PAGE_PREVIEWS_PNG") ?: "png"];
        rtlRun = [NSProcessInfo.processInfo.arguments containsObject:@"rtl"];
        [NSFileManager.defaultManager createDirectoryAtPath:outDir withIntermediateDirectories:YES attributes:nil error:NULL];
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(HarnessApp.class));
    }
}

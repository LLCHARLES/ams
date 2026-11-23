// Only the settings framework's storage containers are mocked; both row builders are production.
#import "tests.h"
#import "Settings/SGModPage.h"
#import "Shared/LyricsPiP/LyricsPiP.h"
#import "Shared/LyricsBackground/LyricsBackground.h"
#import "Shared/LyricsPiP/LyricsPiPStyle.h"
#import "Shared/LyricsPiP/LyricsPiPFrame.h"
#import "Shared/Fonts/Fonts.h"
#import "Shared/Fonts/FontLibrary.h"
@implementation SGPage
@end
@implementation SGModRow
@end
@implementation SGModSection
@end
@implementation SGModPage
- (instancetype)initWithTitle:(NSString *)title intro:(NSString *)intro sections:(NSArray *)sections footer:(NSString *)footer {
    if ((self = [super init])) { self.title = title; _sections = sections; }
    return self;
}
- (void)refreshVisibility {}
- (void)revealRowTitled:(NSString *)title {}
@end
SGModRow *SGPageRow(NSString *title, UIViewController *(^page)(void)) {
    SGModRow *row = [SGModRow new]; row.title = title; row.page = page; return row;
}
SGModRow *SGOptionRow(NSString *title, NSString *subtitle, NSString *key) {
    SGModRow *row = [SGModRow new]; row.title = title; row.subtitle = subtitle; row.key = key; return row;
}
SGModSection *SGSection(NSString *title, NSArray *rows) {
    SGModSection *section = [SGModSection new]; section.title = title; section.rows = rows; return section;
}
SGModRow *SGChoiceRow(NSString *title, NSString *subtitle, NSString *key, NSArray *choices, NSInteger fallback) {
    SGModRow *row = SGOptionRow(title, subtitle, key); row.menu = choices; return row;
}
SGModRow *SGSliderRow(NSString *title, NSString *subtitle, double min, double max, double step,
    double (^get)(void), void (^set)(double), NSString *(^format)(double)) {
    SGModRow *row = [SGModRow new]; row.title = title; row.subtitle = subtitle;
    row.minimum = min; row.maximum = max; row.step = step; row.number = get; row.setNumber = set; row.format = format; return row;
}
SGModRow *SGStatActionRow(NSString *title, NSString *subtitle, NSString *(^value)(void), void (^action)(void)) {
    SGModRow *row = [SGModRow new]; row.title = title; row.subtitle = subtitle; row.value = value; row.action = action; return row;
}
SGModRow *SGMenuRow(NSString *title, NSArray<NSString *> *choices, NSString *(^value)(void), void (^chosen)(NSInteger index)) {
    SGModRow *row = [SGModRow new]; row.title = title; row.menu = choices; row.value = value; row.chosen = chosen; return row;
}
void SGPickColor(NSString *title, NSInteger initial, void (^picked)(NSInteger)) { picked(0x123456); }
UIColor *SGColorRGB(NSInteger rgb) { return UIColor.blackColor; }

// The preview is found the way VoiceOver finds it, by its label, and compared by decoded pixels with an
// independently built sample drawn by the production renderer.
static UIImageView *findPreview(UIView *view) {
    if ([view isKindOfClass:UIImageView.class] && [view.accessibilityLabel hasPrefix:@"Sample preview"]) return (id)view;
    for (UIView *sub in view.subviews) { UIImageView *found = findPreview(sub); if (found) return found; }
    return nil;
}
static UIImageView *previewIn(UIViewController *controller, CGSize size) {
    controller.overrideUserInterfaceStyle = UIUserInterfaceStyleDark; // as SGPage does
    controller.view.frame = (CGRect){CGPointZero, size};
    [controller viewWillAppear:NO]; // a page draws its preview only while it is the one shown
    [controller.view setNeedsLayout];
    [controller.view layoutIfNeeded];
    return findPreview(controller.view);
}
// The pixels in one fixed format, so a bitmap handed over directly and a decoded PNG compare equal.
static NSData *pixels(UIImage *image) {
    CGImageRef cg = image.CGImage;
    if (!cg) return nil;
    size_t width = CGImageGetWidth(cg), height = CGImageGetHeight(cg);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, width * 4, space,
        kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(space);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), cg);
    NSData *data = [NSData dataWithBytes:CGBitmapContextGetData(context) length:width * 4 * height];
    CGContextRelease(context);
    return data;
}
// The preview queue is the page's own; holding it keeps submitted renders waiting until the gate is signalled.
extern dispatch_queue_t SGLyricsPiPPreviewQueue(void);
static dispatch_semaphore_t holdPreviewQueue(void) {
    dispatch_semaphore_t gate = dispatch_semaphore_create(0);
    dispatch_async(SGLyricsPiPPreviewQueue(), ^{ dispatch_semaphore_wait(gate, DISPATCH_TIME_FOREVER); });
    return gate;
}
// Returns once everything already submitted to main has run, including the second hop a change takes.
static void drainMain(void) {
    __block BOOL done = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ dispatch_async(dispatch_get_main_queue(), ^{ done = YES; }); });
    SGTestAssert(SGTestPump(^BOOL { return done; }), @"main queue drains");
}
// A size change as the page sees it: stored, announced, and the page's update run.
static void changeSize(SGModPage *page, double value) {
    page.sections[0].rows[0].setNumber(value);
    [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:NSUserDefaults.standardUserDefaults];
    drainMain();
}
// Every submitted render has finished and its result, if any, has reached main.
static void settle(void) {
    dispatch_sync(SGLyricsPiPPreviewQueue(), ^{});
    drainMain();
}
// Counts the images a preview is given, to see how many renders of a burst were shown.
@interface SGImageCounter : NSObject
@property (nonatomic) NSUInteger images;
@end
@implementation SGImageCounter
- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (change[NSKeyValueChangeNewKey] != NSNull.null) self.images++;
}
@end
static NSArray *sample(BOOL pronunciation, BOOL translation) {
    return @[@"별빛을 따라 걸어요", @"A new day is on its way", @"Sample lyrics · Retrine",
        pronunciation ? @"Byeolbicheul ttara georeoyo" : @"", translation ? @"We walk beneath the stars" : @"",
        @"A song for the night", @"Retrine"];
}
static BOOL shows(UIImageView *preview, NSArray *content) {
    NSData *got = pixels(preview.image);
    return got && [got isEqual:pixels([UIImage imageWithData:SGLyricsPiPFramePNG(content)])];
}
static BOOL same(id a, id b) { return a == b || [a isEqual:b]; }
static UILabel *labelIn(UIView *view) {
    for (UIView *sub in view.subviews) if ([sub isKindOfClass:UILabel.class]) return (id)sub;
    return nil;
}
static BOOL unclipped(UILabel *label, UIView *in) {
    CGFloat needed = ceil([label sizeThatFits:CGSizeMake(label.bounds.size.width, CGFLOAT_MAX)].height);
    return label.text.length && label.bounds.size.height >= needed && CGRectContainsRect(in.bounds, label.frame);
}
// Small phones both ways, a common size and an extreme short window, at the default and the largest accessibility
// text size: the whole pinned header stays within 42% of the visible room and at the top of it while the rows scroll;
// its caption is never clipped, and whatever does not fit pinned (the caption, the hidden-line explanation) is an
// unclipped, accessible note at the top of the scrolling content.
static void pinnedLayout(UIViewController *controller, UIImageView *preview, NSString *name, NSString *explanation) {
    UITableView *table = ((UITableViewController *)controller).tableView;
    BOOL moved = NO;
    for (UIContentSizeCategory category in @[UIContentSizeCategoryLarge, UIContentSizeCategoryAccessibilityExtraExtraExtraLarge])
    for (NSValue *value in @[[NSValue valueWithCGSize:CGSizeMake(568, 320)], [NSValue valueWithCGSize:CGSizeMake(320, 568)],
            [NSValue valueWithCGSize:CGSizeMake(667, 375)], [NSValue valueWithCGSize:CGSizeMake(390, 844)],
            [NSValue valueWithCGSize:CGSizeMake(568, 160)]]) {
        CGSize size = value.CGSizeValue;
        NSString *where = [NSString stringWithFormat:@"%@ page at %.0f×%.0f, %@", name, size.width, size.height, category];
        controller.traitOverrides.preferredContentSizeCategory = category;
        previewIn(controller, size);
        table.contentOffset = CGPointMake(0, -table.adjustedContentInset.top);
        [controller.view layoutIfNeeded];
        UIView *header = preview.superview, *noteView = table.tableHeaderView;
        UILabel *caption = labelIn(header), *note = labelIn(noteView);
        CGFloat visible = size.height - table.safeAreaInsets.top - table.safeAreaInsets.bottom - table.contentInset.bottom;
        BOOL captioned = !caption.hidden;
        moved |= !captioned;
        SGTestAssert(caption.font.pointSize == [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1
            compatibleWithTraitCollection:[UITraitCollection traitCollectionWithPreferredContentSizeCategory:category]].pointSize,
            [@"caption follows the page's text size: " stringByAppendingString:where]);
        SGTestAssert(header.bounds.size.height <= floor(visible * .42) && table.contentInset.top == header.bounds.size.height &&
            CGRectContainsRect(header.bounds, preview.frame) && (!captioned || unclipped(caption, header)),
            [@"whole pinned header, caption included, stays within its share and unclipped: " stringByAppendingString:where]);
        SGTestAssert([preview.accessibilityLabel isEqual:@"Sample preview"] &&
            (captioned ? [caption.text isEqual:@"Sample preview"] : [note.text hasPrefix:@"Sample preview"]),
            [@"the sample stays labeled, pinned or in the note: " stringByAppendingString:where]);
        BOOL wantNote = !captioned || explanation;
        SGTestAssert(wantNote ? noteView != header && noteView.superview == table && unclipped(note, noteView) &&
                !note.accessibilityElementsHidden && (!explanation || [note.text hasSuffix:explanation]) &&
                fabs(CGRectGetMinY(noteView.frame) - table.contentOffset.y - table.adjustedContentInset.top) < .5 :
                noteView == nil,
            [@"explanations scroll as an unclipped accessible note right under the preview: " stringByAppendingString:where]);
        table.contentOffset = CGPointMake(0, 240 - table.adjustedContentInset.top);
        [controller.view layoutIfNeeded];
        SGTestAssert(header.superview == table && fabs(CGRectGetMinY(header.frame) - table.contentOffset.y - table.safeAreaInsets.top) < .5,
            [@"preview stays pinned above scrolled rows: " stringByAppendingString:where]);
    }
    SGTestAssert(moved, [name stringByAppendingString:@" page's caption moves into the note where the pinned share cannot hold it"]);
    controller.traitOverrides.preferredContentSizeCategory = UIContentSizeCategoryLarge;
    previewIn(controller, CGSizeMake(390, 844));
}

void SGTestSettings(void) {
    SGModRow *link = SGLyricsPiPRow();
    SGTestAssert(link.page && !link.key && [link.subtitle isEqual:@"Open lyrics over other apps and customize their background."],
        @"existing settings-row API now returns discoverable page link");
    SGModPage *page = (id)link.page();
    SGModRow *toggle = page.sections[0].rows[0];
    SGTestAssert([toggle.key isEqual:SGKeyLyricsPiP] && [toggle.subtitle containsString:@"Restart Spotify"],
        @"page preserves opt-in toggle and existing restart explanation");
    SGTestAssert(page.sections.count == 4 && [page.sections[1].title isEqual:@"Layout"] &&
        [page.sections[2].title isEqual:@"Text"] && [page.sections[3].title isEqual:@"Background"],
        @"native page groups layout, text and background");
    SGTestAssert(page.sections[1].rows[0].menu.count == 3 && page.sections[1].rows[1].defaultOn,
        @"aspect choices and default-on metadata control are discoverable");
    SGModPage *role = (id)page.sections[2].rows[2].page();
    SGTestAssert(role.sections[0].rows[0].minimum == 24 && role.sections[0].rows[0].maximum == 64 &&
        role.sections[0].rows[1].menu.count == 4 && [role.sections[0].rows[1].value() isEqual:@"Semibold"],
        @"original settings use bounded role-specific controls with an on-page weight menu");
    role = (id)page.sections[2].rows[3].page();
    SGTestAssert(role.sections[0].rows[0].minimum == 16 && role.sections[0].rows[0].maximum == 48,
        @"secondary role settings have smaller bounded range");
    NSArray<SGModRow *> *rows = page.sections[3].rows;
    SGTestAssert(rows.count == 4 && [rows[0].key isEqual:@"spotifyglass.lyrics.pip.background.mode"] && rows[0].menu.count == 5,
        @"page reuses all five shared background choices under PiP prefix");
    SGTestAssert(rows[1].minimum == 0 && rows[1].maximum == 85 && rows[2].minimum == 0 && rows[2].maximum == 100,
        @"darkness and blur expose exact slider ranges");
    // Restore the persistent harness domain after exercising the actual setters.
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *darkness = @"spotifyglass.lyrics.pip.background.darkness", *blur = @"spotifyglass.lyrics.pip.background.blur";
    NSString *color = @"spotifyglass.lyrics.pip.background.color";
    NSString *domain = NSProcessInfo.processInfo.processName;
    NSDictionary *saved = [defaults persistentDomainForName:domain] ?: @{};
    SGTestSetting(darkness, nil);
    rows[1].setNumber(33);
    rows[2].setNumber(12);
    rows[3].action();
    SGTestAssert(rows[1].number() == 33 && rows[2].number() == 12 && SGLyricsBackgroundRead(@"spotifyglass.lyrics.pip.background").color == 0x123456
        && SGLyricsBackgroundRead(@"spotifyglass.lockscreen.background").darkness == .8,
        @"production slider/color writes never change lockscreen preferences");
    id appFont = [defaults objectForKey:SGKeyAppFont] ?: @0;
    // The lyrics screen's switches, as the user left them there: both off, in the volatile test domain.
    NSString *pronunciationKey = @"spotifyglass.redesign.lyricsPronunciation", *translationKey = @"spotifyglass.redesign.lyricsTranslation";
    SGTestSetting(pronunciationKey, @NO);
    SGTestSetting(translationKey, @NO);
    extern int SGTestFontAsks;
    int asksBefore = SGTestFontAsks;
    SGModPage *fonts = (id)page.sections[2].rows[1].page();
    SGTestAssert(SGTestFontAsks == asksBefore + 2, @"opening the font page asks for the downloaded and the imported families");
    UIImageView *fontPreview = previewIn(fonts, CGSizeMake(667, 375));
    SGTestAssert(fontPreview && SGTestPump(^BOOL { return shows(fontPreview, sample(NO, NO)); }) && [fontPreview.accessibilityLabel isEqual:@"Sample preview"] &&
        [fontPreview.accessibilityValue containsString:@"별빛을 따라 걸어요"] && ![fontPreview.accessibilityValue containsString:@"Byeolbicheul"] &&
        ![fontPreview.accessibilityValue containsString:@"beneath"], @"font page shows a labeled production sample without switched-off supplements");
    pinnedLayout(fonts, fontPreview, @"font", nil);
    NSData *before = pixels(fontPreview.image);
    for (SGModRow *choice in fonts.sections[0].rows) if ([choice.title isEqual:@"Georgia"]) choice.action();
    SGTestAssert([SGLyricsPiPReadStyle().font isEqual:@"Georgia"] &&
        [appFont isEqual:[defaults objectForKey:SGKeyAppFont] ?: @0], @"PiP font picker changes only the PiP font");
    SGTestAssert(SGTestPump(^BOOL { return shows(fontPreview, sample(NO, NO)); }) && ![pixels(fontPreview.image) isEqual:before],
        @"choosing a family redraws the pinned preview at once");
    SGTestSetting(translationKey, @YES);
    [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:defaults];
    SGTestAssert(SGTestPump(^BOOL { return shows(fontPreview, sample(NO, YES)); }) &&
        [fontPreview.accessibilityValue containsString:@"We walk beneath the stars"] && ![fontPreview.accessibilityValue containsString:@"Byeolbicheul"],
        @"switching translation on in lyrics shows only translation in the preview");
    SGModPage *pronunciation = (id)page.sections[2].rows[3].page();
    UIImageView *pronunciationPreview = previewIn(pronunciation, CGSizeMake(320, 568));
    SGModPage *translation = (id)page.sections[2].rows[4].page();
    UIImageView *translationPreview = previewIn(translation, CGSizeMake(320, 568));
    NSString *hiddenNote = @"Pronunciation is off on the lyrics screen, so it is hidden.";
    SGTestAssert(SGTestPump(^BOOL { return shows(pronunciationPreview, sample(NO, YES)) && shows(translationPreview, sample(NO, YES)); }) && [labelIn(pronunciation.tableView.tableHeaderView).text isEqual:hiddenNote] &&
        !translation.tableView.tableHeaderView,
        @"supplement pages say when their line is hidden and stay quiet when it shows");
    pinnedLayout(pronunciation, pronunciationPreview, @"pronunciation", hiddenNote);
    NSDictionary *now = [defaults persistentDomainForName:domain];
    SGTestAssert(same(now[pronunciationKey], saved[pronunciationKey]) && same(now[translationKey], saved[translationKey]),
        @"previews never write the lyrics screen's switches");
    SGModPage *original = (id)page.sections[2].rows[2].page();
    UIImageView *originalPreview = previewIn(original, CGSizeMake(375, 667));
    pinnedLayout(original, originalPreview, @"original", nil);
    original.sections[0].rows[0].setNumber(64);
    SGTestAssert(SGLyricsPiPReadStyle().sizes[0].doubleValue == 64, @"role size setter reaches production style");
    SGTestAssert(SGTestPump(^BOOL { return shows(originalPreview, sample(NO, YES)); }), @"size slider redraws the pinned preview while dragged");
    before = pixels(originalPreview.image);
    original.sections[0].rows[1].chosen(0);
    SGTestAssert(SGLyricsPiPReadStyle().weights[0].integerValue == 0 && [original.sections[0].rows[1].value() isEqual:@"Regular"],
        @"weight menu stores the role weight");
    SGTestAssert(SGTestPump(^BOOL { return shows(originalPreview, sample(NO, YES)); }) && ![pixels(originalPreview.image) isEqual:before],
        @"weight menu redraws the pinned preview");
    // A page under another one (the parent while a child is pushed) draws nothing, and draws the current
    // settings when it is shown again.
    NSData *shown = pixels(originalPreview.image);
    [original viewWillDisappear:NO];
    changeSize(original, 30);
    settle();
    SGTestAssert([pixels(originalPreview.image) isEqual:shown], @"a page that is not shown renders no preview");
    [original viewWillAppear:NO];
    SGTestAssert(SGTestPump(^BOOL { return shows(originalPreview, sample(NO, YES)); }) && ![pixels(originalPreview.image) isEqual:shown],
        @"a page shown again draws the settings changed meanwhile");
    // A render already queued when the page is covered is dropped, not published under the page that covers it.
    shown = pixels(originalPreview.image);
    dispatch_semaphore_t gate = holdPreviewQueue();
    changeSize(original, 35);
    [original viewWillDisappear:NO];
    dispatch_semaphore_signal(gate);
    settle();
    SGTestAssert([pixels(originalPreview.image) isEqual:shown], @"a render queued before the page was covered is not shown");
    [original viewWillAppear:NO];
    SGTestAssert(SGTestPump(^BOOL { return shows(originalPreview, sample(NO, YES)); }) && ![pixels(originalPreview.image) isEqual:shown],
        @"returning to the page draws the current settings");
    // A dragged slider: 40 requests queue up behind a held render; only the newest is drawn and shown.
    SGImageCounter *counter = [SGImageCounter new];
    [originalPreview addObserver:counter forKeyPath:@"image" options:NSKeyValueObservingOptionNew context:NULL];
    gate = holdPreviewQueue();
    for (NSUInteger step = 0; step < 40; step++) changeSize(original, 24 + step);
    dispatch_semaphore_signal(gate);
    settle();
    [originalPreview removeObserver:counter forKeyPath:@"image"];
    SGTestAssert(SGLyricsPiPReadStyle().sizes[0].doubleValue == 63 && shows(originalPreview, sample(NO, YES)),
        @"after a drag the preview matches the size where it stopped");
    SGTestAssert(counter.images == 1, @"a drag shows only the newest render, not one per step");
    original.sections[0].rows[0].setNumber(64);
    originalPreview.image = nil;
    [NSNotificationCenter.defaultCenter postNotificationName:SGFontLibraryChangedNotification object:nil];
    SGTestAssert(SGTestPump(^BOOL { return shows(originalPreview, sample(NO, YES)); }), @"font library changes redraw the preview");
    UIImageView *mainPreview = previewIn(page, CGSizeMake(375, 667));
    SGTestAssert(mainPreview.superview == page.tableView.tableHeaderView && SGTestPump(^BOOL { return shows(mainPreview, sample(NO, YES)); }),
        @"main page keeps its scrolling sample header with the same supplement rule");
    [defaults setBool:YES forKey:pronunciationKey]; // a stored lyrics-screen choice the reset must keep
    page.sections[2].rows[5].action();
    SGTestAssert(SGLyricsPiPReadStyle().sizes[0].doubleValue == 40 && SGLyricsPiPReadStyle().weights[0].integerValue == 2 &&
        ![defaults objectForKey:SGKeyPiPFont] && rows[1].number() == 33 && [[defaults persistentDomainForName:domain][pronunciationKey] boolValue],
        @"reset restores layout/text defaults without changing background or lyrics switches");
    SGTestAssert(SGTestPump(^BOOL { return shows(mainPreview, sample(NO, YES)) && shows(originalPreview, sample(NO, YES)); }),
        @"reset redraws open previews with the default style");
    [defaults setPersistentDomain:saved forName:domain];
    // These keys were created only by this host test when Foundation uses its executable domain.
    for (NSString *key in @[darkness, blur, color, SGKeyPiPFont, SGLyricsPiPRoleKey(0, @"size"), SGLyricsPiPRoleKey(0, @"weight"),
            pronunciationKey])
        if (!saved[key]) [defaults removeObjectForKey:key]; else [defaults setObject:saved[key] forKey:key];
    SGTestSetting(pronunciationKey, nil);
    SGTestSetting(translationKey, nil);
    SGTestSetting(darkness, @45);
    SGTestSetting(@"spotifyglass.lyrics.pip.background.mode", @2);
    SGTestAssert(rows[2].visible() && !rows[3].visible(), @"blur control shown only in blur mode");
    SGTestSetting(@"spotifyglass.lyrics.pip.background.mode", @4);
    SGTestAssert(!rows[2].visible() && rows[3].visible(), @"color control shown only in solid mode");
    SGTestSetting(@"spotifyglass.lyrics.pip.background.mode", @0);
}

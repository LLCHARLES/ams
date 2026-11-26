#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "LyricsPiP.h"
#import "LyricsPiPBackground.h"
#import "Shared/LyricsBackground/LyricsBackgroundSettings.h"
#import "LyricsPiPFrame.h"
#import "Shared/Fonts/FontLibrary.h"
#import "Shared/Fonts/Fonts.h"

// The newest preview request of one page. A render running off main reads it to drop itself once a newer
// request exists, so a dragged slider renders only where the finger stopped, not at every step.
@interface SGLyricsPiPPreviewTicket : NSObject
@property (atomic) NSUInteger latest;
@end
@implementation SGLyricsPiPPreviewTicket
@end

// Not static only so the lyrics-pip harness can hold the queue while it submits a burst of requests.
dispatch_queue_t SGLyricsPiPPreviewQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("spotifyglass.lyrics.pip.preview", dispatch_queue_attr_make_with_qos_class(
            DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0));
    });
    return queue;
}

// SGModPage remains the native grouped settings page; its preview is a real CPU-rendered frame from the
// production renderer. The main page carries it as a scrolling header. The font and role pages pin it above
// their rows, so it stays in view while a family, size or weight changes, and cap the whole pinned header so
// the rows keep most of the screen at any text size, even on a small phone held sideways. Explanations scroll
// with the rows, in a note at their top, rather than being shrunk or clipped.
@interface SGLyricsPiPSettingsPage : SGModPage
@property (nonatomic) BOOL pinned;
// 1 or 2 on the pronunciation or translation page: says when that line is hidden by the lyrics screen.
@property (nonatomic) BOOL typography;
@property (nonatomic, strong) UIView *header;
@property (nonatomic, strong) UIImageView *preview;
@property (nonatomic, strong) UILabel *sampleLabel;
@property (nonatomic, strong) UIView *noteView;
@property (nonatomic, strong) UILabel *noteLabel;
@property (nonatomic, copy) NSString *hiddenNote;
@property (nonatomic) CGSize raster;
@property (nonatomic) BOOL refreshQueued;
// A page under another one, or not yet shown, renders nothing; it redraws when it comes back.
@property (nonatomic) BOOL onScreen;
@property (nonatomic) BOOL previewStale;
@property (nonatomic, strong) SGLyricsPiPPreviewTicket *ticket;
@end
@implementation SGLyricsPiPSettingsPage
- (void)viewDidLoad {
    [super viewDidLoad];
    self.preview = [UIImageView new];
    self.preview.contentMode = UIViewContentModeScaleAspectFit;
    self.preview.isAccessibilityElement = YES;
    self.preview.accessibilityTraits = UIAccessibilityTraitImage;
    self.sampleLabel = [UILabel new];
    self.sampleLabel.textColor = UIColor.secondaryLabelColor;
    self.sampleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    self.sampleLabel.adjustsFontForContentSizeCategory = YES;
    self.sampleLabel.numberOfLines = 0;
    self.sampleLabel.textAlignment = NSTextAlignmentCenter;
    self.sampleLabel.accessibilityElementsHidden = YES; // the preview reads the same text out
    self.header = [UIView new];
    [self.header addSubview:self.preview]; [self.header addSubview:self.sampleLabel];
    if (self.pinned) {
        self.header.backgroundColor = self.tableView.backgroundColor; // rows scroll under it
        [self.tableView addSubview:self.header];
        self.noteLabel = [UILabel new];
        self.noteLabel.textColor = UIColor.secondaryLabelColor;
        self.noteLabel.numberOfLines = 0;
        self.noteView = [UIView new];
        [self.noteView addSubview:self.noteLabel];
    } else {
        self.tableView.tableHeaderView = self.header;
    }
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(previewChanged:)
        name:NSUserDefaultsDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(previewChanged:)
        name:SGFontLibraryChangedNotification object:nil];
    self.ticket = [SGLyricsPiPPreviewTicket new];
    [self updatePreview];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.onScreen = YES;
    if (self.previewStale) [self updatePreview];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.onScreen = NO;
    // A render already queued or running is for a page that is no longer shown: drop it, and draw afresh on return.
    self.ticket.latest++;
    self.previewStale = YES;
}
- (void)previewChanged:(NSNotification *)note {
    // Defaults may post off main and several times for one change (a reset removes ten keys): one render per burst.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.refreshQueued) return;
        self.refreshQueued = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.refreshQueued = NO;
            [self updatePreview];
            // A page that is not shown recomputes its rows as it appears. Fonts registering are no switch flipped,
            // so the rows they bring come in without scrolling the page, on SGModPage's own tick.
            if (self.onScreen && ![note.name isEqual:SGFontLibraryChangedNotification]) [self refreshVisibility];
        });
    });
}
- (void)updatePreview {
    // The lyrics screen's effective switches, read exactly as LyricsPiP.m reads them for its frames. Only
    // read: the sample never writes them, and nothing here asks for a translation or pronunciation.
    BOOL pronunciation = SGFlag(@"spotifyglass.redesign.lyricsPronunciation", NO);
    BOOL translation = SGFlag(@"spotifyglass.redesign.lyricsTranslation", NO);
    NSArray<NSString *> *sample = @[SGL(@"settings.lyrics.pip.sample.original", @"별빛을 따라 걸어요"),
        SGL(@"settings.lyrics.pip.sample.next", @"A new day is on its way"),
        SGL(@"settings.lyrics.pip.sample.credit", @"Sample lyrics · Retrine"),
        pronunciation ? @"Byeolbicheul ttara georeoyo" : @"", translation ? @"We walk beneath the stars" : @"",
        SGL(@"settings.lyrics.pip.sample.song", @"A song for the night"), @"Retrine"];
    NSString *label = SGL(@"settings.lyrics.pip.preview", @"Sample preview");
    NSMutableArray *hidden = [NSMutableArray array];
    if (self.typography && !pronunciation) [hidden addObject:SGL(@"settings.lyrics.pip.preview.hidden.pronunciation", @"Pronunciation is off on the lyrics screen, so it is hidden.")];
    if (self.typography && !translation) [hidden addObject:SGL(@"settings.lyrics.pip.preview.hidden.translation", @"Translation is off on the lyrics screen, so it is hidden.")];
    self.sampleLabel.text = label;
    self.hiddenNote = hidden.count ? [hidden componentsJoinedByString:@"\n"] : nil;
    self.preview.accessibilityLabel = label;
    // Read in the order the frame shows them: song, artist, then the lyric lines, the next line and the credit.
    NSMutableArray<NSString *> *spoken = [NSMutableArray array];
    for (NSNumber *slot in @[@5, @6, @0, @3, @4, @1, @2])
        if (sample[slot.unsignedIntegerValue].length) [spoken addObject:sample[slot.unsignedIntegerValue]];
    self.preview.accessibilityValue = [spoken componentsJoinedByString:@", "];
    self.raster = SGLyricsPiPReadStyle().raster;
    [self.view setNeedsLayout];
    self.previewStale = !self.onScreen;
    if (!self.onScreen) return;
    // Everything the render reads is copied here on main; the encode-free bitmap is drawn on the preview
    // queue and only the newest request is shown.
    SGLyricsPiPStyle *style = SGLyricsPiPReadStyle();
    SGLyricsBackgroundStyle background = SGLyricsPiPReadBackground();
    SGLyricsPiPPreviewTicket *ticket = self.ticket;
    NSUInteger request = ++ticket.latest;
    __weak SGLyricsPiPSettingsPage *weakSelf = self;
    dispatch_async(SGLyricsPiPPreviewQueue(), ^{
        if (ticket.latest != request) return;
        CGImageRef frame = SGLyricsPiPCreateStyledImage(sample, style, NULL, background);
        if (!frame) return;
        UIImage *image = [UIImage imageWithCGImage:frame scale:1 orientation:UIImageOrientationUp];
        CGImageRelease(frame);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (ticket.latest == request) weakSelf.preview.image = image;
        });
    });
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UITableView *table = self.tableView;
    CGFloat width = table.bounds.size.width;
    if (!self.header || width <= 0 || self.raster.width <= 0) return;
    CGFloat x = table.layoutMargins.left, inner = MAX(0, width - x - table.layoutMargins.right);
    UIFont *font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1 compatibleWithTraitCollection:self.traitCollection];
    if (![self.sampleLabel.font isEqual:font]) self.sampleLabel.font = font; // scrolling lays out every frame
    CGFloat label = ceil([self.sampleLabel sizeThatFits:CGSizeMake(inner, CGFLOAT_MAX)].height);
    CGFloat image = MIN(220, floor(inner * self.raster.height / self.raster.width));
    if (!self.pinned) {
        CGFloat height = 8 + image + 4 + label + 8;
        self.preview.frame = CGRectMake(x, 8, inner, image);
        self.sampleLabel.frame = CGRectMake(x, 12 + image, inner, label);
        if (self.header.frame.size.height != height || self.header.frame.size.width != width) {
            self.header.frame = CGRectMake(0, 0, width, height);
            table.tableHeaderView = self.header;
        }
        return;
    }
    // The whole pinned header, caption and padding included, takes at most 42% of the room between the bars.
    // A caption that would leave the frame under 48 pt moves into the scrolling note instead; the preview
    // still reads it out. Under any tighter room the frame alone shrinks, to nothing if it must.
    CGFloat visible = table.bounds.size.height - table.safeAreaInsets.top - table.safeAreaInsets.bottom - table.contentInset.bottom;
    CGFloat cap = MAX(0, floor(visible * .42));
    BOOL captioned = cap - label - 20 >= 48;
    image = MAX(0, MIN(image, captioned ? cap - label - 20 : cap - 16));
    CGFloat height = captioned ? image + label + 20 : MIN(cap, image + 16);
    self.preview.frame = CGRectMake(x, 8, inner, image);
    self.sampleLabel.hidden = !captioned;
    self.sampleLabel.frame = CGRectMake(x, 12 + image, inner, captioned ? label : 0);
    NSMutableArray<NSString *> *note = [NSMutableArray array];
    if (!captioned) [note addObject:self.sampleLabel.text];
    if (self.hiddenNote) [note addObject:self.hiddenNote];
    if (!note.count) {
        if (table.tableHeaderView) table.tableHeaderView = nil;
    } else {
        NSString *text = [note componentsJoinedByString:@"\n"];
        if (![self.noteLabel.font isEqual:font]) self.noteLabel.font = font;
        if (![self.noteLabel.text isEqual:text]) self.noteLabel.text = text;
        CGFloat lines = ceil([self.noteLabel sizeThatFits:CGSizeMake(inner, CGFLOAT_MAX)].height);
        self.noteLabel.frame = CGRectMake(x, 8, inner, lines);
        CGSize size = CGSizeMake(width, lines + 16);
        if (table.tableHeaderView != self.noteView || !CGSizeEqualToSize(self.noteView.bounds.size, size)) {
            self.noteView.frame = (CGRect){CGPointZero, size};
            table.tableHeaderView = self.noteView;
        }
    }
    SGPositionPinnedPreview(table, self.header, height);
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
@end

static SGLyricsPiPSettingsPage *previewPage(NSString *title, NSArray<SGModSection *> *sections, NSString *footer, BOOL typography) {
    SGLyricsPiPSettingsPage *page = [[SGLyricsPiPSettingsPage alloc] initWithTitle:title intro:nil sections:sections footer:footer];
    page.pinned = YES;
    page.typography = typography;
    return page;
}

static NSArray *weights(void) {
    return @[SGL(@"settings.lyrics.pip.weight.regular", @"Regular"),
        SGL(@"settings.lyrics.pip.weight.medium", @"Medium"),
        SGL(@"settings.lyrics.pip.weight.semibold", @"Semibold"),
        SGL(@"settings.lyrics.pip.weight.bold", @"Bold")];
}
static SGModRow *fontRow(void) {
    SGModRow *row = SGPageRow(SGL(@"settings.lyrics.pip.font", @"Font"), ^UIViewController *{
        // Opening the page asks for the downloaded and imported families off main; each one's row is on the page
        // from the start but shows (SGModPage's ticker, which runs only while the page does) once it is registered.
        SGFontLibraryRegisterInstalled();
        SGRegisterCustomFontAsync();
        NSMutableArray *rows = [NSMutableArray array];
        for (NSString *identifier in SGLyricsPiPFontCandidates()) {
            SGModRow *choice = SGStatActionRow(SGLyricsPiPFontName(identifier), nil, nil, ^{
                [NSUserDefaults.standardUserDefaults setObject:identifier forKey:SGKeyPiPFont];
            });
            __weak SGModRow *weakChoice = choice;
            choice.visible = ^BOOL {
                BOOL available = SGLyricsPiPFontAvailable(identifier);
                if (available) weakChoice.title = SGLyricsPiPFontName(identifier);   // the imported family's own name
                return available;
            };
            choice.checked = ^BOOL {
                return [[NSUserDefaults.standardUserDefaults stringForKey:SGKeyPiPFont] ?: @"app" isEqual:identifier];
            };
            [rows addObject:choice];
        }
        return previewPage(SGL(@"settings.lyrics.pip.font", @"Font"), @[SGSection(nil, rows)],
            SGL(@"settings.lyrics.pip.font.note", @"Uses installed fonts, including your imported and downloaded families. Add fonts in Appearance → Font. Unavailable fonts fall back to the system font. This does not change the app font."), 0);
    });
    row.value = ^NSString *{
        return SGLyricsPiPFontName([NSUserDefaults.standardUserDefaults stringForKey:SGKeyPiPFont] ?: @"app");
    };
    return row;
}
static SGModSection *roleSection(NSUInteger role, NSString *title) {
        SGModRow *size = SGSliderRow([NSString stringWithFormat:SGL(@"settings.lyrics.pip.role_size", @"%@ size"), title], nil,
            role == 0 ? 24 : 16, role == 0 ? 64 : 48, 1,
            ^double { return SGLyricsPiPReadStyle().sizes[role].doubleValue; },
            ^(double value) { [NSUserDefaults.standardUserDefaults setDouble:value forKey:SGLyricsPiPRoleKey(role, @"size")]; },
            ^NSString *(double value) { return [NSString stringWithFormat:@"%.0f", value]; });
        // Picked on the page itself, not a list pushed over it, so the pinned preview shows each weight.
        SGModRow *weight = SGMenuRow([NSString stringWithFormat:SGL(@"settings.lyrics.pip.role_weight", @"%@ weight"), title], weights(),
            ^NSString *{ return weights()[SGLyricsPiPReadStyle().weights[role].unsignedIntegerValue]; },
            ^(NSInteger index) { [NSUserDefaults.standardUserDefaults setInteger:index forKey:SGLyricsPiPRoleKey(role, @"weight")]; });
        size.searchIdentifier = SGLyricsPiPRoleKey(role, @"size");
        weight.searchIdentifier = SGLyricsPiPRoleKey(role, @"weight");
        return SGSection(title, @[size, weight]);
}

SGModRow *SGLyricsPiPRow(void) {
    SGModRow *row = SGPageRow(SGL(@"settings.lyrics.pip.title", @"Picture in Picture lyrics"), ^UIViewController *{
        SGModRow *enabled = SGOptionRow(SGL(@"settings.lyrics.pip.title", @"Picture in Picture lyrics"),
            SGL(@"settings.lyrics.pip.subtitle", @"Show lyrics over other apps from the lyrics screen. Restart Spotify after changing this."),
            SGKeyLyricsPiP);
        SGModRow *aspect = SGChoiceRow(SGL(@"settings.lyrics.pip.aspect", @"Aspect ratio"), nil, SGKeyPiPLayout,
            @[SGL(@"settings.lyrics.pip.square", @"Square"), SGL(@"settings.lyrics.pip.landscape", @"Landscape"),
              SGL(@"settings.lyrics.pip.portrait", @"Portrait")], 0);
        SGModRow *info = SGOptionRow(SGL(@"settings.lyrics.pip.info", @"Cover and song info"), nil, SGKeyPiPInfo);
        info.defaultOn = YES;
        NSString *typeTitle = SGL(@"settings.lyrics.pip.typography", @"Text sizes & weights");
        SGModRow *type = SGPageRow(typeTitle, ^UIViewController *{
            return previewPage(typeTitle, @[
                roleSection(0, SGL(@"settings.lyrics.pip.original", @"Original")),
                roleSection(1, SGL(@"settings.lyrics.pip.pronunciation", @"Pronunciation")),
                roleSection(2, SGL(@"settings.lyrics.pip.translation", @"Translation"))],
                SGL(@"settings.lyrics.pip.fit.note", @"Sizes are maximums in the rendered frame. Long text wraps and shrinks to fit; an ellipsis marks text that still cannot fit."), YES);
        });
        type.searchIdentifier = @"page.pip.typography";
        SGModRow *alignment = SGChoiceRow(SGL(@"settings.lyrics.pip.alignment", @"Text alignment"), nil, SGKeyPiPAlignment,
            @[SGL(@"settings.lyrics.pip.left", @"Left"), SGL(@"settings.lyrics.pip.center", @"Center"),
              SGL(@"settings.lyrics.pip.right", @"Right")], 1);
        SGModRow *reset = SGStatActionRow(SGL(@"settings.lyrics.pip.reset", @"Reset layout and text"),
            SGL(@"settings.lyrics.pip.reset.note", @"Background and the enable switch are kept."), nil, ^{ SGLyricsPiPResetStyle(); });
        return [[SGLyricsPiPSettingsPage alloc] initWithTitle:SGL(@"settings.lyrics.pip.title", @"Picture in Picture lyrics")
            intro:SGL(@"settings.lyrics.pip.live", @"Layout, text and background apply live, even while paused. Only the enable switch requires restarting Spotify.")
            sections:@[SGSection(nil, @[enabled]),
                SGSection(SGL(@"settings.lyrics.pip.layout", @"Layout"), @[aspect, info]),
                SGSection(SGL(@"settings.lyrics.pip.text", @"Text"), @[alignment, fontRow(), type, reset]),
                SGSection(SGL(@"settings.lyrics.pip.background", @"Background"), SGLyricsBackgroundRows(SGKeyLyricsPiPBackground))]
            footer:SGL(@"settings.lyrics.pip.extras.note", @"Shows available pronunciation and translation using your lyrics display and language rules. Opening Picture in Picture never starts translation or AI.")];
    });
    row.subtitle = SGL(@"settings.lyrics.pip.page.subtitle", @"Open lyrics over other apps and customize their background.");
    return row;
}

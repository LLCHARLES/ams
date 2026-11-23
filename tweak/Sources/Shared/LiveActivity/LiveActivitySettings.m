// The Live Activity page (App/ModSettings.x links it from the root, under either look): the preview at its top
// (SGLiveActivityPreview.m), then the switch, the view and the card's options, which the tick reads, so they
// apply at once to a card that is showing.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "LiveActivity.h"
#import "SGLiveActivityPreview.h"

static NSArray<NSString *> *viewNames(void) {
    return @[SGL(@"settings.liveactivity.shows.choice.lyrics", @"Lyrics"), SGL(@"settings.liveactivity.shows.choice.queue", @"Queue"), SGL(@"settings.liveactivity.shows.choice.controlmenu", @"Control menu")];
}

@interface SGLiveActivityPage : SGModPage
@property (nonatomic, strong) SGLiveActivityPreview *preview;
@end

@implementation SGLiveActivityPage

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.tableHeaderView = self.preview;
}

// Handed back to the table only when its size changes (SGFitNote's way: the table lays out again on every handing back).
- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    UITableView *table = self.tableView;
    CGFloat width = table.bounds.size.width;
    self.preview.layoutMargins = UIEdgeInsetsMake(0, table.layoutMargins.left, 0, table.layoutMargins.right);
    CGSize size = CGSizeMake(width, [self.preview heightForWidth:width]);
    if (CGSizeEqualToSize(self.preview.bounds.size, size)) return;
    self.preview.frame = (CGRect){CGPointZero, size};
    table.tableHeaderView = self.preview;
}

// Back from Shows' or Text size's list, the preview reads them again.
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.preview reload];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    self.preview.running = YES;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.preview.running = NO;
}

@end

// A menu row of `names` stored under `key`, which shows the preview the new choice.
static SGModRow *menuRow(NSString *title, NSString *key, NSArray<NSString *> *names, NSInteger fallback, SGLiveActivityPreview *preview) {
    __weak SGLiveActivityPreview *weakPreview = preview;
    return SGMenuRow(title, names, ^NSString *{
        NSInteger index = SGInt(key, fallback);
        return names[(NSUInteger)(index >= 0 && index < (NSInteger)names.count ? index : fallback)];
    }, ^(NSInteger index) {
        SGSetInt(key, index);
        [weakPreview reload];
    });
}

static BOOL hasActivityExtension(void) {
    static BOOL present;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *path = [NSBundle.mainBundle.builtInPlugInsPath stringByAppendingPathComponent:@"SpotifyGlassLiveActivity.appex"];
        BOOL directory = NO;
        present = path && [NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&directory] && directory;
    });
    return present;
}

BOOL SGLiveActivityAllowedByInstall(void) {
    return hasActivityExtension() && [[NSBundle.mainBundle objectForInfoDictionaryKey:@"NSSupportsLiveActivities"] boolValue];
}

// At the top while the install lacks the declaration or extension.
static SGModRow *missingRow(void) {
    SGModRow *row = SGWarningRow(SGL(@"settings.liveactivity.missing.title", @"Missing from this install"), SGL(@"settings.liveactivity.missing.subtitle", @"Tap for why"), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGL(@"settings.liveactivity.missing.alert.title", @"Live Activity is missing")
            message:!hasActivityExtension()
                ? SGL(@"settings.liveactivity.missing.extension.message", @"The lock screen Live Activity is unavailable in this install. App extensions may have been removed during signing or left out of the IPA; LiveContainer also cannot register them. To use Live Activity, keep app extensions when signing and install an IPA that includes them directly, outside LiveContainer. The rest of Retrine still works.")
                : SGL(@"settings.liveactivity.missing.alert.message", @"iOS shows a Live Activity only for an app that says it has one, and only Retrine's IPA build writes that into Spotify. This Spotify was put together another way, such as with Retrine's .deb injected by hand, so iOS turns the card down. Build the IPA with Retrine to get it.")
            preferredStyle:UIAlertControllerStyleAlert];
        alert.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.ok", @"OK") style:UIAlertActionStyleCancel handler:nil]];
        [SGTopController() presentViewController:alert animated:YES completion:nil];
    });
    row.visible = ^BOOL { return !SGLiveActivityAllowedByInstall(); };
    return row;
}

UIViewController *SGLiveActivitySettingsPage(void) {
    SGLiveActivityPreview *preview = [SGLiveActivityPreview new];
    __weak SGLiveActivityPreview *weakPreview = preview;
    void (^switched)(BOOL) = ^(BOOL on) { [weakPreview reload]; };

    SGModRow *on = SGOptionRow(SGL(@"settings.liveactivity.title", @"Live Activity"), nil, SGKeyLiveActivity);
    on.changed = ^(BOOL value) { SGSetLiveActivityEnabled(value); };
    on.visible = ^BOOL { return SGLiveActivityAllowedByInstall(); };
    SGModRow *view = SGChoiceRow(SGL(@"settings.liveactivity.shows.title", @"Shows"), nil, SGKeyLiveActivityView, viewNames(), SGLiveActivityLyrics);
    // The lyrics view's own rows, shown while it is picked.
    SGModRow *without = menuRow(SGL(@"settings.liveactivity.withoutlyrics.title", @"Without lyrics"), SGKeyLiveActivityWithoutLyrics, @[SGL(@"settings.liveactivity.withoutlyrics.choice.note", @"Note"), SGL(@"settings.liveactivity.withoutlyrics.choice.track", @"Track")], SGLiveActivityWithoutLyricsNote, preview);
    SGModRow *alignment = menuRow(SGL(@"settings.liveactivity.alignment.title", @"Alignment"), SGKeyLiveActivityAlignment, @[SGL(@"settings.liveactivity.alignment.choice.left", @"Left"), SGL(@"settings.liveactivity.alignment.choice.center", @"Center")], SGLiveActivityAlignCenter, preview);
    SGModRow *translation = SGOptionRow(SGL(@"settings.liveactivity.translations.title", @"Translations"), SGL(@"settings.liveactivity.translations.subtitle", @"Under the line, when the lyrics have one"), SGKeyLiveActivityTranslation);
    translation.changed = switched;
    SGModRow *size = SGChoiceRow(SGL(@"settings.liveactivity.textsize.title", @"Text size"), nil, SGKeyLiveActivityTextSize, @[SGL(@"settings.liveactivity.textsize.choice.small", @"Small"), SGL(@"settings.liveactivity.textsize.choice.medium", @"Medium"), SGL(@"settings.liveactivity.textsize.choice.large", @"Large")], SGLiveActivityTextMedium);
    for (SGModRow *row in @[without, alignment, translation, size]) row.visible = ^BOOL { return SGInt(SGKeyLiveActivityView, SGLiveActivityLyrics) == SGLiveActivityLyrics; };
    // Every view's.
    SGModRow *artwork = SGSwitchRow(SGL(@"settings.liveactivity.artwork.title", @"Artwork"), SGL(@"settings.liveactivity.artwork.subtitle", @"The cover beside the track's name and in the Dynamic Island"), SGKeyLiveActivityArtwork);
    artwork.changed = switched;
    SGModRow *colors = menuRow(SGL(@"settings.liveactivity.colors.title", @"Colors"), SGKeyLiveActivityColors, @[SGL(@"settings.liveactivity.colors.choice.spotify", @"Spotify"), SGL(@"settings.liveactivity.colors.choice.artwork", @"Artwork"), SGL(@"settings.liveactivity.colors.choice.plain", @"Plain")], SGLiveActivityColorsSpotify, preview);
    SGModRow *progress = SGSwitchRow(SGL(@"settings.liveactivity.progressbar.title", @"Progress bar"), nil, SGKeyLiveActivityProgressBar);
    progress.changed = switched;
    // What a card on the lock screen, in the Dynamic Island, on a Watch or in CarPlay is looked for by.
    for (SGModRow *row in @[on, view, without, alignment, translation, size, artwork, colors, progress])
        SGSearchKeywords(row, SGL(@"settings.search.live_activity.keywords", @"dynamic island lock screen apple watch carplay card activity"));
    // A choice or menu row stores under a key its own blocks hold, so it has no key of its own for the search to
    // remember it by; these rows are the shared Live Activity's, under either look, so their names carry no look.
    SGSearchIdentified(view, SGKeyLiveActivityView);
    SGSearchIdentified(without, SGKeyLiveActivityWithoutLyrics);
    SGSearchIdentified(alignment, SGKeyLiveActivityAlignment);
    SGSearchIdentified(size, SGKeyLiveActivityTextSize);
    SGSearchIdentified(colors, SGKeyLiveActivityColors);
    SGLiveActivityPage *page = [[SGLiveActivityPage alloc] initWithTitle:SGL(@"settings.liveactivity.title", @"Live Activity") intro:nil sections:@[
        SGSection(nil, @[missingRow(), on, view, without, alignment, translation, size]),
        SGNotedSection(SGL(@"settings.liveactivity.card.header", @"Card"), @[artwork, colors, progress],
                       SGL(@"settings.liveactivity.card.footer", @"Colors: Spotify puts the cover's color behind Spotify's green, Artwork takes the green from the cover too, "
                       @"and Plain is white on the lock screen's own background. "
                       @"The card also shows on a paired Apple Watch, in its Smart Stack, from iOS 18, and in CarPlay from iOS 26, "
                       @"as a smaller card of the line or the track. A tap there opens Spotify on the iPhone.")),
    ] footer:nil];
    page.preview = preview;
    return page;
}

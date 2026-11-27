// The AutoMix page (App/ModSettings.x links it from the root, under either look): a preview of the transition the
// rows make (AutoMixPreview.m), the switch, then the style and the blend length, which read Spotify's own settings
// and gray out while the switch is off, and, while it is on, the redesigned player's three options.
// It has no restart note: Spotify's player takes a new setting at the next track change, and the player follows
// its options at once.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "AutoMix.h"
#import "AutoMixPreview.h"

// Spotify's own crossfade slider (Settings > Playback) runs from 0, which is off and is the switch here, to 12 s.
static const double kShortest = 1, kLongest = 12, kUnread = 5;

// The blend length as the slider shows it.
static double blendSeconds(void) {
    SGTransitionSettings s;
    return SGTransitionSettingsRead(&s) ? MAX(kShortest, MIN(kLongest, s.milliseconds / 1000.0)) : kUnread;
}

@interface SGAutoMixPage : SGModPage
@property (nonatomic, strong) SGAutoMixPreview *preview;
@end

@implementation SGAutoMixPage

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.tableHeaderView = self.preview;
    // Spotify's Playback page writes the same settings, whether this page shows or not.
    [NSNotificationCenter.defaultCenter addObserver:self.preview selector:@selector(reload) name:SGTransitionSettingsDidChangeNotification object:nil];
}

// Handed back to the table only when its size changes: the table lays out again on every handing back.
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

@end

static SGModRow *playerOption(NSString *title, NSString *key) {
    SGModRow *row = SGOptionRow(title, nil, key);
    row.visible = ^BOOL { return SGFlag(SGKeyAutoMix, NO); };
    row.changed = ^(BOOL on) {
        [NSNotificationCenter.defaultCenter postNotificationName:SGAutoMixPlayerOptionsDidChangeNotification object:nil];
    };
    return row;
}

UIViewController *SGAutoMixSettingsPage(void) {
    SGAutoMixPreview *preview = [[SGAutoMixPreview alloc] initWithReading:^SGAutoMixPreviewReading {
        if (!SGFlag(SGKeyAutoMix, NO)) return (SGAutoMixPreviewReading){SGAutoMixPreviewOff, lround(blendSeconds())};
        SGAutoMixPreviewStyle style = SGAutoMixCurrentStyle() == SGAutoMixBeatMatched ? SGAutoMixPreviewBeatMatched : SGAutoMixPreviewCrossfade;
        return (SGAutoMixPreviewReading){style, lround(blendSeconds())};
    }];
    __weak SGAutoMixPreview *weakPreview = preview;

    SGModRow *toggle = SGOptionRow(SGL(@"settings.automix.title", @"AutoMix"), nil, SGKeyAutoMix);
    toggle.changed = ^(BOOL on) {
        SGAutoMixApply(on);
        [weakPreview reload];
    };

    NSArray<NSString *> *styles = @[SGL(@"settings.automix.style.choice.beatmatched", @"Beat-matched"), SGL(@"settings.automix.style.choice.crossfade", @"Crossfade")];
    SGModRow *style = SGMenuRow(SGL(@"settings.automix.style.title", @"Style"), styles, ^NSString *{ return styles[(NSUInteger)SGAutoMixCurrentStyle()]; },
                                ^(NSInteger index) {
                                    SGAutoMixSetStyle(index);
                                    [weakPreview reload];
                                });
    style.waitsOn = SGKeyAutoMix;

    SGModRow *blend = SGSliderRow(SGL(@"settings.automix.blendlength.title", @"Blend length"), nil, kShortest, kLongest, 1,
        ^double { return blendSeconds(); },
        ^(double value) {
            SGAutoMixSetSeconds(lround(value));
            [weakPreview reload];
        },
        ^NSString *(double value) { return [NSString stringWithFormat:SGL(@"settings.automix.blendlength.format", @"%ld s"), lround(value)]; });
    blend.waitsOn = SGKeyAutoMix;

    NSArray<SGModRow *> *player = @[
        playerOption(SGL(@"settings.automix.showprogress.title", @"Transitions in the progress bar"), SGKeyAutoMixShowProgress),
        playerOption(SGL(@"settings.automix.showqueue.title", @"Transitions in the queue"), SGKeyAutoMixShowQueue),
        playerOption(SGL(@"settings.automix.artwork.title", @"Artwork moves with the mix"), SGKeyAutoMixArtwork),
    ];

    // Spotify's Automix covers only some playlists Spotify made; the user's own need its Mix toggle in Spotify's queue or the playlist's ⋯ menu (#52, #74).
    NSString *note = SGL(@"settings.automix.footer.style", @"Beat-matched works only on some playlists Spotify made. For your own playlists, also turn on Mix in Spotify's queue or the playlist's ⋯ menu.");
    if (!SGAutoMixAccountAllows())
        note = [NSString stringWithFormat:@"%@ %@", SGL(@"settings.automix.footer.note", @"AutoMix needs Premium, or Spoof Premium under Premium, ads & privacy."), note];
    SGAutoMixPage *page = [[SGAutoMixPage alloc] initWithTitle:SGL(@"settings.automix.title", @"AutoMix") intro:nil sections:@[
        SGNotedSection(nil, @[toggle, style, blend], note),
        SGNotedSection(nil, player, SGL(@"settings.automix.player.footer", @"In the redesigned player. The progress bar and the cover show crossfades only, as Spotify gives no times for a beat-matched blend.")),
    ] footer:nil];
    page.preview = preview;
    return page;
}

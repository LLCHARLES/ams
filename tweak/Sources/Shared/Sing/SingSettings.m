// The Sing page (Sing on Mod Settings' main page, and Lyrics > Karaoke), under either look: the card at its top
// (SGSingCard.m: the song, what Sing is doing, the vocals and the rest traced live, play and pause, the vocals'
// level and its three stops), Sing's switch, which turns the mic on and off at once, Ignore heat warnings, the voice
// model (Best quality or Light, the chosen one's download and removal, and the other's removal), spatial voice's page (its preview, SGSpatialPreview.m, and its switch), and Runs on under
// Advanced. While the page is on screen with Spotify in front, the card's reads of its lines keep Sing separating
// the playing song even at As sung, where it otherwise rests (SGSingReadLevels), so what the card shows and what
// its slider sets are heard at once; popped, covered or in the background, the page no longer counts.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Sing.h"
#import <sys/utsname.h>

// Chips before the A14 (the iPhone XS, XR, 11 and SE 2: iPhone11,x and iPhone12,x) are untested and may not keep up.
static BOOL untestedChip(void) {
    struct utsname name;
    int major = 0;
    return uname(&name) == 0 && sscanf(name.machine, "iPhone%d,", &major) == 1 && major < 13;
}

UIView *SGSingCardView(void);   // SGSingCard.m

static void ask(NSString *title, NSString *message, NSString *action, BOOL destructive, void (^then)(void)) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:action style:destructive ? UIAlertActionStyleDestructive : UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) { then(); }]];
    SGPresentDark(alert);
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

NSString *SGSingLevelText(double level) {
    if (level <= 0.001) return SGL(@"settings.karaoke.level.gone", @"Gone");
    if (level < 0.999) return [NSString stringWithFormat:SGL(@"settings.karaoke.level.percent", @"%.0f%%"), level * 100];
    if (level <= 1.001) return SGL(@"settings.karaoke.level.assung", @"As sung");
    if (level >= 1.999) return SGL(@"settings.karaoke.level.vocalsonly", @"Vocals only");
    return [NSString stringWithFormat:SGL(@"settings.karaoke.level.backing", @"Backing %.0f%%"), (2 - level) * 100];
}

static NSString *bytes(long long count) {
    return [NSByteCountFormatter stringFromByteCount:count countStyle:NSByteCountFormatterCountStyleFile];
}

// The row's state: with the old model, its update reads as the model's download, worded as an update.
static SGSingModelState rowState(void) {
    if (SGSingModelUpdateDownloading()) return SGSingModelDownloading;
    if (SGSingModelUpdateAvailable()) return SGSingModelMissing;
    return SGSingModelCurrentState();
}

static NSString *modelValue(void) {
    if (!SGSingOSSupported()) return SGL(@"settings.karaoke.model.status.unavailable", @"Unavailable");
    BOOL update = SGSingModelUpdateAvailable();
    switch (rowState()) {
        case SGSingModelDownloading:
            if (SGSingModelChecking()) return SGL(@"settings.karaoke.model.status.checking", @"Checking…");
            if (SGSingModelWaitingForNetwork()) return SGSingModelOverCellular() ? SGL(@"settings.karaoke.model.status.waitingfornetwork", @"Waiting for the network") : SGL(@"settings.karaoke.model.status.waitingforwifi", @"Waiting for Wi-Fi");
            return [NSString stringWithFormat:SGL(@"settings.karaoke.model.status.progress", @"%.0f%%"), SGSingModelProgress() * 100];
        case SGSingModelReady: return [NSString stringWithFormat:SGL(@"settings.karaoke.model.status.downloaded", @"Downloaded · %@"), SGSingModelSizeText()];
        case SGSingModelMissing:
            if (SGSingModelError()) return update ? SGL(@"settings.karaoke.model.status.updatefailed", @"Update failed, try again") : SGL(@"settings.karaoke.model.status.downloadfailed", @"Failed, try again");
            if (SGSingModelPausedBytes()) {
                return [NSString stringWithFormat:SGL(@"settings.karaoke.model.status.pausedformat", @"%@ · %@ of %@"), update ? SGL(@"settings.karaoke.model.status.updatepaused", @"Update paused") : SGL(@"settings.karaoke.model.status.paused", @"Paused"), bytes(SGSingModelPausedBytes()), SGSingModelSizeText()];
            }
            return [NSString stringWithFormat:update ? SGL(@"settings.karaoke.model.status.updateavailable", @"Update available · %@") : SGL(@"settings.karaoke.model.status.downloadneeded", @"Download, %@"), SGSingModelSizeText()];
    }
    return @"";
}

static void modelTapped(UITableViewController *page) {
    if (!SGSingOSSupported()) {
        SGPresentInformation(SGTopController(), SGL(@"settings.karaoke.model.alert.title", @"Voice model"), SGSingMissing());
        return;
    }
    switch (rowState()) {
        case SGSingModelMissing: {
            BOOL update = SGSingModelUpdateAvailable();
            NSString *message = [NSString stringWithFormat:SGL(@"settings.karaoke.model.download.message", @"%@%@%@ from Hugging Face. It waits for Wi-Fi unless you let it use cellular. It stays on this iPhone, and no audio leaves it."),
                                 SGSingModelError() ? [NSString stringWithFormat:SGL(@"settings.karaoke.model.download.lasterror", @"The last try failed: %@\n\n"), SGSingModelError()] : @"",
                                 update ? SGL(@"settings.karaoke.model.download.updatenote", @"The new voice model runs on the Neural Engine, faster and cooler, and Karaoke keeps the one it has until it is in. ") : @"",
                                 SGSingModelSizeText()];
            if (untestedChip()) {
                message = [message stringByAppendingString:SGSingChosenModel() == SGSingModelLight
                    ? SGL(@"settings.karaoke.model.download.warning.light", @"\n\nKaraoke is tested on the iPhone 15 Pro. On iPhones older than the iPhone 12 it may not keep up, even with the light model.")
                    : SGL(@"settings.karaoke.model.download.warning.full", @"\n\nKaraoke is tested on the iPhone 15 Pro. On iPhones older than the iPhone 12 it may not keep up; the light model has a better chance.")];
            }
            NSString *title = SGSingModelPausedBytes() ? (update ? SGL(@"settings.karaoke.model.resume.update.title", @"Carry on with the update?") : SGL(@"settings.karaoke.model.resume.download.title", @"Carry on with the download?"))
                                                       : (update ? SGL(@"settings.karaoke.model.start.update.title", @"Download the update?") : SGL(@"settings.karaoke.model.start.download.title", @"Download the voice model?"));
            ask(title, message, SGL(@"settings.karaoke.model.action.download", @"Download"), NO, ^{ SGSingDownloadModel(); });
            break;
        }
        case SGSingModelDownloading:
            if (SGSingModelWaitingForNetwork() && !SGSingModelOverCellular()) {
                ask(SGL(@"settings.karaoke.model.cellular.alert.title", @"Download over cellular?"), [NSString stringWithFormat:SGL(@"settings.karaoke.model.cellular.alert.message", @"The download waits for Wi-Fi. Over cellular or a Low Data Mode network it uses up to %@ of your plan."),
                                                 SGSingModelSizeText()], SGL(@"settings.karaoke.model.cellular.action.use", @"Use cellular"), NO, ^{ SGSingDownloadModelOverCellular(); });
                break;
            }
            ask(SGL(@"settings.karaoke.model.stop.alert.title", @"Stop the download?"), SGL(@"settings.karaoke.model.stop.alert.message", @"What has come in is kept, so the next download carries on from it."), SGL(@"settings.karaoke.model.action.stop", @"Stop"), YES, ^{ SGSingCancelModelDownload(); });
            break;
        case SGSingModelReady:
            ask(SGL(@"settings.karaoke.model.delete.alert.title", @"Delete the voice model?"), [NSString stringWithFormat:SGL(@"settings.karaoke.model.delete.alert.message", @"It frees %@. Karaoke needs it again to turn the vocals down."), SGSingModelInUseSizeText()],
                SGL(@"common.delete", @"Delete"), YES, ^{
                    SGSetSingOn(NO);
                    SGSingDeleteModel();
                    // Sing's switch goes off with it.
                    [page.tableView reloadData];
                });
            break;
    }
}

// Spatial voice's page, under Sing's: the preview at its top and the switch.
@interface SGSpatialVoicePage : SGModPage
@property (nonatomic, readonly) SGSpatialPreview *preview;
@end

@implementation SGSpatialVoicePage

- (void)viewDidLoad {
    [super viewDidLoad];
    _preview = [[SGSpatialPreview alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 0)];
    self.tableView.tableHeaderView = _preview;
}

// Its caption follows Dynamic Type and what the preview is doing, so the header is sized to it, and handed back
// only when that size changes (SGFitNote's way: the table lays out again on every handing back).
- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    UITableView *table = self.tableView;
    CGSize size = [_preview sizeThatFits:CGSizeMake(table.bounds.size.width, 0)];
    if (CGSizeEqualToSize(_preview.bounds.size, size)) return;
    _preview.frame = (CGRect){_preview.frame.origin, size};
    table.tableHeaderView = _preview;
}

@end

UIViewController *SGSpatialVoiceSettingsPage(void) {
    SGModRow *spatial = SGOptionRow(SGL(@"settings.spatial.title", @"Spatial voice"), nil, SGKeySingSpatial);
    __block __weak SGSpatialVoicePage *page;
    spatial.changed = ^(BOOL on) {
        SGSetSingSpatial(on);
        [page.preview refresh];
    };
    SGSpatialVoicePage *made = [[SGSpatialVoicePage alloc] initWithTitle:SGL(@"settings.spatial.title", @"Spatial voice") intro:nil sections:@[
        SGNotedSection(nil, @[spatial],
                       SGL(@"settings.spatial.intro", @"The singer's voice keeps its place in front of you as you turn your head, while the rest of the song turns with "
                       @"you; stay turned, and it comes round in front again. It follows your head through headphones that "
                       @"track it: AirPods Pro, AirPods 3 or later, AirPods Max, and asks for Motion & Fitness the first time. "
                       @"While iOS's own Spatialize Stereo is on, which already holds the whole song in place, the voice is left to it.")),
        SGNotedSection(SGL(@"settings.spatial.sound.header", @"Sound"), @[
            SGSliderRow(SGL(@"settings.spatial.distance.title", @"Distance"), nil, 1, 6.5, 0.5, ^double { return SGSingSpatialDistance(); }, ^(double value) {
                SGSetSingSpatialSound(value, SGSingSpatialRoom(), SGSingSpatialFront(), SGSingSpatialWidth());
            }, ^NSString *(double value) { return [NSString stringWithFormat:SGL(@"settings.spatial.distance.format", @"%.1f m"), value]; }),
            SGSliderRow(SGL(@"settings.spatial.room.title", @"Room"), nil, 0, 100, 5, ^double { return SGSingSpatialRoom(); }, ^(double value) {
                SGSetSingSpatialSound(SGSingSpatialDistance(), value, SGSingSpatialFront(), SGSingSpatialWidth());
            }, ^NSString *(double value) { return [NSString stringWithFormat:SGL(@"settings.spatial.room.format", @"%.0f%%"), value]; }),
            SGSliderRow(SGL(@"settings.spatial.front.title", @"Back in front"), nil, 5, 60, 1, ^double { return SGSingSpatialFront(); }, ^(double value) {
                SGSetSingSpatialSound(SGSingSpatialDistance(), SGSingSpatialRoom(), value, SGSingSpatialWidth());
            }, ^NSString *(double value) { return [NSString stringWithFormat:SGL(@"settings.spatial.front.format", @"After %.0f s"), value]; }),
            SGSliderRow(SGL(@"settings.spatial.width.title", @"Instruments width"), nil, 0, 200, 5, ^double { return SGSingSpatialWidth(); }, ^(double value) {
                SGSetSingSpatialSound(SGSingSpatialDistance(), SGSingSpatialRoom(), SGSingSpatialFront(), value);
            }, ^NSString *(double value) { return [NSString stringWithFormat:SGL(@"settings.spatial.width.format", @"%.0f%%"), value]; }),
        ], SGL(@"settings.spatial.sound.footer", @"How far ahead the voice sings, and how much of the room you hear around it: farther, the voice is quieter and "
           @"more of it is the room. Back in front is how long a head that stays turned takes to bring the voice ahead again. "
           @"Instruments width spreads the rest of the song wider than the recording, or narrows it below 100%.")),
    ] footer:nil];
    page = made;
    return made;
}

// The Sing page: the card (SGSingCard.m) as the table's header, sized to Dynamic Type, then its rows.
@interface SGSingPage : SGModPage
@end

@implementation SGSingPage {
    UIView *_card;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _card = SGSingCardView();
    self.tableView.tableHeaderView = _card;
}

// Handed back only when its size changes (SGFitNote's way: the table lays out again on every handing back).
- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    UITableView *table = self.tableView;
    CGSize size = [_card sizeThatFits:CGSizeMake(table.bounds.size.width, 0)];
    if (CGSizeEqualToSize(_card.bounds.size, size)) return;
    _card.frame = (CGRect){_card.frame.origin, size};
    table.tableHeaderView = _card;
}

@end

NSNotificationName const SGSingButtonDidChangeNotification = @"SGSingButtonDidChangeNotification";

BOOL SGSingButtonShown(void) {
    return SGFlag(SGKeySingButton, SGSingOSSupported());
}

UIViewController *SGSingSettingsPage(void) {
    SGModRow *sing = SGOptionRow(SGL(@"settings.karaoke.title", @"Karaoke"), nil, SGKeySing);
    sing.changed = ^(BOOL on) { SGSetSingOn(on); };
    // Only the redesign's lyrics have the mic.
    SGModRow *button = SGSwitchRow(SGL(@"settings.karaoke.togglebutton.title", @"Toggle from lyrics"), SGL(@"settings.karaoke.togglebutton.subtitle", @"The mic in the corner of the lyrics"), SGKeySingButton);
    button.defaultOn = SGSingOSSupported();
    button.changed = ^(BOOL on) { [NSNotificationCenter.defaultCenter postNotificationName:SGSingButtonDidChangeNotification object:nil]; };
    button.visible = ^BOOL { return SGRedesignedUIStored(); };
    SGModRow *heat = SGOptionRow(SGL(@"settings.karaoke.ignoreheat.title", @"Ignore heat warnings"), SGL(@"settings.karaoke.ignoreheat.subtitle", @"Keeps Karaoke going on a hot iPhone, which then gets hotter"), SGKeySingIgnoreHeat);
    SGModRow *memory = SGOptionRow(SGL(@"settings.karaoke.ignorememory.title", @"Ignore memory warnings"), SGL(@"settings.karaoke.ignorememory.subtitle", @"Keeps Karaoke going when iOS is low on memory, which may then close Spotify"),
                                   SGKeySingIgnoreMemory);
    heat.changed = ^(BOOL on) { SGSetSingIgnoresHeat(on); };
    __block __weak SGModPage *page;
    SGModRow *model = SGStatActionRow(SGL(@"settings.karaoke.model.row.title", @"Voice model"), nil, ^NSString *{ return modelValue(); }, ^{ modelTapped(page); });
    SGModRow *remove = SGActionRow(SGL(@"settings.karaoke.model.action.remove", @"Remove voice model"), nil, ^{
        BOOL partial = SGSingModelCurrentState() != SGSingModelReady;
        ask(partial ? SGL(@"settings.karaoke.model.remove.paused.title", @"Remove the paused download?") : SGL(@"settings.karaoke.model.remove.alert.title", @"Remove the voice model?"),
            partial ? [NSString stringWithFormat:SGL(@"settings.karaoke.model.remove.paused.message", @"It frees %@. A new download starts from the beginning."), bytes(SGSingModelPausedBytes())]
                    : [NSString stringWithFormat:SGL(@"settings.karaoke.model.remove.alert.message", @"It frees %@. Karaoke needs it again to turn the vocals down."), SGSingModelInUseSizeText()],
            SGL(@"common.remove", @"Remove"), YES, ^{
                SGSetSingOn(NO);
                SGSingDeleteModel();
                [page.tableView reloadData];
            });
    });
    remove.color = SGRed();
    remove.visible = ^BOOL { return SGSingModelCurrentState() == SGSingModelReady || SGSingModelPausedBytes() > 0; };
    // The two models, picked on the page: the rows below follow the one with the checkmark.
    SGModRow *(^choice)(NSString *, NSString *, SGSingModelKind) = ^SGModRow *(NSString *title, NSString *format, SGSingModelKind kind) {
        SGModRow *row = SGActionRow(title, [NSString stringWithFormat:format, SGSingModelSizeTextOf(kind)], ^{
            if (SGSingChosenModel() == kind) return;
            void (^choose)(void) = ^{
                SGSetSingChosenModel(kind);
                [page.tableView reloadData];
                [page refreshVisibility];
            };
            BOOL downloading = SGSingModelCurrentState() == SGSingModelDownloading || SGSingModelUpdateDownloading();
            if (!downloading) choose();
            else ask(SGL(@"settings.karaoke.model.switch.stop.title", @"Stop the download?"), SGL(@"settings.karaoke.model.switch.stop.message", @"The voice model coming in stops, and what has come in is kept for when you choose it again."), SGL(@"settings.karaoke.model.switch.action", @"Switch"), NO, choose);
        });
        row.checked = ^BOOL { return SGSingChosenModel() == kind; };
        return row;
    };
    SGModRow *full = choice(SGL(@"settings.karaoke.model.choice.full.title", @"Best quality"), SGL(@"settings.karaoke.model.choice.full.subtitle", @"The full model, %@: the cleanest result, for recent iPhones"), SGSingModelFull);
    SGModRow *light = choice(SGL(@"settings.karaoke.model.choice.light.title", @"Light"), SGL(@"settings.karaoke.model.choice.light.subtitle", @"A small model, %@, for older iPhones: more of the voice is left in, and the music dips under it"),
                             SGSingModelLight);
    SGModRow *other = SGStatActionRow(SGL(@"settings.karaoke.model.removeother.title", @"Remove the other model"), nil, ^NSString *{ return bytes(SGSingOtherModelBytes()); }, ^{
        NSString *name = SGSingChosenModel() == SGSingModelFull ? SGL(@"settings.karaoke.model.name.light", @"Light") : SGL(@"settings.karaoke.model.name.full", @"Best quality");
        ask(SGL(@"settings.karaoke.model.removeother.alert.title", @"Remove the other model?"), [NSString stringWithFormat:SGL(@"settings.karaoke.model.removeother.alert.message", @"%@ is not in use. Removing it frees %@, and choosing it again downloads it again."),
                                         name, bytes(SGSingOtherModelBytes())],
            SGL(@"common.remove", @"Remove"), YES, ^{
                SGSingDeleteOtherModel();
                [page refreshVisibility];
            });
    });
    other.color = SGRed();
    other.visible = ^BOOL { return SGSingOtherModelBytes() > 0; };
    SGModRow *spatial = SGPageRow(SGL(@"settings.spatial.title", @"Spatial voice"), ^UIViewController *{ return SGSpatialVoiceSettingsPage(); });
    SGSearchIdentified(spatial, @"page.spatialvoice");
    SGSearchKeywords(spatial, SGL(@"settings.search.spatial_voice.keywords", @"spatial audio surround head tracking headphone motion"));
    spatial.subtitle = SGL(@"settings.spatial.subtitle", @"With AirPods, the voice stays in front of you as you turn your head");
    spatial.value = ^NSString *{ return SGSingSpatial() ? SGL(@"common.on", @"On") : SGL(@"common.off", @"Off"); };
    // Facts about the iPhone, which do not change while the page shows.
    spatial.visible = ^BOOL { return SGSingSpatialAvailable(); };
    SGModRow *units = SGChoiceRow(SGL(@"settings.karaoke.computeunits.title", @"Runs on"), nil, SGKeySingComputeUnits, SGSingComputeUnitNames(), 0);
    units.choiceNotes = @[SGL(@"settings.karaoke.computeunits.note.auto", @"The Neural Engine, the fastest, with the CPU while it loads"), SGL(@"settings.karaoke.computeunits.note.cpu", @"Slower and warmer, and a little less memory")];
    units.choiceFooter = SGL(@"settings.karaoke.computeunits.footer", @"Karaoke loads the voice model on the CPU first and starts with it. On Automatic a second copy then loads on "
                         @"the Neural Engine and takes over, in the background too. The iPhone prepares it the first time after Retrine "
                         @"is installed or updated, for a minute or so, and Karaoke runs on the CPU until then, unless Prepare after "
                         @"updates did it already. If it does not load, "
                         @"Karaoke stays on the CPU until Spotify is opened again.");
    units.chosen = ^(NSInteger index) { SGSingComputeUnitsChanged(); };
    SGModRow *prepare = SGSwitchRow(SGL(@"settings.karaoke.prepareahead.title", @"Prepare after updates"),
                                    SGL(@"settings.karaoke.prepareahead.subtitle", @"Readies the Neural Engine in the background after Retrine or iOS updates, so Karaoke starts at full speed"), SGKeySingPrepareAhead);
    SGSingPage *made = [[SGSingPage alloc] initWithTitle:SGL(@"settings.karaoke.title", @"Karaoke") intro:nil sections:@[
        SGSection(nil, @[sing, button]),
        SGNotedSection(SGL(@"settings.karaoke.model.header", @"Voice model"), @[full, light, model, remove, other],
                       SGL(@"settings.karaoke.model.footer", @"Each model is downloaded and kept on its own, and Karaoke needs only the chosen one. A switch takes effect "
                       @"without restarting Spotify: the model loads in a few seconds, and the song plays as it is until it is in.")),
        SGSection(nil, @[spatial]),
        SGNotedSection(SGL(@"settings.karaoke.advanced.header", @"Advanced"), @[units, prepare, heat, memory],
                       SGL(@"settings.karaoke.advanced.footer", @"Karaoke turns a song's vocals down to sing over, or the rest down to hear the vocals alone, with a voice model that "
                       @"runs only on this iPhone: no audio leaves it. It listens a few seconds ahead of what plays, so the vocals change a "
                       @"few seconds after a song starts or after a seek.")),
    ] footer:nil];
    page = made;
    return made;
}

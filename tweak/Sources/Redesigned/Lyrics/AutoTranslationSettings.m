// The Lyrics page's Automatic translation rows: its switch, and the order its services are asked in, each read
// out with whether it can work now. What they do lives in AutoTranslation.m.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/LyricsTranslation/LyricsTranslation.h"
#import "AutoTranslation.h"
#import "LyricsText.h"

// The lyrics menu's glyph for the same service.
static NSString *autoTranslatorSymbol(SGRAutoTranslator provider) {
    switch (provider) {
        case SGRAutoTranslatorOnDevice: return @"translate";
        case SGRAutoTranslatorAppleIntelligence: return @"apple.intelligence";
        case SGRAutoTranslatorGoogle: return @"globe";
        case SGRAutoTranslatorBing: return @"globe.americas";
        case SGRAutoTranslatorDeepL: return @"character.book.closed";
        case SGRAutoTranslatorGemini: return @"sparkles";
        case SGRAutoTranslatorClaude: return @"sparkle";
        case SGRAutoTranslatorOpenAI: return @"cpu";
        default: return nil;
    }
}

// Where the lyrics go, said under each name.
static NSString *autoTranslatorDestination(SGRAutoTranslator provider) {
    switch (provider) {
        case SGRAutoTranslatorOnDevice: return SGL(@"settings.lyrics.auto_translation.ondevice.note", @"On this iPhone, with both languages downloaded in the Translate app");
        case SGRAutoTranslatorAppleIntelligence: return SGL(@"settings.lyrics.auto_translation.intelligence.note", @"On this iPhone");
        case SGRAutoTranslatorGoogle: return SGL(@"settings.lyricstools.menu.google.subtitle", @"Sends the lyrics to Google Translate");
        case SGRAutoTranslatorBing: return SGL(@"settings.lyricstools.menu.bing.subtitle", @"Sends the lyrics to Bing Translator");
        case SGRAutoTranslatorDeepL: return SGL(@"settings.lyrics.auto_translation.deepl.note", @"Sends the lyrics to DeepL on your key");
        case SGRAutoTranslatorGemini: return SGL(@"settings.lyrics.auto_translation.gemini.note", @"Sends the lyrics to Google on your key");
        case SGRAutoTranslatorClaude: return SGL(@"settings.lyrics.auto_translation.claude.note", @"Sends the lyrics to Anthropic on your key");
        case SGRAutoTranslatorOpenAI: return SGL(@"settings.lyrics.auto_translation.openai.note", @"Sends the lyrics to the service you set, on your key");
        default: return nil;
    }
}

// Why a service is passed over now, or nil while it can be asked.
static NSString *autoTranslatorSkip(SGRAutoTranslator provider, SGRAutoTranslationState state) {
    switch (state) {
        case SGRAutoTranslationReady: return nil;
        case SGRAutoTranslationNeedsKey: return SGL(@"settings.lyrics.auto_translation.skip.key", @"Skipped: no API key in Lyrics › Translation & AI");
        case SGRAutoTranslationNeedsSwitch: return SGL(@"settings.lyrics.auto_translation.skip.switch", @"Skipped: switched off in Lyrics › Translation & AI");
        case SGRAutoTranslationNeedsSettings: return SGL(@"settings.lyrics.auto_translation.skip.settings", @"Skipped: check its base URL and model in Lyrics › Translation & AI");
        case SGRAutoTranslationUnavailableDevice:
            return provider == SGRAutoTranslatorAppleIntelligence
                ? SGL(@"settings.lyrics.auto_translation.skip.intelligence", @"Skipped: needs Apple Intelligence on, in a language it supports")
                : SGL(@"settings.lyrics.auto_translation.skip.device", @"Skipped: not available on this iPhone");
        case SGRAutoTranslationUnsupportedLanguage: return SGL(@"settings.lyrics.auto_translation.skip.language", @"Skipped: can't translate into the translation language");
    }
    return nil;
}

// Drag the services into the order they are asked in. Every one stays in the list; one that cannot be asked
// now is gray, with why under it, and passed over until it can.
@interface SGRAutoTranslationOrderPage : SGPage
@end

@implementation SGRAutoTranslationOrderPage {
    NSMutableArray<NSNumber *> *_order;
    UIView *_footer;
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = SGL(@"settings.lyrics.auto_translation.order.title", @"Translation order");
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _order = [SGRAutoTranslationOrder() mutableCopy];
    self.tableView.editing = YES;
    _footer = SGNote(SGL(@"settings.lyrics.auto_translation.order.footer",
        @"When lyrics show without a translation of their own, each service is asked once, from the top: lines one leaves "
        @"untranslated, or a whole song it fails, go on to the next. Gray ones are skipped until they are set up in Lyrics › Translation & AI. "
        @"Except on this iPhone, the lyrics go to the service, and one on your own key counts each song toward its usage and charges."));
    self.tableView.tableFooterView = _footer;
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    SGFitNote(self.tableView, _footer, 16, 24);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_order.count;
}

- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    return SGSectionHeader(table, SGL(@"settings.lyrics.auto_translation.order.header", @"Asked top to bottom"));
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    return SGSectionHeaderHeight();
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = SGDequeueCell(table, @"translator");
    SGRAutoTranslator provider = _order[(NSUInteger)path.row].integerValue;
    NSString *skip = autoTranslatorSkip(provider, SGRAutoTranslationStateOf(provider, SGLyricsGeminiLanguage()));
    NSString *destination = autoTranslatorDestination(provider);
    NSString *detail = skip ? [NSString stringWithFormat:@"%@\n%@", destination, skip] : destination;
    SGFillCell(cell, SGRAutoTranslatorName(provider), detail, skip ? SGGrey() : nil, autoTranslatorSymbol(provider));
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (BOOL)tableView:(UITableView *)table canMoveRowAtIndexPath:(NSIndexPath *)path {
    return YES;
}

- (BOOL)tableView:(UITableView *)table canEditRowAtIndexPath:(NSIndexPath *)path {
    return YES;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)table editingStyleForRowAtIndexPath:(NSIndexPath *)path {
    return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)table shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)path {
    return NO;
}

- (void)tableView:(UITableView *)table moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
    NSNumber *provider = _order[(NSUInteger)from.row];
    [_order removeObjectAtIndex:(NSUInteger)from.row];
    [_order insertObject:provider atIndex:(NSUInteger)to.row];
    SGRSetAutoTranslationOrder(_order);
}

@end

// Turning it on is asking to see translations, so it turns Show Translation on once, here and nowhere else.
SGModRow *SGRAutoTranslationRow(void) {
    SGModRow *row = SGOptionRow(SGL(@"settings.lyrics.auto_translation.title", @"Automatic translation"),
                                SGL(@"settings.lyrics.auto_translation.subtitle", @"Translates lyrics that come without a translation"),
                                SGRKeyLyricsAutoTranslation);
    row.info = SGL(@"settings.lyrics.auto_translation.info",
        @"For songs in another language than the translation language, or every song with Translate any song on. Turning it on "
        @"turns Show Translation on. Remove Translation leaves a song as it is until Spotify restarts or these settings change. "
        @"Applies at once.");
    row.changed = ^(BOOL on) {
        SGRAutoTranslationSettingsChanged();
        if (on) SGRSetLyricsTextShown(SGRLyricsTextTranslation, YES);
    };
    return row;
}

// Reads out the service asked first among those that can be asked now.
SGModRow *SGRAutoTranslationOrderRow(void) {
    SGModRow *row = SGPageRow(SGL(@"settings.lyrics.auto_translation.order.title", @"Translation order"),
                              ^UIViewController *{ return [SGRAutoTranslationOrderPage new]; });
    row.value = ^NSString *{
        NSString *language = SGLyricsGeminiLanguage();
        for (NSNumber *provider in SGRAutoTranslationOrder()) {
            if (SGRAutoTranslationAvailable(provider.integerValue, language)) return SGRAutoTranslatorName(provider.integerValue);
        }
        return SGL(@"settings.lyrics.auto_translation.order.none", @"None ready");
    };
    row.waitsOn = SGRKeyLyricsAutoTranslation;
    return row;
}

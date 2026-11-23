#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "SponsorBlock.h"

static NSString *categoriesTitle(void) {
    return SGL(@"settings.sponsorblock.categories", @"Categories & behavior");
}

static NSArray<NSString *> *categoryTitles(void) {
    return @[
        SGL(@"settings.sponsorblock.sponsor", @"Sponsors"),
        SGL(@"settings.sponsorblock.selfpromo", @"Self-promotion"),
        SGL(@"settings.sponsorblock.interaction", @"Interaction reminders"),
        SGL(@"settings.sponsorblock.intro", @"Intros"),
        SGL(@"settings.sponsorblock.outro", @"Outros"),
        SGL(@"settings.sponsorblock.preview", @"Previews and recaps"),
        SGL(@"settings.sponsorblock.hook", @"Hooks"),
        SGL(@"settings.sponsorblock.filler", @"Filler"),
        SGL(@"settings.sponsorblock.exclusive_access", @"Exclusive-access promotions"),
    ];
}

static UIViewController *categoriesPage(void) {
    NSArray *titles = categoryTitles();
    NSArray *choices = @[SGL(@"settings.sponsorblock.auto", @"Auto-skip"), SGL(@"settings.sponsorblock.ask", @"Ask"),
                         SGL(@"settings.sponsorblock.show_only", @"Show only"), SGL(@"common.off", @"Off")];
    NSMutableArray *rows = [NSMutableArray array];
    NSArray *categories = SGSponsorBlockCategories();
    for (NSUInteger i = 0; i < categories.count; i++) {
        NSString *category = categories[i];
        NSString *key = SGSponsorBlockBehaviorKey(category);
        [rows addObject:SGSearchIdentified(SGMenuRow(titles[i], choices, ^NSString *{
            return choices[SGSponsorBlockReadBehavior(NSUserDefaults.standardUserDefaults, category)];
        }, ^(NSInteger index) { SGSetInt(key, index); }), key)];
    }
    return [[SGModPage alloc] initWithTitle:categoriesTitle() intro:SGRestartNote sections:@[SGSection(nil, rows)]
        footer:SGL(@"settings.sponsorblock.behavior_note", @"Ask offers a Skip button. Show only marks the progress bar without interrupting playback. Off leaves the category out of the request.")];
}

static NSString *privacyText(void) {
    return [NSString stringWithFormat:SGL(@"settings.sponsorblock.footer", @"Requests to %@ include the first five hex digits of the episode ID’s SHA-256 hash, selected categories, service (Spotify) and the Retrine client name. The server sees your IP address, not your full episode ID or Spotify account."), SGSponsorBlockServer()];
}

static void editServer(SGModSection *section) {
    UIViewController *owner = SGTopController();
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGL(@"settings.sponsorblock.server", @"SponsorBlock server")
        message:SGL(@"settings.sponsorblock.server_note", @"Enter an HTTPS server address without credentials, a query or a fragment. Leave it blank to use sponsor.ajay.app.")
        preferredStyle:UIAlertControllerStyleAlert];
    SGPresentDark(alert);
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.keyboardType = UIKeyboardTypeURL;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.placeholder = @"https://sponsor.ajay.app";
        field.text = SGSponsorBlockValidServer([NSUserDefaults.standardUserDefaults objectForKey:SGKeySponsorBlockServer]);
    }];
    UITextField *field = alert.textFields.firstObject;
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    UIAlertAction *save = [UIAlertAction actionWithTitle:SGL(@"common.save", @"Save") style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *action) {
            NSString *valid = SGSponsorBlockValidServer(field.text);
            if (!field.text.length) [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeySponsorBlockServer];
            else if (valid) [NSUserDefaults.standardUserDefaults setObject:valid forKey:SGKeySponsorBlockServer];
            section.footer = privacyText();
            if ([owner isKindOfClass:SGModPage.class]) [((SGModPage *)owner).tableView reloadData];
        }];
    [alert addAction:save];
    __weak UIAlertAction *weakSave = save;
    [field addAction:[UIAction actionWithHandler:^(UIAction *action) {
        NSString *input = ((UITextField *)action.sender).text;
        weakSave.enabled = !input.length || SGSponsorBlockValidServer(input) != nil;
    }] forControlEvents:UIControlEventEditingChanged];
    [owner presentViewController:alert animated:YES completion:nil];
}

static UIViewController *settingsPage(void) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    SGModRow *enabled = SGOptionRow(SGL(@"settings.sponsorblock.enabled", @"Skip podcast segments"),
        SGL(@"settings.sponsorblock.subtitle", @"Community-marked segments from SponsorBlock. Music is unchanged."), SGKeySponsorBlock);
    SGModRow *categories = SGSearchIdentified(SGPageRow(categoriesTitle(), ^{ return categoriesPage(); }), @"page.sponsorblock.categories");
    categories.searchKeywords = [categoryTitles() componentsJoinedByString:@"\n"];
    SGModRow *duration = SGSliderRow(SGL(@"settings.sponsorblock.minimum", @"Minimum segment duration"), nil,
        0, SGSponsorBlockMaxMinimum, 1, ^{ return SGSponsorBlockMinimum(); },
        ^(double seconds) { [store setDouble:seconds forKey:SGKeySponsorBlockMinimum]; },
        ^NSString *(double seconds) { return [NSString stringWithFormat:SGL(@"settings.sponsorblock.seconds", @"%.0f s"), seconds]; });
    SGModSection *rules = SGSection(SGL(@"settings.sponsorblock.rules", @"Playback rules"), @[
        SGSwitchRow(SGL(@"settings.sponsorblock.respect", @"Respect manual seeks"),
                    SGL(@"settings.sponsorblock.respect_note", @"Ask before skipping when you seek or resume inside a segment."), SGKeySponsorBlockRespectManual),
        SGSearchIdentified(duration, SGKeySponsorBlockMinimum),
        SGSwitchRow(SGL(@"settings.sponsorblock.haptic", @"Vibrate on skip"),
                    SGL(@"settings.sponsorblock.haptic_note", @"Uses Vibrations > Controls."), SGKeySponsorBlockHaptics),
        SGSwitchRow(SGL(@"settings.sponsorblock.markers", @"Show segments on the progress bar"), nil, SGKeySponsorBlockOverlay)
    ]);
    SGModSection *stats = SGSection(SGL(@"settings.sponsorblock.stats", @"Statistics"), @[
        SGSearchIdentified(SGStatRow(SGL(@"settings.sponsorblock.count", @"Segments skipped"),
            ^{ return @([store integerForKey:SGKeySponsorBlockCount]).stringValue; }), SGKeySponsorBlockCount),
        SGSearchIdentified(SGStatRow(SGL(@"settings.sponsorblock.saved", @"Time saved"),
            ^{ return [NSString stringWithFormat:SGL(@"settings.sponsorblock.seconds", @"%.0f s"), [store doubleForKey:SGKeySponsorBlockSaved]]; }), SGKeySponsorBlockSaved),
        SGSearchIdentified(SGActionRow(SGL(@"settings.sponsorblock.reset", @"Reset statistics"), nil,
            ^{ SGSponsorBlockResetStats(store); }), @"sponsorblock.reset")
    ]);
    SGModSection *privacy = SGNotedSection(nil, @[], privacyText());
    __weak SGModSection *weakPrivacy = privacy;
    privacy.rows = @[SGSearchIdentified(SGActionRow(SGL(@"settings.sponsorblock.server", @"SponsorBlock server"), nil,
        ^{ editServer(weakPrivacy); }), SGKeySponsorBlockServer)];
    return [[SGModPage alloc] initWithTitle:SGL(@"settings.sponsorblock.title", @"SponsorBlock") intro:SGRestartNote
        sections:@[SGSection(nil, @[enabled, categories]), rules, stats, privacy] footer:nil];
}

SGModSection *SGSponsorBlockSettingsSection(void) {
    return SGSection(nil, @[SGSearchIdentified(SGPageRow(SGL(@"settings.sponsorblock.title", @"SponsorBlock"),
        ^{ return settingsPage(); }), @"page.sponsorblock")]);
}

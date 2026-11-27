// Real settings factories and callbacks, with lightweight row/page and preference-store doubles.
#import "Settings/SGModPage.h"
#import "Core/SGPrefs.h"
#import "Core/SGLocalize.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Lyrics/PixieLyricsQueue.h"
#import "Settings/SGPageStyle.h"

NSDictionary<NSString *, NSNumber *> *SGPixieLyricsCounts(void) { return @{}; }
UIViewController *SGTopController(void) { return nil; }

@implementation SGModRow
@end
@implementation SGModSection
@end
@implementation SGPage
@end
@implementation SGModPage
- (instancetype)initWithTitle:(NSString *)title intro:(NSString *)intro sections:(NSArray *)sections footer:(NSString *)footer {
    if ((self = [super init])) _sections = sections;
    return self;
}
- (void)refreshVisibility {}
- (void)revealRowTitled:(NSString *)title {}
@end

NSString *SGL(NSString *key, NSString *english) { return english; }
BOOL SGFlag(NSString *key, BOOL fallback) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:key];
    return value ? [value boolValue] : fallback;
}
void SGSetEnabled(NSString *key, BOOL on) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSMutableDictionary *domain = [[defaults volatileDomainForName:NSArgumentDomain] mutableCopy];
    domain[key] = @(on);
    [defaults setVolatileDomain:domain forName:NSArgumentDomain];
}
SGModRow *SGOptionRow(NSString *title, NSString *subtitle, NSString *key) {
    SGModRow *row = [SGModRow new]; row.title = title; row.subtitle = subtitle; row.key = key; return row;
}
SGModRow *SGPageRow(NSString *title, UIViewController *(^page)(void)) {
    SGModRow *row = [SGModRow new]; row.title = title; row.page = page; return row;
}
SGModRow *SGMenuRow(NSString *title, NSArray<NSString *> *choices, NSString *(^value)(void), void (^chosen)(NSInteger)) {
    SGModRow *row = [SGModRow new]; row.title = title; row.menu = choices; row.value = value; row.chosen = chosen; return row;
}
SGModSection *SGSection(NSString *title, NSArray<SGModRow *> *rows) {
    SGModSection *section = [SGModSection new]; section.title = title; section.rows = rows; return section;
}

static NSUInteger failures;
static void check(BOOL ok, NSString *name) {
    if (ok) return;
    failures++;
    fprintf(stderr, "FAIL %s\n", name.UTF8String);
}
int main(void) {
    @autoreleasepool {
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{
            SGKeyLyricsRomanised:@NO, SGKeyLyricsJapaneseKana:@YES, SGKeyLyricsPronunciationHangul:@NO
        } forName:NSArgumentDomain];
        SGModRow *toggle = SGLyricsRomanisedRow();
        check([toggle.key isEqual:@"spotifyglass.lyricsRomanised"] && !toggle.defaultOn,
            @"Showing pronunciation retains the existing off-by-default switch");
        SGModRow *alphabet = SGLyricsAlphabetRow();
        SGModRow *japanese = SGLyricsJapaneseReadingRow();
        check([alphabet.value() isEqual:@"Latin"], @"Alphabet defaults to Latin");
        check([alphabet.waitsOn isEqual:@"spotifyglass.lyricsRomanised"], @"Choices wait for pronunciation");
        check([alphabet.menu isEqual:@[@"Latin", @"Hangul"]], @"Alphabet offers Latin and Hangul");
        check(!japanese.visible(), @"Japanese reading stays hidden while pronunciation is off");
        __block BOOL notified = NO;
        id observer = [NSNotificationCenter.defaultCenter addObserverForName:SGLyricsRomanisedDidChangeNotification
            object:nil queue:nil usingBlock:^(NSNotification *note) { notified = YES; }];
        alphabet.chosen(1);
        check(notified && [alphabet.value() isEqual:@"Hangul"] &&
              [SGLyricsRomanised(@"きって", YES) isEqual:@"킷테"],
            @"Picking Hangul immediately updates the reading and the menu");
        check(!SGFlag(SGKeyLyricsRomanised, YES), @"Choosing an alphabet never enables pronunciation");
        check(SGFlag(SGKeyLyricsJapaneseKana, NO), @"Hangul leaves the saved Japanese choice intact");
        notified = NO;
        alphabet.chosen(0);
        check(notified && [SGLyricsRomanised(@"君の名前を呼ぶ", YES) isEqual:@"きみのなまえをよぶ"],
            @"Returning to Latin restores the saved hiragana choice");
        notified = NO;
        japanese.chosen(0);
        check(notified && [SGLyricsRomanised(@"東京", YES) isEqual:@"toukyou"],
            @"Japanese reading still applies immediately");
        [NSNotificationCenter.defaultCenter removeObserver:observer];
        printf("%s: pronunciation settings callbacks (%lu failures)\n", failures ? "FAIL" : "PASS", (unsigned long)failures);
        return failures ? 1 : 0;
    }
}

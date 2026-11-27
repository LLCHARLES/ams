// Play counts In menu on Mac Catalyst: Redesigned/Album/AlbumPlaysMenu.x and AlbumRows.x, each compiled whole
// through Logos, against mocks of Spotify's ⋯ sheet and of an album's track cell. The count is a stub the steps set;
// each step lays the sheet out, posts the counts' change notification as AlbumPlays.m does, or sends a ⋯'s action as
// a tap or VoiceOver would, and checks what the table's header holds. Failures log and exit nonzero
// (harness-fail.h).
#import <UIKit/UIKit.h>
#import "Core/SGUIMode.h"
#import "Core/SGPrefs.h"
#import <objc/runtime.h>
#import "Settings/SGPageStyle.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Album/Album.h"
#import "Redesigned/Album/AlbumSpotifyCounts.h"
#import "Redesigned/Kit/SGRCoverRead.h"
#import "../harness-fail.h"

#pragma mark - stubs for what the files call

static NSUInteger sg_count;
NSNotificationName const SGRAlbumPlayCountsDidChangeNotification = @"SGRAlbumPlayCountsDidChange";
BOOL SGRedesignedUI(void) { return YES; }
static SGSpotifyMetadataReply sg_pendingMetadataReply;
static NSString *const sg_trackURI = @"spotify:track:0000000000000000000001";
dispatch_block_t SGSpotifyMetadataRequest(NSString *path, NSData *body, SGSpotifyMetadataReply done) {
    if (!SGRAlbumUsesSpotifyCounts()) HARNESS_FAIL(@"Spotify metadata reached from a personal-count fixture");
    if (body) {
        dispatch_async(dispatch_get_main_queue(), ^{ sg_pendingMetadataReply = done; });
    } else {
        NSData *json = [NSJSONSerialization dataWithJSONObject:@{@"disc": @[@{@"track":
            @[@{@"uri": sg_trackURI}, @{@"uri": @"spotify:track:0000000000000000000002"}]}]} options:0 error:nil];
        done(json, 200, nil);
    }
    return ^{ sg_pendingMetadataReply = nil; };
}
NSUInteger SGRAlbumPlayCount(NSString *album, NSString *title) {
    if (SGRAlbumUsesSpotifyCounts()) HARNESS_FAIL(@"personal title matching reached from a Spotify-count page");
    return [album isEqualToString:@"Hurry Up Tomorrow"] && [title isEqualToString:@"Cry For Me"] ? sg_count : 0;
}

// The existing model bridge's boundary: identity is carried by the page controller, never the labels.
@interface SGAlbumQueuePage : NSObject
+ (NSString *)albumURI:(UIViewController *)controller;
@end
@implementation SGAlbumQueuePage
+ (NSString *)albumURI:(UIViewController *)controller {
    return [controller.view.accessibilityIdentifier isEqual:@"harness.albumHost"] ? controller.view.accessibilityValue : nil;
}
@end

@interface NSFileManager (CountFixture)
- (NSArray<NSURL *> *)fixture_URLsForDirectory:(NSSearchPathDirectory)directory inDomains:(NSSearchPathDomainMask)domains;
@end
@implementation NSFileManager (CountFixture)
- (NSArray<NSURL *> *)fixture_URLsForDirectory:(NSSearchPathDirectory)directory inDomains:(NSSearchPathDomainMask)domains {
    if (directory == NSCachesDirectory) return @[[NSURL fileURLWithPath:@(getenv("ALBUM_COUNTS_CACHE"))]];
    return [self fixture_URLsForDirectory:directory inDomains:domains];
}
@end
// The Kit's, for AlbumRows.x: the mock marks a page and a track's content by identifier.
static NSString *const kPageID = @"harness.albumPage", *const kTrackID = @"harness.trackContent";
const CGFloat SGRSideMargin = 16;
UIColor *SGRSecondary(void) { return [UIColor colorWithWhite:1 alpha:0.65]; }
UIColor *SGRHairline(void) { return [UIColor colorWithWhite:1 alpha:0.15]; }
BOOL SGRIsTrackContent(UIView *content) { return [content.accessibilityIdentifier isEqualToString:kTrackID]; }
UIView *SGRAlbumPageOf(UIView *view) {
    for (UIView *v = view; v; v = v.superview) if ([v.accessibilityIdentifier isEqualToString:kPageID]) return v;
    return nil;
}
UIView *SGRFindByIdentifier(UIView *root, NSString *identifier, const void *cacheKey) {
    if (!root) return nil;
    BOOL prefix = [identifier hasSuffix:@"*"];
    NSString *stem = prefix ? [identifier substringToIndex:identifier.length - 1] : identifier;
    if (prefix ? [root.accessibilityIdentifier hasPrefix:stem] : [root.accessibilityIdentifier isEqualToString:stem]) return root;
    for (UIView *sub in root.subviews) {
        UIView *found = SGRFindByIdentifier(sub, identifier, cacheKey);
        if (found) return found;
    }
    return nil;
}
BOOL SGRCreditRepeatsAlbum(NSString *albumArtist, NSString *rowArtist, NSString *title) { return NO; }
UIFont *SGCategoryCappedFont(UIFontTextStyle style, UIFontWeight weight, UIContentSizeCategory largest) { return [UIFont preferredFontForTextStyle:style]; }
UIFont *SGMonospacedDigitsFont(UIFont *font) { return font; }
// AlbumRows.x's ⋯ in the page's colour: the mock page has no field, and nothing watches its glyphs.
UIColor *SGRAlbumFieldColor(UIView *view) { return nil; }
NSNotificationName const SGRFieldColorDidChangeNotification = @"SGRFieldColorDidChange";
BOOL SGRIncreaseContrast(void) { return NO; }
SGRLab SGRLabFromRGB(CGFloat red, CGFloat green, CGFloat blue) { return (SGRLab){0, 0, 0}; }
void SGRLabToRGB(SGRLab lab, CGFloat *red, CGFloat *green, CGFloat *blue) { *red = *green = *blue = 0; }
SGRLab SGRLabInSRGB(CGFloat L, CGFloat chroma, CGFloat hue) { return (SGRLab){L, 0, 0}; }
BOOL SGRObserveImage(UIImageView *view, void (^changed)(UIImageView *view)) { return NO; }
// Track numbers (the only layout observer AlbumRows.x asks for) stay off here.
BOOL SGRObserveLayout(UIView *view, void (^laidOut)(UIView *view)) { return NO; }

#pragma mark - an album's track cell

@interface _TtC12Element_List18CollectionViewCell : UICollectionViewCell @end
@implementation _TtC12Element_List18CollectionViewCell @end

// Spotify's action on a ⋯, which the sheet would follow.
@interface SGUIRefinementsSpotifyAction : NSObject
@property (nonatomic) NSUInteger fired;
- (void)fire;
@end
@implementation SGUIRefinementsSpotifyAction
- (void)fire { self.fired++; }
@end

#pragma mark - Spotify's sheet

@interface _TtC24ContextMenu_InternalImpl25ContextMenuViewController : UIViewController <UITableViewDataSource>
@property (nonatomic, strong) UITableView *table;
@end

@implementation _TtC24ContextMenu_InternalImpl25ContextMenuViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.dataSource = self;
    [self.view addSubview:self.table];
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return 3; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = @"Add to queue";
    return cell;
}
@end

#pragma mark - the steps

static NSUInteger sg_checks;

static void expect(BOOL ok, NSString *what) {
    sg_checks++;
    if (!ok) HARNESS_FAIL(@"%@", what);
}

static void checkPlacementMigration(void) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    NSDictionary *saved = [store volatileDomainForName:NSArgumentDomain];
    NSString *old = @"spotifyglass.redesign.album.playCounts", *place = @"spotifyglass.redesign.album.playCounts.place";
    NSArray *cases = @[
        @[@{}, @(SGRAlbumPlayCountsInRow)],
        @[@{old: @YES}, @(SGRAlbumPlayCountsInRow)],
        @[@{old: @NO}, @(SGRAlbumPlayCountsOff)],
        @[@{old: @NO, place: @2}, @(SGRAlbumPlayCountsInMenu)],
        @[@{old: @YES, place: @0}, @(SGRAlbumPlayCountsOff)],
        @[@{old: @NO, place: @1}, @(SGRAlbumPlayCountsInRow)],
        @[@{old: @NO, place: @7}, @(SGRAlbumPlayCountsOff)],
        @[@{old: @YES, place: @(-1)}, @(SGRAlbumPlayCountsInRow)],
        @[@{@"spotifyglass.stock": @YES}, @(SGRAlbumPlayCountsOff)]
    ];
    for (NSArray *fixture in cases) {
        [store setVolatileDomain:fixture[0] forName:NSArgumentDomain];
        SGPrefsChanged();
        expect(SGRAlbumPlayCountsWhere() == [fixture[1] integerValue], @"placement migration and stock reset");
    }
    [store setVolatileDomain:saved forName:NSArgumentDomain];
    SGPrefsChanged();
}

static void layOut(UIViewController *sheet) {
    [sheet.view setNeedsLayout];
    [sheet.view layoutIfNeeded];
}

static void countsChanged(NSUInteger count) {
    sg_count = count;
    [NSNotificationCenter.defaultCenter postNotificationName:SGRAlbumPlayCountsDidChangeNotification object:nil];
}

static UIView *header(_TtC24ContextMenu_InternalImpl25ContextMenuViewController *sheet) {
    return sheet.table.tableHeaderView;
}

static UILabel *labelIn(UIView *view) {
    for (UIView *sub in view.subviews) if ([sub isKindOfClass:UILabel.class]) return (UILabel *)sub;
    return nil;
}

// The line a sheet opened now shows, nil for none: whatever track the last ⋯ action marked.
static NSString *lineOfNewSheet(UIWindow *window) {
    _TtC24ContextMenu_InternalImpl25ContextMenuViewController *sheet = [_TtC24ContextMenu_InternalImpl25ContextMenuViewController new];
    window.rootViewController = sheet;
    layOut(sheet);
    return header(sheet).accessibilityLabel;
}

static void waitFor(BOOL (^ready)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:60];
    while (!ready() && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    expect(ready(), @"Spotify fixture completed before its deadline");
}
static BOOL showsSpotifyCount(UIView *view) {
    if ([view isKindOfClass:UILabel.class] && [((UILabel *)view).text isEqual:@"Spotify plays: 12,345"]) return YES;
    for (UIView *child in view.subviews) if (showsSpotifyCount(child)) return YES;
    return NO;
}
static void deliverSpotifyCount(void) {
    const uint8_t count[] = {0x18, 0xb9, 0x60};
    NSData *any = SGPBSerialize(@[SGPBString(1, @"fixture.PlayCount"), SGPBBytes(2, [NSData dataWithBytes:count length:sizeof(count)])]);
    NSData *entry = SGPBSerialize(@[SGPBString(2, sg_trackURI), SGPBBytes(1, SGPBSerialize(@[SGPBVarint(1, 200)])), SGPBBytes(3, any)]);
    NSData *reply = SGPBSerialize(@[SGPBBytes(2, SGPBSerialize(@[SGPBVarint(2, 185), SGPBBytes(3, entry)]))]);
    SGSpotifyMetadataReply done = sg_pendingMetadataReply;
    sg_pendingMetadataReply = nil;
    done(reply, 200, nil);
}

static void runSpotifyChecks(UIWindow *window, UIViewController *host, UIView *page, UIView *cell,
                             UILabel *title, UIControl *more, dispatch_block_t layoutCell) {
    BOOL inRow = SGRAlbumPlayCountsWhere() == SGRAlbumPlayCountsInRow;
    waitFor(^BOOL{ return sg_pendingMetadataReply != nil; });
    expect(!showsSpotifyCount(cell), @"loading Spotify count is unavailable on the row");
    _TtC24ContextMenu_InternalImpl25ContextMenuViewController *sheet;
    if (!inRow) {
        [more sendActionsForControlEvents:UIControlEventTouchUpInside];
        sheet = [_TtC24ContextMenu_InternalImpl25ContextMenuViewController new];
        window.rootViewController = sheet;
        layOut(sheet);
        expect(header(sheet) == nil, @"loading Spotify count is unavailable in menu");
    }
    deliverSpotifyCount();
    waitFor(^BOOL{
        if (inRow) { layoutCell(); return showsSpotifyCount(cell); }
        return [header(sheet).accessibilityLabel isEqual:@"Spotify plays: 12,345"];
    });
    expect(inRow || !showsSpotifyCount(cell), @"menu placement does not also put counts on the row");
    window.rootViewController = host;
    title.text = @"No title matching is possible";
    layoutCell();
    if (inRow) expect(showsSpotifyCount(cell), @"Spotify row count follows URI after title changes");
    else {
        [more sendActionsForControlEvents:UIControlEventTouchUpInside];
        expect([lineOfNewSheet(window) isEqual:@"Spotify plays: 12,345"], @"Spotify menu count follows the tapped row URI");
    }
    window.rootViewController = host;
    more.accessibilityIdentifier = @"Components.UI.ContextMenuButton-0000000000000000000002";
    layoutCell();
    if (inRow) expect(!showsSpotifyCount(cell), @"missing track count is not reused or fabricated as zero");
    else {
        [more sendActionsForControlEvents:UIControlEventTouchUpInside];
        expect(lineOfNewSheet(window) == nil, @"missing URI count stays absent from its menu");
    }
    window.rootViewController = host;
    more.accessibilityIdentifier = @"Components.UI.ContextMenuButton-0000000000000000000001";
    layoutCell();
    if (!inRow) {
        [more sendActionsForControlEvents:UIControlEventTouchUpInside];
        sheet = [_TtC24ContextMenu_InternalImpl25ContextMenuViewController new];
        window.rootViewController = sheet;
        layOut(sheet);
    }
    host.view.accessibilityValue = nil;
    SGRAlbumSetTitle(page, @"Hurry Up Tomorrow");
    layoutCell();
    expect(inRow ? !showsSpotifyCount(cell) : header(sheet) == nil, @"page identity loss clears the live Spotify count");
}

// AlbumRows.x's ⋯ watch: the track is marked from the ⋯'s action alone (no touch, as VoiceOver activates), and only
// while the ⋯ is still an album track row's; any other control's action leaves a mark as it was.
static void runActionChecks(UIWindow *window) {
    sg_count = 1234;
    UIViewController *host = [UIViewController new];
    host.view.accessibilityIdentifier = @"harness.albumHost";
    host.view.accessibilityValue = @"spotify:album:0000000000000000000001";
    UIView *page = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 400, 400)];
    page.accessibilityIdentifier = kPageID;
    [host.view addSubview:page];
    _TtC12Element_List18CollectionViewCell *cell = [[_TtC12Element_List18CollectionViewCell alloc] initWithFrame:CGRectMake(0, 0, 400, 56)];
    [page addSubview:cell];
    UIView *content = [[UIView alloc] initWithFrame:cell.contentView.bounds];
    content.accessibilityIdentifier = kTrackID;
    [cell.contentView addSubview:content];
    UIView *row = [[UIView alloc] initWithFrame:content.bounds];
    row.accessibilityIdentifier = @"Components.UI.RetrievalRowElementUI";
    [content addSubview:row];
    UIView *titleBox = [[UIView alloc] initWithFrame:CGRectMake(16, 8, 300, 18)];
    titleBox.accessibilityIdentifier = @"EncoreConsumerMobile.View.Granular.Title";
    UILabel *title = [[UILabel alloc] initWithFrame:titleBox.bounds];
    title.text = @"Cry For Me";
    [titleBox addSubview:title];
    [row addSubview:titleBox];
    UIControl *more = [[UIControl alloc] initWithFrame:CGRectMake(340, 4, 48, 48)];
    more.accessibilityIdentifier = @"Components.UI.ContextMenuButton-5673WA8EEUSPx1ir26lhGW";
    if (SGRAlbumUsesSpotifyCounts()) more.accessibilityIdentifier = @"Components.UI.ContextMenuButton-0000000000000000000001";
    SGUIRefinementsSpotifyAction *spotify = [SGUIRefinementsSpotifyAction new];
    [more addTarget:spotify action:@selector(fire) forControlEvents:UIControlEventTouchUpInside];
    [row addSubview:more];
    UIControl *other = [[UIControl alloc] initWithFrame:CGRectMake(0, 0, 44, 44)];
    [other addTarget:spotify action:@selector(fire) forControlEvents:UIControlEventTouchUpInside];
    [host.view addSubview:other];
    window.rootViewController = host;
    SGRAlbumSetTitle(page, @"Hurry Up Tomorrow");
    void (^layOutCell)(void) = ^{
        [cell setNeedsLayout];
        [cell layoutIfNeeded];
    };
    layOutCell();

    if (SGRAlbumUsesSpotifyCounts()) {
        runSpotifyChecks(window, host, page, cell, title, more, layOutCell);
        return;
    }

    // The album row's ⋯: its action marks the track for the sheet it opens.
    [more sendActionsForControlEvents:UIControlEventTouchUpInside];
    expect(spotify.fired == 1, @"Spotify's own action still runs");
    expect([lineOfNewSheet(window) isEqualToString:@"Your plays: 1,234"], @"the album row's ⋯ marks its track from its action");

    // The cell is reused for a row of no album, its title another: its old ⋯ marks nothing, before and after the
    // reused cell's layout, and the mark there was stays.
    window.rootViewController = host;
    [cell prepareForReuse];
    content.accessibilityIdentifier = nil;
    title.text = @"Other";
    SGRAlbumPlaysMarkMenu(@"Hurry Up Tomorrow", @"Cry For Me");
    [more sendActionsForControlEvents:UIControlEventTouchUpInside];
    layOutCell();
    [more sendActionsForControlEvents:UIControlEventTouchUpInside];
    expect([lineOfNewSheet(window) isEqualToString:@"Your plays: 1,234"], @"a ⋯ reused out of an album leaves the mark alone");

    // An album's track row again, then moved off the album page with no pass of its own since: the action checks
    // the row again rather than trusting its flag.
    window.rootViewController = host;
    content.accessibilityIdentifier = kTrackID;
    title.text = @"Cry For Me";
    layOutCell();
    [host.view addSubview:cell];
    title.text = @"Other";
    SGRAlbumPlaysMarkMenu(@"Hurry Up Tomorrow", @"Cry For Me");
    [more sendActionsForControlEvents:UIControlEventTouchUpInside];
    expect([lineOfNewSheet(window) isEqualToString:@"Your plays: 1,234"], @"a ⋯ no longer on an album page leaves the mark alone");

    // Any other control's action leaves the mark as it was.
    window.rootViewController = host;
    SGRAlbumPlaysMarkMenu(@"Hurry Up Tomorrow", @"Cry For Me");
    [other sendActionsForControlEvents:UIControlEventTouchUpInside];
    expect([lineOfNewSheet(window) isEqualToString:@"Your plays: 1,234"], @"an unflagged control leaves the mark alone");
}

static void run(UIWindow *window) {
    if (SGRAlbumUsesSpotifyCounts()) {
        runActionChecks(window);
        printf("ui-refinements Spotify %s: %lu checks passed\n", SGRAlbumPlayCountsWhere() == SGRAlbumPlayCountsInRow ? "row" : "menu", (unsigned long)sg_checks);
        fflush(stdout);
        exit(0);
    }
    // A sheet with no ⋯ action before it gets no line, whatever the count.
    sg_count = 7;
    _TtC24ContextMenu_InternalImpl25ContextMenuViewController *unmarked = [_TtC24ContextMenu_InternalImpl25ContextMenuViewController new];
    window.rootViewController = unmarked;
    layOut(unmarked);
    expect(header(unmarked) == nil, @"a sheet not opened from a row's ⋯ has no line");

    // The row's ⋯ sent its action; the log has not been read when the sheet first lays out.
    sg_count = 0;
    SGRAlbumPlaysMarkMenu(@"Hurry Up Tomorrow", @"Cry For Me");
    _TtC24ContextMenu_InternalImpl25ContextMenuViewController *sheet = [_TtC24ContextMenu_InternalImpl25ContextMenuViewController new];
    window.rootViewController = sheet;
    layOut(sheet);
    expect(header(sheet) == nil, @"no count yet, no line");

    // The counts arrive after the sheet's last pass: the notification alone brings the line.
    countsChanged(1234);
    UIView *line = header(sheet);
    expect([line.accessibilityLabel isEqualToString:@"Your plays: 1,234"], [NSString stringWithFormat:@"the line comes with the counts, got %@ %@", line.class, line.accessibilityLabel]);
    expect(!line.userInteractionEnabled && (line.accessibilityTraits & UIAccessibilityTraitStaticText) && !(line.accessibilityTraits & UIAccessibilityTraitButton),
           @"the line is static text, not a button");
    expect([labelIn(line).textColor isEqual:UIColor.secondaryLabelColor], @"the line's text is the secondary label color");

    // The line is as tall as its text. (Catalyst keeps one footnote size whatever the text size, so the growth at
    // accessibility sizes is looked at in the simulator's album harness instead.)
    [line layoutIfNeeded];
    UILabel *text = labelIn(line);
    CGFloat needed = ceil([text sizeThatFits:CGSizeMake(text.bounds.size.width, CGFLOAT_MAX)].height);
    expect(text.bounds.size.height >= needed, [NSString stringWithFormat:@"the text is whole: %.1f of %.1f", text.bounds.size.height, needed]);

    // The count goes (the log erased): so does the line, and it comes back with a count.
    countsChanged(0);
    expect(header(sheet) == nil, @"the line goes with the count");
    countsChanged(5);
    expect([header(sheet).accessibilityLabel isEqualToString:@"Your plays: 5"], @"the line comes back with a count");

    // Spotify puts a view of its own in the header: the line gives way, on the next pass and on the next change.
    UIView *spotify = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 300, 40)];
    sheet.table.tableHeaderView = spotify;
    layOut(sheet);
    expect(header(sheet) == spotify, @"a pass leaves Spotify's header in place");
    countsChanged(6);
    expect(header(sheet) == spotify, @"a change leaves Spotify's header in place");

    runActionChecks(window);

    printf("ui-refinements menu: %lu checks passed\n", (unsigned long)sg_checks);
    fflush(stdout);
    exit(0);
}

@interface SGUIRefinementsMenuScene : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation SGUIRefinementsMenuScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    [self.window makeKeyAndVisible];
    [NSTimer scheduledTimerWithTimeInterval:0 repeats:NO block:^(NSTimer *timer) { run(self.window); }];
}
@end

@interface SGUIRefinementsMenuApp : UIResponder <UIApplicationDelegate>
@end
@implementation SGUIRefinementsMenuApp
@end

int main(int argc, char *argv[]) {
    // A run that never reaches its end fails rather than hangs.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ HARNESS_FAIL(@"album menu checks did not finish"); });
    @autoreleasepool {
        checkPlacementMigration();
        method_exchangeImplementations(class_getInstanceMethod(NSFileManager.class, @selector(URLsForDirectory:inDomains:)),
                                       class_getInstanceMethod(NSFileManager.class, @selector(fixture_URLsForDirectory:inDomains:)));
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(SGUIRefinementsMenuApp.class));
    }
}

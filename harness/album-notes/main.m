#import "catalog-boundary.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Shared/AnimatedArtwork/SGMotionCatalog.h"
#import "Redesigned/Album/AlbumNotes.h"
#import <objc/runtime.h>
#import <objc/message.h>

@interface MockRetrievalListStructuredDataView : UIView @end
@implementation MockRetrievalListStructuredDataView @end

static NSInteger placement = 1;
static NSUInteger recomputations, pageWalks, batchWraps;
void SGRAlbumNotesTestDidRecompute(void) { recomputations++; }
void SGRAlbumNotesTestDidWrapBatch(void) { batchWraps++; }
NSInteger SGInt(NSString *key, NSInteger fallback) { return placement == -1 ? fallback : placement; }
NSString *SGL(NSString *key, NSString *english) { return english; }
UIColor *SGRSecondary(void) { return UIColor.grayColor; }
UIColor *SGRTertiary(void) { return UIColor.grayColor; }
BOOL SGRedesignedUI(void) { return YES; }
BOOL SGEnabled(NSString *key) { return YES; }
BOOL SGClassNamed(Class cls, NSString *name) { return [NSStringFromClass(cls) containsString:name]; }
void SGRRestoreCell(UICollectionViewCell *cell, const void *key) {
    objc_setAssociatedObject(cell, key, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
void SGPresentDark(UIViewController *controller) {}
@interface PresentRecorder : UIViewController
@property (nonatomic, strong) UIViewController *shown;
@end
@implementation PresentRecorder
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion {
    self.shown = controller;
}
@end
static PresentRecorder *presenter;
UIViewController *SGTopController(void) { return presenter; }
void SGForEachView(UIView *view, void (^visit)(UIView *)) {
    if (!view) return;
    visit(view);
    for (UIView *child in view.subviews) SGForEachView(child, visit);
}
NSString *SGRFirstLabelText(UIView *view) {
    if ([view isKindOfClass:UILabel.class]) return ((UILabel *)view).text;
    for (UIView *child in view.subviews) { NSString *text = SGRFirstLabelText(child); if (text.length) return text; }
    return nil;
}
UIView *SGRAlbumPageOf(UIView *view) {
    pageWalks++;
    while (view.superview) view = view.superview;
    return view;
}
UIView *SGRFindByIdentifier(UIView *view, NSString *identifier, const void *key) {
    if ([view.accessibilityIdentifier isEqual:identifier]) return view;
    for (UIView *sub in view.subviews) { UIView *found = SGRFindByIdentifier(sub, identifier, NULL); if (found) return found; }
    return nil;
}

// Spotify supplies each live cell's index path. The same eight cells can carry
// thirty tracks, exactly as recycling does on a long album.
@interface NotesCell : UICollectionViewCell
@property (nonatomic, strong) NSIndexPath *trackPath;
@end
@implementation NotesCell
- (void)layoutSubviews {
    [super layoutSubviews];
}
@end
@interface NotesCollection : UICollectionView
@property (nonatomic, copy) NSArray<NSNumber *> *snapshotCounts;
@property (nonatomic, strong) id receivedCompletion;
@end
@implementation NotesCollection
- (NSIndexPath *)indexPathForCell:(UICollectionViewCell *)cell { return ((NotesCell *)cell).trackPath; }
- (NSInteger)numberOfSections { return self.snapshotCounts.count; }
- (NSInteger)numberOfItemsInSection:(NSInteger)section { return [self.snapshotCounts[section] integerValue]; }
- (void)layoutSubviews {}
- (void)reloadData {}
- (void)reloadItemsAtIndexPaths:(NSArray<NSIndexPath *> *)paths {}
- (void)reloadSections:(NSIndexSet *)sections {}
- (void)performBatchUpdates:(void (NS_NOESCAPE ^)(void))updates completion:(void (^)(BOOL))completion {
    self.receivedCompletion = completion;
    if (updates) updates();
    if (completion) completion(YES);
}
@end

@interface NotesPage : NSObject
@property (nonatomic, strong) UIView *page, *header;
@property (nonatomic, strong) UIStackView *stack;
@property (nonatomic, strong) NotesCollection *list;
@property (nonatomic, strong) NotesCell *footer;
@property (nonatomic, strong) UILabel *count;
@end
@implementation NotesPage @end

static NotesPage *makePage(NSUInteger count) {
    NotesPage *fixture = [NotesPage new];
    fixture.page = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 390, 800)];
    fixture.stack = [[UIStackView alloc] initWithFrame:fixture.page.bounds];
    fixture.stack.axis = UILayoutConstraintAxisVertical;
    [fixture.page addSubview:fixture.stack];
    fixture.header = [UIView new];
    [fixture.stack addArrangedSubview:fixture.header];
    UILabel *metadata = [UILabel new];
    metadata.accessibilityIdentifier = @"Components.UI.MetadataRow";
    metadata.text = @"앨범 • 31. 1. 2025";
    [fixture.header addSubview:metadata];
    fixture.list = [[NotesCollection alloc] initWithFrame:CGRectMake(0, 0, 390, 400)
        collectionViewLayout:[UICollectionViewFlowLayout new]];
    fixture.list.snapshotCounts = @[@(count)];
    [fixture.stack addArrangedSubview:fixture.list];
    fixture.footer = [[NotesCell alloc] initWithFrame:CGRectMake(0, 0, 390, 44)];
    [fixture.list addSubview:fixture.footer];
    fixture.count = [UILabel new];
    fixture.count.accessibilityIdentifier = @"Album.ConsumptionExperience";
    fixture.count.text = [NSString stringWithFormat:@"%lu곡 • 1시간 24분", (unsigned long)count];
    [fixture.footer.contentView addSubview:fixture.count];
    SGRAlbumNotesUpdate(fixture.header, fixture.page, @"Fixture Echo", @"Signals");
    [fixture.footer layoutSubviews];
    return fixture;
}
static NotesCell *slot(NotesPage *fixture) {
    NotesCell *cell = [[NotesCell alloc] initWithFrame:CGRectMake(0, 0, 390, 56)];
    [fixture.list addSubview:cell];
    return cell;
}
static void showTrackAt(NotesCell *cell, NSUInteger section, NSUInteger index, NSString *title, NSString *badgeIdentifier) {
    cell.trackPath = [NSIndexPath indexPathForItem:index inSection:section];
    for (UIView *old in cell.contentView.subviews) [old removeFromSuperview];
    UIView *payload = [MockRetrievalListStructuredDataView new];
    [cell.contentView addSubview:payload];
    UIView *row = [UIView new];
    row.accessibilityIdentifier = @"Components.UI.RetrievalRowElementUI_Loaded";
    [payload addSubview:row];
    UILabel *label = [UILabel new];
    label.accessibilityIdentifier = @"EncoreConsumerMobile.View.Granular.Title";
    label.text = title;
    [row addSubview:label];
    if (badgeIdentifier) {
        UIView *badge = [UIView new];
        badge.accessibilityIdentifier = badgeIdentifier;
        [row addSubview:badge];
    }
    [cell layoutSubviews];
}
static void showTrack(NotesCell *cell, NSUInteger index, NSString *title, NSString *badgeIdentifier) {
    showTrackAt(cell, 0, index, title, badgeIdentifier);
}

static Class deviceClass(NSString *name, Class base) {
    Class cls = NSClassFromString(name);
    if (!cls) { cls = objc_allocateClassPair(base, name.UTF8String, 0); objc_registerClassPair(cls); }
    return cls;
}

// Structure recorded on Korean 9.1.90: the loaded TitleView has no Granular
// identifier; its label and explicit badge remain evidence even when dimmed.
static void showDeviceTrack(NotesCell *cell) {
    object_setClass(cell, deviceClass(@"_TtC12Element_List18CollectionViewCell", NotesCell.class));
    cell.trackPath = [NSIndexPath indexPathForItem:5 inSection:0];
    UIView *payload = [deviceClass(@"_TtGC13Element_UIKit18ElementContentViewV12Element_List14ItemIdentifierGCS_14AnyBaseElementOC28CreativeWorkPlatform_PageKit24CreativeWorkTemplateViewP10$10acf475c27RetrievalListStructuredDataOS_9NeedsData__", UIView.class) new];
    [cell.contentView addSubview:payload];
    UIView *row = [deviceClass(@"_TtGC27ListUXPlatform_ListSwipeKit9SwipeViewOV36CreativeWorkPlatform_RetrievalRowKit19RetrievalRowElement5Event_", UIView.class) new];
    row.accessibilityIdentifier = @"Components.UI.RetrievalRowElementUI_Loaded";
    [payload addSubview:row];
    UIView *title = [deviceClass(@"_TtCC36CreativeWorkPlatform_RetrievalRowKit21RetrievalRowElementUI9TitleView", UIView.class) new];
    [row addSubview:title];
    UIView *encore = [deviceClass(@"SPTEncoreLabel", UIView.class) new];
    encore.accessibilityIdentifier = @"Encore.Label";
    [title addSubview:encore];
    UILabel *text = [UILabel new];
    text.accessibilityIdentifier = @"Encore.Label-internal";
    text.text = @"Escape From LA";
    text.alpha = .30;
    [encore addSubview:text];
    UIView *badges = [deviceClass(@"_TtCC36CreativeWorkPlatform_RetrievalRowKit21RetrievalRowElementUI10BadgesView", UIView.class) new];
    badges.alpha = .30;
    [row addSubview:badges];
    UIView *badge = [deviceClass(@"_TtCCC36CreativeWorkPlatform_RetrievalRowKit21RetrievalRowElementUI10BadgesViewP33_9D5FF3EB21C9757CC8B47C2445B48C7B17NineteenPlusBadge", UIView.class) new];
    badge.accessibilityIdentifier = @"Components.UI.19andOverIcon";
    [badges addSubview:badge];
    UILabel *artist = [UILabel new];
    artist.accessibilityIdentifier = @"RetrievalRowElementUI.Subtitle.Label";
    artist.text = @"The Weeknd";
    [row addSubview:artist];
    [cell layoutSubviews];
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        CHECK(argc == 2);
        CatalogStart(@(argv[1]));
        CHECK(([@{@"album\n4\nthe weeknd\nafter hours":
            @{@"url": @"https://fixture.invalid/after-hours/clip.mp4", @"at": NSDate.date}}
            writeToURL:SGMotionTestAlbumAnswersFile() atomically:YES]));
        NSArray *records = CatalogFixture[@"results"][@"albums"][@"data"];
        NSDictionary *edition = @{@"trackCount": @22, @"releaseYear": @2025, @"explicit": @YES};
        NSDictionary *deluxe = @{@"trackCount": @26, @"releaseYear": @2025, @"explicit": @YES};
        NSDictionary *notes = SGMotionAlbumNotesIn(records, @"Fixture Echo", @"Signals", edition);
        CHECK([notes[@"short"] isEqual:@"Bright & spare.\n\nA second paragraph."]);
        CHECK([notes[@"standard"] isEqual:@"A full account of the record.\n\n“Signals” — in detail.\n\nAnother line."]);
        CHECK([SGMotionAlbumNotesIn(records, @"Fixture Echo", @"Signals (Deluxe)", deluxe)[@"short"] isEqual:@"The expanded edition."]);
        CHECK(SGMotionAlbumNotesIn(records, @"Fixture Echo", @"Signals (Remastered)", edition) == nil);
        CHECK(SGMotionAlbumNotesIn(records, @"Someone Else", @"Signals", edition) == nil);
        CHECK(SGMotionAlbumNotesIn([records arrayByAddingObject:records[0]], @"Fixture Echo", @"Signals", edition) == nil);
        CHECK(SGMotionAlbumNotesIn(records, @"Fixture Echo", @"Quiet", edition) == nil);
        CHECK(SGMotionAlbumNotesIn(records, @"Fixture Echo", @"Signals", @{}) == nil);
        CHECK(SGMotionAlbumNotesIn(records, @"Fixture Echo", @"Signals", @{@"trackCount": @26}) == nil);
        CHECK(SGMotionAlbumNotesIn(records, @"Fixture Echo", @"Signals", @{@"trackCount": @22, @"releaseYear": @2024}) == nil);
        CHECK(SGMotionAlbumNotesIn(records, @"Fixture Echo", @"Signals", @{@"releaseYear": @2025, @"explicit": @NO}) == nil);
        CHECK(SGMotionAlbumNotesIn(records, @"Fixture Echo", @"Signals", @{@"releaseYear": @2025}) == nil);
        CHECK(SGMotionAlbumNotesIn(records, @"Fixture Echo", @"Signals", @{@"trackCount": @22}) == nil);
        CHECK(SGMotionAlbumNotesIn(records, @"Fixture Echo", @"Signals", @{@"trackCount": @22, @"releaseYear": @2025}) == nil);
        CHECK(SGMotionAlbumNotesIn(@[records[0]], @"Fixture Echo", @"Signals", @{@"trackCount": @22, @"releaseYear": @2025}) == nil);
        CHECK(SGMotionAlbumNotesIn(records, @"Fixture Echo", @"Signals", @{@"trackCount": @22, @"releaseYear": @2025, @"explicit": @NO}) == nil);
        CHECK([SGMotionEditorialText(@"<p>&lt;b&gt; &#x1F3B5; &quot;music&quot;</p><script>bad()</script><p>Next&nbsp;line</p>")
               isEqual:@"<b> 🎵 \"music\"\n\nNext line"]);
        CHECK(SGMotionEditorialText(NSNull.null) == nil);
        CHECK(SGMotionEditorialText([@"x" stringByPaddingToLength:65537 withString:@"x" startingAtIndex:0]) == nil);

        placement = -1; CHECK(SGRAlbumNotesWhere() == SGRAlbumNotesUnderTracks);
        placement = 0; CHECK(SGRAlbumNotesWhere() == SGRAlbumNotesUnderPlay);
        placement = 1; CHECK(SGRAlbumNotesWhere() == SGRAlbumNotesUnderTracks);
        placement = 2; CHECK(SGRAlbumNotesWhere() == SGRAlbumNotesOff);
        placement = 42; CHECK(SGRAlbumNotesWhere() == SGRAlbumNotesUnderTracks);
        placement = 1;

        __block NSUInteger done = 0;
        // Only Deluxe has a unique title. The two plain Signals releases cannot be
        // distinguished by the presence of motion, but their notes have edition facts.
        SGMotionAlbumCover(@"Fixture Echo", @"Signals (Deluxe)", 720, ^(NSURL *file) {
            CHECK([file.path isEqual:@"/fixture/clip.mp4"]); done++;
        });
        SGMotionAlbumNotes(@"Fixture Echo", @"Signals", edition, ^(NSDictionary *value) {
            CHECK([value[@"short"] isEqual:@"Bright & spare.\n\nA second paragraph."]); done++;
        });
        CatalogWait(^BOOL { return done == 2; });
        CHECK(CatalogSearches == 1);
        __block BOOL ambiguous = NO;
        SGMotionAlbumCover(@"Fixture Echo", @"Signals", 720, ^(NSURL *file) {
            CHECK(file == nil); ambiguous = YES;
        });
        CatalogWait(^BOOL { return ambiguous; });
        SGMotionAlbumNotes(@"Fixture Echo", @"Signals (Deluxe)", deluxe, ^(NSDictionary *value) {
            CHECK([value[@"short"] isEqual:@"The expanded edition."]); done++;
        });
        CHECK(done == 3 && CatalogSearches == 1);

        // The production Logos hooks, not a duplicate implementation, run on
        // these fixture classes. Unowned collections must forward unchanged.
        NotesCollection *unrelated = [[NotesCollection alloc] initWithFrame:CGRectZero
            collectionViewLayout:[UICollectionViewFlowLayout new]];
        CHECK(objc_getAssociatedObject(unrelated, &SGRAlbumNotesCollectionOwnerKey) == nil);
        __block BOOL updatesRan = NO, completionRan = NO;
        void (^completion)(BOOL) = ^(BOOL finished) { completionRan = finished; };
        pageWalks = batchWraps = 0;
        [unrelated layoutSubviews];
        [unrelated reloadData];
        [unrelated performBatchUpdates:^{ updatesRan = YES; } completion:completion];
        CHECK(pageWalks == 0 && batchWraps == 0);
        CHECK(updatesRan && completionRan && unrelated.receivedCompletion == completion);

        NotesPage *longAlbum = makePage(30);
        NSMutableArray<NotesCell *> *slots = [NSMutableArray array];
        for (NSUInteger index = 0; index < 8; index++) [slots addObject:slot(longAlbum)];
        for (NSUInteger index = 0; index < 30; index++) {
            showTrack(slots[index % 8], index, [NSString stringWithFormat:@"Track %lu", (unsigned long)index], nil);
            if (index < 29) CHECK(SGRAlbumNotesEdition(longAlbum.page)[@"explicit"] == nil);
        }
        CHECK([SGRAlbumNotesEdition(longAlbum.page)[@"explicit"] isEqual:@NO]);
        NSUInteger before = recomputations;
        for (NSUInteger index = 0; index < 100; index++) [slots[index % 8] layoutSubviews];
        CHECK(recomputations == before);
        // A title replacement at a known path invalidates the whole snapshot,
        // even without a reload notification or item-count change.
        showTrack(slots[0], 0, @"Replacement", nil);
        CHECK(SGRAlbumNotesEdition(longAlbum.page)[@"explicit"] == nil);
        [longAlbum.footer layoutSubviews];
        showTrack(slots[1], 1, @"Track 1", nil);
        CHECK(SGRAlbumNotesEdition(longAlbum.page)[@"explicit"] == nil);

        // Inserting a disc header shifts C into a previously unseen index.
        // Without snapshot invalidation, old A/B/C plus shifted C falsely cover
        // all four tracks before the explicit D has ever been seen.
        NotesPage *shifted = makePage(4);
        NotesCell *shiftSlot = slot(shifted);
        showTrack(shiftSlot, 0, @"A", nil);
        showTrack(shiftSlot, 1, @"B", nil);
        showTrack(shiftSlot, 2, @"C", nil);
        shifted.list.snapshotCounts = @[@5];
        [shifted.list layoutSubviews];
        [shifted.footer layoutSubviews];
        showTrack(shiftSlot, 3, @"C", nil);
        CHECK(SGRAlbumNotesEdition(shifted.page)[@"explicit"] == nil);
        showTrack(shiftSlot, 0, @"A", nil);
        showTrack(shiftSlot, 2, @"B", nil);
        CHECK(SGRAlbumNotesEdition(shifted.page)[@"explicit"] == nil);
        showTrack(shiftSlot, 4, @"D", @"Components.UI.19andOverIcon");
        CHECK([SGRAlbumNotesEdition(shifted.page)[@"explicit"] isEqual:@YES]);

        NotesPage *discs = makePage(6);
        discs.list.snapshotCounts = @[@5, @6]; // headers and gaps are not tracks
        NotesCell *discSlot = slot(discs);
        showTrackAt(discSlot, 0, 1, @"Disc 1 A", nil);
        showTrackAt(discSlot, 0, 3, @"Disc 1 B", nil);
        showTrackAt(discSlot, 0, 4, @"Disc 1 C", nil);
        showTrackAt(discSlot, 1, 1, @"Disc 2 A", nil);
        showTrackAt(discSlot, 1, 3, @"Disc 2 B", nil);
        CHECK(SGRAlbumNotesEdition(discs.page)[@"explicit"] == nil);
        showTrackAt(discSlot, 1, 5, @"Disc 2 C", nil);
        CHECK([SGRAlbumNotesEdition(discs.page)[@"explicit"] isEqual:@NO]);

        NotesPage *reloaded = makePage(2);
        NotesCell *reloadSlot = slot(reloaded);
        showTrack(reloadSlot, 0, @"Old A", nil);
        showTrack(reloadSlot, 1, @"Old B", nil);
        CHECK([SGRAlbumNotesEdition(reloaded.page)[@"explicit"] isEqual:@NO]);
        CHECK(objc_getAssociatedObject(reloaded.list, &SGRAlbumNotesCollectionOwnerKey) != nil);
        pageWalks = batchWraps = 0;
        [reloaded.list reloadData]; // same counts, new titles
        CHECK(SGRAlbumNotesEdition(reloaded.page)[@"explicit"] == nil);
        CHECK(pageWalks == 0);
        [reloaded.footer layoutSubviews];
        showTrack(reloadSlot, 0, @"New A", nil);
        CHECK(SGRAlbumNotesEdition(reloaded.page)[@"explicit"] == nil);
        showTrack(reloadSlot, 1, @"New B", @"Components.UI.19andOverIcon");
        CHECK([SGRAlbumNotesEdition(reloaded.page)[@"explicit"] isEqual:@YES]);
        pageWalks = batchWraps = 0;
        [reloaded.list performBatchUpdates:nil completion:nil];
        CHECK([SGRAlbumNotesEdition(reloaded.page)[@"explicit"] isEqual:@YES]);
        CHECK(pageWalks == 0 && batchWraps == 1);
        [reloaded.list performBatchUpdates:^{
            [reloaded.list reloadItemsAtIndexPaths:@[[NSIndexPath indexPathForItem:0 inSection:0]]];
        } completion:nil];
        CHECK(SGRAlbumNotesEdition(reloaded.page)[@"explicit"] == nil);
        puts("album notes: real collection hooks: unrelated 0 walks / 0 wraps; reload and targeted track batches invalidate, no-op batches preserve evidence");

        NotesPage *loading = makePage(14);
        loading.list.snapshotCounts = @[@1, @14, @4];
        NotesCell *loadingSlot = slot(loading);
        showTrackAt(loadingSlot, 1, 0, @"Alone Again", @"Components.UI.19andOverIcon");
        [loading.list reloadData]; // Spotify starts a new lazy-loaded track snapshot
        CHECK(SGRAlbumNotesEdition(loading.page)[@"trackCount"] == nil);
        showTrackAt(loadingSlot, 1, 0, @"Alone Again", @"Components.UI.19andOverIcon");
        CHECK([SGRAlbumNotesEdition(loading.page)[@"explicit"] isEqual:@YES]);
        // Header/footer counts change without changing any track index.
        loading.list.snapshotCounts = @[@2, @14, @99];
        [loading.list layoutSubviews];
        CHECK([SGRAlbumNotesEdition(loading.page)[@"explicit"] isEqual:@YES]);
        [loading.list performBatchUpdates:^{
            [loading.list reloadSections:[NSIndexSet indexSetWithIndex:0]];
            loading.list.snapshotCounts = @[@2, @14, @3];
            [loading.list reloadSections:[NSIndexSet indexSetWithIndex:2]];
        } completion:nil];
        CHECK([SGRAlbumNotesEdition(loading.page)[@"explicit"] isEqual:@YES]);
        loading.count.text = @"곡 14개 • 56분";
        [loading.footer layoutSubviews];
        CHECK([SGRAlbumNotesEdition(loading.page)[@"trackCount"] isEqual:@14]);
        CHECK([SGRAlbumNotesEdition(loading.page)[@"explicit"] isEqual:@YES]);
        puts("album notes: lazy snapshot + explicit row + non-track signature/batch changes + unknown-to-14 count ends explicit");

        NotesPage *cleanPage = makePage(26);
        NotesCell *cleanSlot = slot(cleanPage);
        for (NSUInteger index = 0; index < 25; index++)
            showTrack(cleanSlot, index, [NSString stringWithFormat:@"Track %lu", (unsigned long)index], nil);
        NSDictionary *partial = SGRAlbumNotesEdition(cleanPage.page);
        CHECK(partial[@"explicit"] == nil);
        CHECK(SGMotionAlbumNotesIn(records, @"Fixture Echo", @"Signals", partial) == nil);
        showTrack(cleanSlot, 25, @"Last track", nil);
        NSDictionary *clean = SGRAlbumNotesEdition(cleanPage.page);
        CHECK([SGMotionAlbumNotesIn(records, @"Fixture Echo", @"Signals", clean)[@"short"] isEqual:@"The clean alternate."]);
        NSMutableDictionary *unrated = [records[2] mutableCopy];
        NSMutableDictionary *unratedAttributes = [unrated[@"attributes"] mutableCopy];
        [unratedAttributes removeObjectForKey:@"contentRating"];
        unrated[@"attributes"] = unratedAttributes;
        CHECK([SGMotionAlbumNotesIn(@[unrated], @"Fixture Echo", @"Signals", clean)[@"short"] isEqual:@"The clean alternate."]);

        placement = 0;
        NotesPage *fixture = makePage(22);
        NotesCell *track = slot(fixture);
        showTrack(track, 0, @"First", @"Components.UI.19andOverIcon");
        CHECK([SGRAlbumNotesEdition(fixture.page) isEqual:edition]);
        CHECK(fixture.stack.arrangedSubviews.count == 3);
        SGRAlbumNoteView *note = (SGRAlbumNoteView *)fixture.stack.arrangedSubviews[1];
        CHECK([note isKindOfClass:SGRAlbumNoteView.class]);
        CHECK(note.isAccessibilityElement && (note.accessibilityTraits & UIAccessibilityTraitButton));
        // The explicit row goes offscreen and its cell now draws a clean track.
        showTrack(track, 1, @"Second", nil);
        CHECK([SGRAlbumNotesEdition(fixture.page)[@"explicit"] isEqual:@YES]);
        CHECK(fixture.stack.arrangedSubviews[1] == note && note.notes != nil);
        // A tap on the note presents the full note over the page, not only styles it. The harness has no
        // UIApplication to deliver a control's actions, so the tap's registered action is called directly.
        presenter = [PresentRecorder new];
        NSArray<NSString *> *tapActions = [note actionsForTarget:note forControlEvent:UIControlEventTouchUpInside];
        CHECK(tapActions.count == 1);
        ((void (*)(id, SEL))objc_msgSend)(note, NSSelectorFromString(tapActions.firstObject));
        CHECK([presenter.shown isKindOfClass:UINavigationController.class]);
        fixture.count.text = @"26곡 • 1시간 34분";
        [fixture.footer layoutSubviews];
        CHECK(fixture.stack.arrangedSubviews.count == 2);
        fixture.count.text = @"22곡 • 1시간 24분";
        [fixture.footer layoutSubviews];
        CHECK(fixture.stack.arrangedSubviews.count == 3);
        CHECK(CatalogSearches == 1);
        SGRAlbumNotesUpdate(fixture.header, fixture.page, @"Fixture Echo", @"Signals (Remastered)");
        CHECK(SGRAlbumNotesEdition(fixture.page)[@"explicit"] == nil);
        CHECK(fixture.stack.arrangedSubviews.count == 2);
        placement = 1;
        SGRAlbumNotesUpdate(fixture.header, fixture.page, @"Fixture Echo", @"Signals");
        [fixture.footer layoutSubviews];
        showTrack(track, 0, @"First", @"Components.UI.19andOverIcon");
        NotesCell *footer = slot(fixture);
        UILabel *copyright = [UILabel new];
        copyright.accessibilityIdentifier = @"Album.Copyright";
        [footer.contentView addSubview:copyright];
        CHECK(SGRAlbumNotesFooterHeight(footer, 390) > 0);
        CHECK(fixture.stack.arrangedSubviews.count == 2);
        UIView *footerNote = footer.subviews.lastObject;
        UIView *overlay = [UIView new];
        [footer addSubview:overlay];
        CHECK(SGRAlbumNotesFooterHeight(footer, 390) > 0 && footer.subviews.lastObject == overlay);
        copyright.accessibilityIdentifier = @"Album.ConsumptionExperience";
        CHECK(SGRAlbumNotesFooterHeight(footer, 390) == 0 && footerNote.superview == nil);
        placement = 2;
        CHECK(SGRAlbumNotesFooterHeight(footer, 390) == 0);

        // Device facts: Korean Spotify 9.1.90 prefixes the count's unit.
        // Editorial copy is synthetic; only identity/count/date/rating model
        // the reported After Hours page. Header metadata uses the same date.
        placement = 0;
        NSUInteger searchesBeforeAfterHours = CatalogSearches;
        __block BOOL cachedCover = NO;
        SGMotionAlbumCover(@"The Weeknd", @"After Hours", 720, ^(NSURL *file) {
            CHECK([file.path isEqual:@"/fixture/clip.mp4"]); cachedCover = YES;
        });
        CHECK(cachedCover && CatalogSearches == searchesBeforeAfterHours);
        NotesPage *afterHours = makePage(14);
        object_setClass(afterHours.list, deviceClass(@"_TtC32CreativeWorkPlatform_TemplateKitP33_5F894CA2C02A3F3767683E90D6AA015014CollectionView", NotesCollection.class));
        ((UILabel *)SGRFindByIdentifier(afterHours.header, @"Components.UI.MetadataRow", NULL)).text = @"앨범 • 2020년 3월 20일";
        SGRAlbumNotesUpdate(afterHours.header, afterHours.page, @"The Weeknd", @"After Hours");
        afterHours.count.text = @"곡 14개 • 56분";
        [afterHours.footer layoutSubviews];
        showDeviceTrack(slot(afterHours));
        CHECK(objc_getAssociatedObject(afterHours.list, &SGRAlbumNotesCollectionOwnerKey) != nil);
        CHECK(([SGRAlbumNotesEdition(afterHours.page) isEqual:@{@"trackCount": @14, @"releaseYear": @2020, @"explicit": @YES}]));
        CatalogWait(^BOOL { return afterHours.stack.arrangedSubviews.count == 3; });
        CHECK(CatalogSearches == searchesBeforeAfterHours + 1);
        SGRAlbumNoteView *afterHoursNote = (SGRAlbumNoteView *)afterHours.stack.arrangedSubviews[1];
        CHECK([afterHoursNote.notes[@"short"] isEqual:@"Fixture note for the device album."]);
        placement = 1;
        NotesCell *afterHoursCopyright = slot(afterHours);
        UILabel *afterHoursLabel = [UILabel new];
        afterHoursLabel.accessibilityIdentifier = @"Album.Copyright";
        [afterHoursCopyright.contentView addSubview:afterHoursLabel];
        CHECK(SGRAlbumNotesFooterHeight(afterHoursCopyright, 390) > 0);

        SGMotionAlbumNotes(@"Fixture Echo", @"Quiet", edition, ^(NSDictionary *value) { CHECK(value == nil); done++; });
        CatalogWait(^BOOL { return done == 4; });
        CatalogStatus = 503;
        SGMotionAlbumNotes(@"Fixture Echo", @"Offline", edition, ^(NSDictionary *value) { CHECK(value == nil); done++; });
        CatalogWait(^BOOL { return done == 5; });
        CatalogWait(^BOOL {
            NSDictionary *saved = [NSDictionary dictionaryWithContentsOfURL:SGMotionTestAlbumAnswersFile()];
            return saved[@"album-records\nfixture echo\nquiet"] != nil;
        });
        CatalogFinish();
        puts("album notes: insertion shifts, multi-disc gaps, same-count reload/batch and changed-title snapshot invalidation passed");
        puts("album notes: 30 tracks / 8 recycled cells become clean; offscreen explicit persists; 100 unchanged layouts / 0 recomputations passed");
        puts("album notes: catalog, rating, edition, placement, HTML, shared request and offline checks passed");
        puts("album notes: After Hours Korean prefix count/date, explicit badge, cached-cover-only metadata lookup and both placements passed");
    }
    return 0;
}

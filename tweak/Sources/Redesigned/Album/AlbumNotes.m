#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "Shared/AnimatedArtwork/SGMotionCatalog.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Album.h"
#import "AlbumNotes.h"

static const CGFloat kSide = 20, kVertical = 12;
static char kNotesKey, kFooterNoteKey;
char SGRAlbumNotesCollectionOwnerKey;

SGRAlbumNotesPlace SGRAlbumNotesWhere(void) {
    NSInteger place = SGInt(SGRKeyAlbumNotesPlace, SGRAlbumNotesUnderTracks);
    return place >= SGRAlbumNotesUnderPlay && place <= SGRAlbumNotesOff ? place : SGRAlbumNotesUnderTracks;
}

@interface SGRAlbumNoteSheet : UIViewController
@property (nonatomic, copy) NSString *text;
@end
@implementation SGRAlbumNoteSheet
- (void)loadView {
    UITextView *text = [UITextView new];
    text.editable = NO;
    text.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    text.adjustsFontForContentSizeCategory = YES;
    text.textColor = UIColor.labelColor;
    text.backgroundColor = UIColor.systemBackgroundColor;
    text.textContainerInset = UIEdgeInsetsMake(20, 16, 24, 16);
    text.text = self.text;
    self.view = text;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.title = SGL(@"settings.album.notes.title", @"Album notes");
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
        target:self action:@selector(close)];
}
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
@end

@implementation SGRAlbumNoteView {
    UILabel *_label;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _label = [UILabel new];
    _label.numberOfLines = 0;
    _label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    _label.adjustsFontForContentSizeCategory = YES;
    _label.textColor = SGRSecondary();
    [self addSubview:_label];
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    self.accessibilityHint = SGL(@"settings.album.notes.open", @"Read the full album note");
    [self addTarget:self action:@selector(openNote) forControlEvents:UIControlEventTouchUpInside];
    return self;
}
- (void)setNotes:(NSDictionary *)notes {
    _notes = [notes copy];
    _label.text = notes[@"short"];
    self.accessibilityLabel = _label.text;
    [self invalidateIntrinsicContentSize];
    [self setNeedsLayout];
}
- (CGFloat)heightForWidth:(CGFloat)width {
    if (!_notes || width <= 2 * kSide) return 0;
    return ceil([_label sizeThatFits:CGSizeMake(width - 2 * kSide, CGFLOAT_MAX)].height) + 2 * kVertical;
}
- (CGSize)intrinsicContentSize {
    return CGSizeMake(UIViewNoIntrinsicMetric, [self heightForWidth:self.superview.bounds.size.width]);
}
- (void)layoutSubviews {
    [super layoutSubviews];
    _label.frame = CGRectInset(self.bounds, kSide, kVertical);
}
- (void)openNote {
    if (![_notes[@"standard"] length]) return;
    SGRAlbumNoteSheet *sheet = [SGRAlbumNoteSheet new];
    sheet.text = _notes[@"standard"];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:sheet];
    navigation.modalPresentationStyle = UIModalPresentationPageSheet;
    navigation.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.mediumDetent,
                                                       UISheetPresentationControllerDetent.largeDetent];
    SGPresentDark(navigation);
    [SGTopController() presentViewController:navigation animated:YES completion:nil];
}
@end

@interface SGRAlbumNotesState : NSObject
@property (nonatomic, copy) NSString *identity;
@property (nonatomic, copy) NSString *artist, *album;
@property (nonatomic, weak) UIView *header;
@property (nonatomic, weak) UIView *page;
@property (nonatomic, copy) NSDictionary *edition;
@property (nonatomic, strong) NSMutableDictionary<NSIndexPath *, NSDictionary *> *tracks;
@property (nonatomic) NSUInteger explicitTracks;
@property (nonatomic, strong) NSNumber *trackCount, *releaseYear;
@property (nonatomic, copy) NSString *consumptionText;
@property (nonatomic, weak) UICollectionView *trackList;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *itemCounts;
@property (nonatomic) NSUInteger snapshotDepth;
@property (nonatomic) BOOL snapshotInvalidated;
@property (nonatomic) NSUInteger generation;
@property (nonatomic, strong) SGRAlbumNoteView *view;
@property (nonatomic, strong) NSMutableSet<NSString *> *diagnostics;
@end
@implementation SGRAlbumNotesState @end

static void noteDiagnostic(SGRAlbumNotesState *state, NSString *event, NSString *detail) {
    NSMutableSet *logged = state.diagnostics;
    if (SGLogFirst(&logged, event))
        SGLog(@"album notes: %@ by %@: %@", state.album ?: @"(pending)", state.artist ?: @"(pending)", detail);
    state.diagnostics = logged;
}

static SGRAlbumNotesState *stateOf(UIView *page) {
    SGRAlbumNotesState *state = objc_getAssociatedObject(page, &kNotesKey);
    if (!state && page) {
        state = [SGRAlbumNotesState new];
        state.page = page;
        state.view = [SGRAlbumNoteView new];
        state.tracks = [NSMutableDictionary dictionary];
        state.edition = @{};
        objc_setAssociatedObject(page, &kNotesKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return state;
}

static void placeUnderPlay(UIView *header, SGRAlbumNotesState *state) {
    SGRAlbumNoteView *note = state.view;
    if (!note.notes || SGRAlbumNotesWhere() != SGRAlbumNotesUnderPlay) return;
    // The page's existing scrolling stack owns header/list ordering. Add one
    // self-sizing arranged sibling after the header, not an overlay on its controls.
    for (UIView *element = header; element.superview; element = element.superview) {
        if (![element.superview isKindOfClass:UIStackView.class]) continue;
        UIStackView *stack = (UIStackView *)element.superview;
        NSUInteger index = [stack.arrangedSubviews indexOfObjectIdenticalTo:element];
        if (index == NSNotFound) continue;
        if (note.superview != stack) {
            [note removeFromSuperview];
            [stack insertArrangedSubview:note atIndex:index + 1];
            noteDiagnostic(state, @"header-attached", @"display: Under Play attached after header");
        }
        [note invalidateIntrinsicContentSize];
        return;
    }
    noteDiagnostic(state, @"header-no-stack", @"display deferred: Under Play has no header stack");
}

static NSNumber *yearInHeader(UIView *header) {
    UIView *metadata = SGRFindByIdentifier(header, @"Components.UI.MetadataRow", NULL);
    __block NSNumber *year = nil;
    __block BOOL conflictingYears = NO;
    NSRegularExpression *years = [NSRegularExpression regularExpressionWithPattern:@"(?<![0-9])[0-9]{4}(?![0-9])" options:0 error:nil];
    SGForEachView(metadata, ^(UIView *view) {
        if (![view isKindOfClass:UILabel.class]) return;
        NSString *text = ((UILabel *)view).text ?: @"";
        for (NSTextCheckingResult *match in [years matchesInString:text options:0 range:NSMakeRange(0, text.length)]) {
            NSNumber *found = @([[text substringWithRange:match.range] integerValue]);
            if (year && ![year isEqual:found]) conflictingYears = YES;
            year = found;
        }
    });
    return conflictingYears ? nil : year;
}

static NSNumber *countInText(NSString *consumption) {
    // The consumption owner puts the count before the duration. Korean 9.1.90
    // prefixes the unit ("곡 14개"), unlike the older "14곡" representation.
    if ([consumption hasPrefix:@"곡 "]) consumption = [consumption substringFromIndex:2];
    NSNumberFormatter *numbers = [NSNumberFormatter new];
    numbers.numberStyle = NSNumberFormatterDecimalStyle;
    numbers.locale = NSLocale.currentLocale;
    NSMutableCharacterSet *digits = [NSCharacterSet.decimalDigitCharacterSet mutableCopy];
    [digits addCharactersInString:numbers.groupingSeparator ?: @""];
    NSScanner *scanner = [NSScanner scannerWithString:consumption];
    NSString *countText = nil;
    if ([scanner scanCharactersFromSet:digits intoString:&countText]) {
        NSNumber *count = [numbers numberFromString:countText];
        if (count.integerValue > 0) return count;
    }
    return nil;
}

// Counters make this independent of the number of tracks already seen. Called
// only for a changed entry, count/year, or album identity, never ordinary layout.
static BOOL updateEdition(SGRAlbumNotesState *state) {
#ifdef SG_ALBUM_NOTES_TEST_PROBE
    extern void SGRAlbumNotesTestDidRecompute(void);
    SGRAlbumNotesTestDidRecompute();
#endif
    NSMutableDictionary *edition = [NSMutableDictionary dictionary];
    if (state.trackCount) edition[@"trackCount"] = state.trackCount;
    if (state.releaseYear) edition[@"releaseYear"] = state.releaseYear;
    BOOL complete = state.trackCount.unsignedIntegerValue > 0 &&
                    state.tracks.count == state.trackCount.unsignedIntegerValue;
    if (state.explicitTracks) edition[@"explicit"] = @YES;
    else if (complete) edition[@"explicit"] = @NO;
    // This owner runs only when evidence changes, not on an ordinary layout.
    // Coverage can grow while the effective rating remains unknown or explicit.
    NSString *rating = edition[@"explicit"] ? ([edition[@"explicit"] boolValue] ? @"explicit" : @"clean") : @"unknown";
    SGLog(@"album notes: %@ by %@: rating=%@ seen=%lu/%@ explicitRows=%lu rebuilding=%d",
        state.album ?: @"(pending)", state.artist ?: @"(pending)", rating,
        (unsigned long)state.tracks.count, state.trackCount ?: @"unknown",
        (unsigned long)state.explicitTracks, !complete);
    if ([state.edition isEqual:edition]) return NO;
    state.edition = edition;
    return YES;
}

static void refreshNote(UIView *page, SGRAlbumNotesState *state) {
    NSUInteger generation = ++state.generation;
    BOOL hadNote = state.view.notes != nil;
    state.view.notes = nil;
    [state.view removeFromSuperview];
    if (hadNote) SGRAlbumNotesChanged(page);
    NSString *reason = !state.identity.length ? @"missing identity" : !state.trackCount ? @"missing Spotify trackCount" :
        !state.releaseYear ? @"missing Spotify releaseYear" : !state.edition[@"explicit"] ? @"unknown Spotify rating" : nil;
    if (reason) {
        noteDiagnostic(state, reason, [@"refuse: " stringByAppendingString:reason]);
        return;
    }
    noteDiagnostic(state, @"catalog-request", @"page evidence ready; requesting shared catalog record (independent of cached motion cover)");
    __weak UIView *weakPage = page;
    __weak SGRAlbumNotesState *weakState = state;
    SGMotionAlbumNotes(state.artist, state.album, state.edition, ^(NSDictionary *notes) {
        SGRAlbumNotesState *current = weakState;
        if (!weakPage || !current) return;
        if (current.generation != generation) {
            noteDiagnostic(current, @"stale-result", @"discard: stale catalog result");
            return;
        }
        noteDiagnostic(current, notes ? @"accepted" : @"catalog-refused",
            notes ? @"accept: note ready" : @"refuse: catalog supplied no eligible note (see catalog diagnostic)");
        current.view.notes = notes;
        placeUnderPlay(current.header, current);
        if (notes) SGRAlbumNotesChanged(weakPage);
    });
}

static NSMutableDictionary<NSNumber *, NSNumber *> *itemCounts(UICollectionView *list, NSDictionary *known) {
    NSMutableDictionary *counts = [NSMutableDictionary dictionary];
    for (NSNumber *section in known)
        counts[section] = section.integerValue < list.numberOfSections ? @([list numberOfItemsInSection:section.integerValue]) : @(-1);
    return counts;
}

// Index paths no longer identify the tracks we recorded. The count must also
// be read again from the new snapshot's consumption cell, not inherited from an
// old edition. A newly observed explicit row is sufficient for rating, whereas
// clean still needs every track of the new snapshot.
static void resetSnapshot(UIView *page, SGRAlbumNotesState *state, NSString *reason) {
    if (state.snapshotDepth && state.snapshotInvalidated) return;
    state.snapshotInvalidated = state.snapshotDepth > 0;
    SGLog(@"album notes: %@ by %@: reset track evidence: %@", state.album, state.artist, reason);
    [state.tracks removeAllObjects];
    state.explicitTracks = 0;
    state.trackCount = nil;
    state.consumptionText = nil;
    updateEdition(state);
    refreshNote(page, state);
}

void SGRAlbumNotesObserveSnapshot(UICollectionView *list) {
    SGRAlbumNotesState *state = objc_getAssociatedObject(list, &SGRAlbumNotesCollectionOwnerKey);
    UIView *page = state.page;
    if (!page || state.trackList != list || state.snapshotDepth) return;
    NSMutableDictionary *counts = itemCounts(list, state.itemCounts);
    if ([state.itemCounts isEqual:counts]) return;
    state.itemCounts = counts;
    resetSnapshot(page, state, @"track section counts changed");
}

void SGRAlbumNotesWillChangeSnapshot(UICollectionView *list) {
    SGRAlbumNotesState *state = objc_getAssociatedObject(list, &SGRAlbumNotesCollectionOwnerKey);
    UIView *page = state.page;
    if (!page || state.trackList != list) return;
    if (state.snapshotDepth++ == 0) state.snapshotInvalidated = NO;
}

void SGRAlbumNotesWillReload(UICollectionView *list) {
    SGRAlbumNotesWillChangeSnapshot(list);
    SGRAlbumNotesState *state = objc_getAssociatedObject(list, &SGRAlbumNotesCollectionOwnerKey);
    if (!state.page || state.trackList != list) return;
    resetSnapshot(state.page, state, @"reloadData");
    [state.itemCounts removeAllObjects];
}

void SGRAlbumNotesWillChangeItems(UICollectionView *list, NSArray<NSIndexPath *> *paths) {
    SGRAlbumNotesState *state = objc_getAssociatedObject(list, &SGRAlbumNotesCollectionOwnerKey);
    if (!state.page || state.trackList != list) return;
    for (NSIndexPath *path in paths) {
        if (!state.itemCounts[@(path.section)]) continue;
        resetSnapshot(state.page, state, @"track items updated");
        return;
    }
}

void SGRAlbumNotesWillChangeSections(UICollectionView *list, NSIndexSet *sections, BOOL shiftsFollowing) {
    SGRAlbumNotesState *state = objc_getAssociatedObject(list, &SGRAlbumNotesCollectionOwnerKey);
    if (!state.page || state.trackList != list) return;
    for (NSNumber *section in state.itemCounts.allKeys) {
        if (![sections containsIndex:section.unsignedIntegerValue] &&
            !(shiftsFollowing && sections.firstIndex <= section.unsignedIntegerValue)) continue;
        resetSnapshot(state.page, state, @"track sections updated or shifted");
        [state.itemCounts removeAllObjects];
        return;
    }
}

void SGRAlbumNotesDidChangeSnapshot(UICollectionView *list) {
    SGRAlbumNotesState *state = objc_getAssociatedObject(list, &SGRAlbumNotesCollectionOwnerKey);
    if (!state.page || state.trackList != list || !state.snapshotDepth) return;
    if (--state.snapshotDepth == 0) {
        // No-op/header/footer batches must not destroy track coverage. Targeted
        // mutation hooks cover same-count track changes; this catches count changes.
        if (state.snapshotInvalidated) state.itemCounts = itemCounts(list, state.itemCounts);
        else SGRAlbumNotesObserveSnapshot(list);
        state.snapshotInvalidated = NO;
        [list setNeedsLayout];
    }
}

NSDictionary *SGRAlbumNotesEdition(UIView *page) {
    SGRAlbumNotesState *state = objc_getAssociatedObject(page, &kNotesKey);
    return state.edition ?: @{};
}

void SGRAlbumNotesUpdate(UIView *header, UIView *page, NSString *artist, NSString *album) {
    if (!page) return;
    SGRAlbumNotesState *state = stateOf(page);
    NSString *identity = artist.length && album.length ? [NSString stringWithFormat:@"%@\n%@", artist, album] : @"";
    BOOL changedIdentity = ![state.identity isEqual:identity];
    if (changedIdentity) state.diagnostics = nil;
    if (changedIdentity && state.identity.length) {
        [state.tracks removeAllObjects];
        state.explicitTracks = 0;
        state.trackCount = state.releaseYear = nil;
        state.consumptionText = nil;
        if (objc_getAssociatedObject(state.trackList, &SGRAlbumNotesCollectionOwnerKey) == state)
            objc_setAssociatedObject(state.trackList, &SGRAlbumNotesCollectionOwnerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        state.trackList = nil;
        state.itemCounts = nil;
        state.snapshotDepth = 0;
        state.snapshotInvalidated = NO;
    }
    state.identity = identity;
    state.artist = artist;
    state.album = album;
    state.header = header;
    if (changedIdentity) {
        SGRAlbumNotesPlace place = SGRAlbumNotesWhere();
        noteDiagnostic(state, @"placement", [NSString stringWithFormat:@"placement=%@",
            place == SGRAlbumNotesOff ? @"Off; refuse: setting off" : place == SGRAlbumNotesUnderPlay ? @"Under Play" : @"Under tracks"]);
    }
    if (SGRAlbumNotesWhere() == SGRAlbumNotesOff) return;
    NSNumber *year = yearInHeader(header);
    BOOL changedYear = year && ![state.releaseYear isEqual:year];
    if (changedYear) state.releaseYear = year;
    if (changedIdentity || changedYear)
        noteDiagnostic(state, year ? @"year-found" : @"year-missing",
            [NSString stringWithFormat:@"Spotify releaseYear=%@ source=header Components.UI.MetadataRow", year ?: @"unknown"]);
    if (changedIdentity || changedYear) {
        BOOL changedEdition = updateEdition(state);
        if (changedIdentity || changedEdition) refreshNote(page, state);
    }
    placeUnderPlay(header, state);
}

void SGRAlbumNotesObserveCell(UICollectionViewCell *cell) {
    if (SGRAlbumNotesWhere() == SGRAlbumNotesOff) return;
    UIView *page = SGRAlbumPageOf(cell);
    if (!page) return;
    UIView *content = cell.contentView.subviews.firstObject;
    SGRAlbumNotesState *state = stateOf(page);
    if (state.snapshotDepth) return; // cells may still hold the previous batch's content
    BOOL changed = NO;
    if ([NSStringFromClass(content.class) containsString:@"RetrievalListStructuredData"]) {
        UICollectionView *list = nil;
        for (UIView *parent = cell.superview; parent && !list; parent = parent.superview)
            if ([parent isKindOfClass:UICollectionView.class]) list = (UICollectionView *)parent;
        NSIndexPath *path = [list indexPathForCell:cell];
        if (!path) {
            noteDiagnostic(state, @"track-no-index", @"track deferred: collection index path unavailable");
            return;
        }
        if (state.trackList != list) {
            if (state.itemCounts.count) resetSnapshot(page, state, @"track collection changed");
            if (objc_getAssociatedObject(state.trackList, &SGRAlbumNotesCollectionOwnerKey) == state)
                objc_setAssociatedObject(state.trackList, &SGRAlbumNotesCollectionOwnerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            state.trackList = list;
            objc_setAssociatedObject(list, &SGRAlbumNotesCollectionOwnerKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            state.itemCounts = [NSMutableDictionary dictionary];
            noteDiagnostic(state, @"track-owner", [NSString stringWithFormat:@"track collection associated: %@", NSStringFromClass(list.class)]);
        }
        if (path.section >= list.numberOfSections || path.item >= [list numberOfItemsInSection:path.section]) return;
        NSNumber *section = @(path.section), *count = @([list numberOfItemsInSection:path.section]);
        NSNumber *oldCount = state.itemCounts[section];
        state.itemCounts[section] = count;
        if (oldCount && ![oldCount isEqual:count]) resetSnapshot(page, state, @"track section count changed at cell");
        UIView *row = SGRFindByIdentifier(content, @"Components.UI.RetrievalRowElementUI_Loaded", NULL)
                   ?: SGRFindByIdentifier(content, @"Components.UI.RetrievalRowElementUI", NULL);
        UIView *titleView = SGRFindByIdentifier(row, @"EncoreConsumerMobile.View.Granular.Title", NULL);
        if (!titleView) {
            // Loaded 9.1.90 tracks use RetrievalRowKit's TitleView with Encore.Label
            // inside, not the Granular.Title identifier used by loading rows.
            __block UIView *loadedTitle = nil;
            SGForEachView(row, ^(UIView *view) {
                if (!loadedTitle && [NSStringFromClass(view.class) isEqual:@"_TtCC36CreativeWorkPlatform_RetrievalRowKit21RetrievalRowElementUI9TitleView"])
                    loadedTitle = view;
            });
            titleView = loadedTitle;
        }
        NSString *title = SGRFirstLabelText(titleView);
        if (!title.length) return; // a placeholder cannot prove clean or erase known evidence
        UIView *subtitle = SGRFindByIdentifier(row, @"RetrievalRowElementUI.Subtitle.Label", NULL)
                        ?: SGRFindByIdentifier(row, @"EncoreConsumerMobile.View.Granular.Subtitle", NULL);
        NSString *artist = SGRFirstLabelText(subtitle) ?: @"";
        NSDictionary *old = state.tracks[path];
        BOOL sameTrack = [old[@"title"] isEqual:title] && [old[@"artist"] isEqual:artist];
        if (old && !sameTrack) {
            // A same-count replacement/reorder can evade the count signature.
            // Never combine its new title with the old snapshot's other paths.
            resetSnapshot(page, state, @"track title/artist changed at index path");
            old = nil;
        }
        BOOL explicit = SGRFindByIdentifier(row, @"Components.UI.19andOverIcon", NULL) ||
                        SGRFindByIdentifier(row, @"Components.UI.ExplicitIcon", NULL);
        if (sameTrack) explicit |= [old[@"explicit"] boolValue];
        if (sameTrack && explicit == [old[@"explicit"] boolValue]) return;
        // Recycling within the same snapshot leaves prior track evidence intact.
        if ([old[@"explicit"] boolValue]) state.explicitTracks--;
        if (explicit) state.explicitTracks++;
        state.tracks[path] = @{@"title": title, @"artist": artist, @"explicit": @(explicit)};
        changed = YES;
    } else {
        UIView *consumption = SGRFindByIdentifier(content, @"Album.ConsumptionExperience", NULL);
        if (!consumption) return;
        NSString *text = SGRFirstLabelText(consumption) ?: @"";
        if ([state.consumptionText isEqual:text]) return;
        state.consumptionText = text;
        NSNumber *count = countInText(text);
        noteDiagnostic(state, count ? @"count-found" : @"count-missing",
            [NSString stringWithFormat:@"Spotify trackCount=%@ source=Album.ConsumptionExperience text=\"%@\"", count ?: @"unknown", text]);
        if (count && ![state.trackCount isEqual:count]) {
            state.trackCount = count;
            changed = YES;
        }
    }
    if (changed && updateEdition(state)) refreshNote(page, state);
}

CGFloat SGRAlbumNotesFooterHeight(UICollectionViewCell *cell, CGFloat width) {
    SGRAlbumNotesState *state = nil;
    if (SGRAlbumNotesWhere() == SGRAlbumNotesUnderTracks &&
        SGRFindByIdentifier(cell.contentView, @"Album.Copyright", NULL))
        state = objc_getAssociatedObject(SGRAlbumPageOf(cell), &kNotesKey);
    SGRAlbumNoteView *note = state.view.notes ? state.view : nil;
    if (objc_getAssociatedObject(cell, &kFooterNoteKey) != note) {
        SGRAlbumNotesForgetFooter(cell);
        objc_setAssociatedObject(cell, &kFooterNoteKey, note, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!note) return 0;
    if (note.superview != cell) {
        noteDiagnostic(state, @"footer-attached", @"display: Under tracks attached to Album.Copyright");
        [cell addSubview:note];
    }
    return [note heightForWidth:width];
}

void SGRAlbumNotesLayoutFooter(UICollectionViewCell *cell) {
    SGRAlbumNoteView *note = objc_getAssociatedObject(cell, &kFooterNoteKey);
    if (note.superview == cell) {
        CGFloat height = [note heightForWidth:cell.bounds.size.width];
        note.frame = CGRectMake(0, cell.contentView.frame.origin.y - height, cell.bounds.size.width, height);
    }
}

void SGRAlbumNotesForgetFooter(UICollectionViewCell *cell) {
    UIView *note = objc_getAssociatedObject(cell, &kFooterNoteKey);
    if (note.superview == cell) [note removeFromSuperview];
    objc_setAssociatedObject(cell, &kFooterNoteKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#import "../album-notes/catalog-boundary.h"
#import "motion-view-stubs.h"
#import "Redesigned/Artist/ArtistArtwork.h"
#import "Shared/AnimatedArtwork/SGMotionClip.h"
#import "Shared/AnimatedArtwork/SGMotionCatalog.h"
static NSMutableArray *pending;
CGFloat SGMotionPixels(void) { return 720; }
BOOL SGRReduceMotion(void) { return NO; }
void SGForEachView(UIView *view, void (^visit)(UIView *)) {
    if (!view) return;
    visit(view);
    for (UIView *child in view.subviews) SGForEachView(child, visit);
}
UIView *SGRFindByIdentifier(UIView *view, NSString *identifier, const void *key) {
    if ([view.accessibilityIdentifier isEqual:identifier]) return view;
    for (UIView *child in view.subviews) {
        UIView *found = SGRFindByIdentifier(child, identifier, NULL);
        if (found) return found;
    }
    return nil;
}
NSString *SGRFirstLabelText(UIView *view) {
    if ([view isKindOfClass:UILabel.class]) return ((UILabel *)view).text;
    for (UIView *child in view.subviews) {
        NSString *text = SGRFirstLabelText(child);
        if (text.length) return text;
    }
    return nil;
}
@interface MockCreator_CreatorPageImpl_LCR_Structure : UIView @end
@implementation MockCreator_CreatorPageImpl_LCR_Structure @end
@interface MockRetrievalTitleView : UIView @end
@implementation MockRetrievalTitleView @end
static UIView *section(UIView *page, NSString *heading) {
    UIView *item = [MockCreator_CreatorPageImpl_LCR_Structure new];
    [page addSubview:item];
    UILabel *label = [UILabel new];
    label.accessibilityIdentifier = @"Components.UI.SectionHeadingHome";
    label.text = heading;
    [item addSubview:label];
    return item;
}
static UIView *row(UIView *section, NSString *title, NSString *subtitle, BOOL add, BOOL undo, BOOL titleView) {
    UIView *row = [UIView new], *content = [UIView new];
    row.accessibilityIdentifier = @"Components.UI.RetrievalRowElementUI_Loaded";
    [section addSubview:row];
    [row addSubview:content]; // controls are descendants, not necessarily direct children
    UILabel *name = [UILabel new];
    name.text = title;
    if (titleView) {
        UIView *wrapper = [MockRetrievalTitleView new];
        [wrapper addSubview:name];
        [content addSubview:wrapper];
    } else {
        name.accessibilityIdentifier = @"EncoreConsumerMobile.View.Granular.Title";
        [content addSubview:name];
    }
    UILabel *detail = [UILabel new];
    detail.text = subtitle;
    detail.accessibilityIdentifier = @"RetrievalRowElementUI.Subtitle.Label";
    [content addSubview:detail];
    for (NSString *identifier in @[@"Components.UI.AddToButton", @"Components.UI.HiddenUndoButton"]) {
        if ([identifier hasSuffix:@"AddToButton"] ? !add : !undo) continue;
        UIView *button = [UIView new];
        button.accessibilityIdentifier = identifier;
        [content addSubview:button];
    }
    return row;
}
void SGMotionArtistArtwork(NSString *name, NSArray *titles, CGFloat pixels, BOOL photo, BOOL motion, void (^done)(UIImage *, NSURL *, SGMotionArtistArtworkOutcome)) {
    [pending addObject:[done copy]];
}
int main(void) {
    @autoreleasepool {
        pending = [NSMutableArray array];
        UIView *pageTree = [UIView new];
        UIView *popular = section(pageTree, @"인기");
        UIView *song = row(popular, @"Starboy", @"앨범 • 2016", YES, YES, NO);
        song.accessibilityLabel = @"2. Starboy. 사십팔억회 재생";
        row(popular, @"Signals", @"싱글 • 2025", YES, NO, NO);
        row(popular, @"Quiet", @"앨범 • 2025", NO, YES, NO);
        CHECK(SGRArtistReleaseTitles(pageTree).count == 0);
        UIView *releases = section(pageTree, @"인기 발매 음악");
        row(releases, @"Starboy", @"앨범 • 2016", NO, NO, NO);
        row(releases, @"Timeless", @"싱글 • 2025", NO, NO, YES);
        row(releases, @"Unverified", @"발매 예정", NO, NO, NO);
        row(releases, @"Not a year", @"앨범 • 12025", NO, NO, NO);
        UIView *featuring = section(pageTree, @"The Weeknd 피처링");
        UIView *card = row(featuring, @"A playlist", @"플레이리스트 • 2025", NO, NO, NO);
        card.accessibilityIdentifier = @"Components.UI.HomeCard";
        CHECK(([[NSSet setWithArray:SGRArtistReleaseTitles(pageTree)] isEqual:[NSSet setWithArray:@[@"Starboy", @"Timeless"]]]));
        SGRArtistArtworkRequest *request = [SGRArtistArtworkRequest new];
        __block NSString *page = @"spotify:artist:first";
        __block NSUInteger delivered = 0;
        void (^start)(void) = ^{
            [request updateIdentity:page name:@"Same Name" titles:@[@"First", @"Second"] photo:NO motion:YES
                currentIdentity:^NSString *{ return page; }
                apply:^(UIImage *photo, NSURL *file) { CHECK([file.path isEqual:@"/new.mp4"]); delivered++; }];
        };
        start();
        page = @"spotify:artist:second";
        // No new layout/request yet: checking only a remembered name is insufficient.
        ((void (^)(UIImage *, NSURL *, SGMotionArtistArtworkOutcome))pending[0])(nil, [NSURL fileURLWithPath:@"/old.mp4"], SGMotionArtistArtworkFinished);
        CHECK(delivered == 0);
        start();
        ((void (^)(UIImage *, NSURL *, SGMotionArtistArtworkOutcome))pending[0])(nil, [NSURL fileURLWithPath:@"/old.mp4"], SGMotionArtistArtworkFinished);
        CHECK(delivered == 0);
        ((void (^)(UIImage *, NSURL *, SGMotionArtistArtworkOutcome))pending[1])(nil, [NSURL fileURLWithPath:@"/new.mp4"], SGMotionArtistArtworkFinished);
        CHECK(delivered == 1);
        SGRArtistArtworkRequest *failure = [SGRArtistArtworkRequest new];
        __block NSUInteger failures = 0;
        void (^observe)(NSArray *) = ^(NSArray *titles) {
            [failure updateIdentity:page name:@"Same Name" titles:titles photo:YES motion:YES
                currentIdentity:^NSString *{ return page; }
                apply:^(UIImage *photo, NSURL *file) { CHECK(!photo && !file); failures++; }];
        };
        observe(@[@"First"]);
        CHECK(pending.count == 2);
        observe(@[@"Second"]);
        CHECK(pending.count == 3);
        observe(@[]);
        ((void (^)(UIImage *, NSURL *, SGMotionArtistArtworkOutcome))pending[2])(nil, nil, SGMotionArtistArtworkFinished);
        CHECK(failures == 1); // going offscreen did not invalidate the attempt
        observe(@[@"First", @"Second", @"Third"]);
        observe(@[]);
        observe(@[@"First", @"Second"]);
        CHECK(pending.count == 3 && failures == 1);
        SGRArtistArtworkRequest *reopened = [SGRArtistArtworkRequest new];
        [reopened updateIdentity:page name:@"Same Name" titles:@[@"First", @"Second"] photo:YES motion:YES
            currentIdentity:^NSString *{ return page; } apply:^(UIImage *photo, NSURL *file) {}];
        CHECK(pending.count == 4);
        SGRArtistArtworkRequest *growing = [SGRArtistArtworkRequest new];
        __block NSUInteger growingResults = 0;
        void (^more)(NSArray *) = ^(NSArray *titles) {
            [growing updateIdentity:page name:@"The Weeknd" titles:titles photo:NO motion:YES
                currentIdentity:^NSString *{ return page; } apply:^(UIImage *photo, NSURL *file) { growingResults++; }];
        };
        more(@[@"After Hours", @"Unmatched"]);
        CHECK(pending.count == 5);
        more(@[@"Out Of Time with Tomoko Aran"]); // arrives during metadata request
        ((void (^)(UIImage *, NSURL *, SGMotionArtistArtworkOutcome))pending[4])(nil, nil, SGMotionArtistArtworkNeedsEvidence);
        CHECK(pending.count == 6 && growingResults == 0);
        ((void (^)(UIImage *, NSURL *, SGMotionArtistArtworkOutcome))pending[5])(nil, nil, SGMotionArtistArtworkNeedsEvidence);
        for (NSUInteger layout = 0; layout < 100; layout++) more(@[]);
        CHECK(pending.count == 6); // unchanged evidence never retries metadata
        more(@[@"Starboy"]);
        CHECK(pending.count == 7);
        ((void (^)(UIImage *, NSURL *, SGMotionArtistArtworkOutcome))pending[6])(nil, nil, SGMotionArtistArtworkFinished);
        more(@[@"Dawn FM"]);
        CHECK(pending.count == 7 && growingResults == 1); // asset failure still latched
        SGRArtistArtworkRequest *metadataFailure = [SGRArtistArtworkRequest new];
        [metadataFailure updateIdentity:page name:@"Failure Artist" titles:@[@"First", @"Second"] photo:NO motion:YES
            currentIdentity:^NSString *{ return page; } apply:^(UIImage *photo, NSURL *file) { CHECK(NO); }];
        ((void (^)(UIImage *, NSURL *, SGMotionArtistArtworkOutcome))pending[7])(nil, nil, SGMotionArtistArtworkMetadataFailed);
        [metadataFailure updateIdentity:page name:@"Failure Artist" titles:@[@"Third"] photo:NO motion:YES
            currentIdentity:^NSString *{ return page; } apply:^(UIImage *photo, NSURL *file) { CHECK(NO); }];
        CHECK(pending.count == 8); // no scrolling retries on this page
        SGRArtistArtworkRequest *nextOpen = [SGRArtistArtworkRequest new];
        [nextOpen updateIdentity:page name:@"Failure Artist" titles:@[@"First", @"Second"] photo:NO motion:YES
            currentIdentity:^NSString *{ return page; } apply:^(UIImage *photo, NSURL *file) {}];
        CHECK(pending.count == 9);
        puts("artist artwork: new releases re-evaluate waiting metadata, unchanged layouts and failed assets never retry");
        puts("artist artwork: popular-track evidence excluded, releases retained, failed page attempt not retried on scrolling");
        puts("artist artwork: live page identity and superseded generation discard late results");
    }
    return 0;
}

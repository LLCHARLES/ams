// A lyrics button on the player's footer for a song with imported or embedded lyrics.
//
// NowPlaying_ModesImpl's units are child controllers whose views hold one row each (Native/Player/
// Player.x); the footer's is FooterElementsUnit (-viewDidLoad, objc-methods). The button is the mod's
// own view on the unit's view, not one of the row's, so it is free to hide. It sits a fifth of the way
// in from the leading edge, mirrored for a right-to-left language by the leading and trailing anchors.
//
// The track's metadata also says has_lyrics "true" for such a file, so the player builds its lyrics
// affordance. Spotify's Now Playing lyrics service (Lyrics_NPVElementsKitImpl.NPVElementsKitServiceImpl)
// is not told the same: its hasLyrics is a Swift protocol requirement with no Objective-C method on the
// class or its protocols in the binary, so Swift reaches it through its witness table and a method added
// for a hook would never be called.
#import "Core/SGCore.h"
#import "Headers/SPTPlayer.h"
#import "Shared/LocalFiles/LocalFiles.h"
#import "Shared/LocalFiles/LocalLyrics.h"
#import "Shared/Player/PlayerState.h"
#import "LocalLyrics.h"

static NSHashTable<UIButton *> *sg_buttons;

NSNotificationName const SGNativeFileSheetDidChange = @"spotifyglass.native.fileSheetChanged";
static NSString *sg_uri, *sg_path;
static BOOL sg_loading;
static NSUInteger sg_generation;
static SGLyricsResult *sg_sheet;

// One current-track snapshot, including a miss. The footer and its page never scan the
// library or parse the same tag independently. A late result cannot win across A → B → A.
static void refresh(SPTPlayerState *state, BOOL force) {
    NSString *uri = SGURIString(state.track.URI);
    BOOL local = SGLocalFileIs(uri);
    NSString *path = local ? state.track.metadata[@"local_file_path"] : nil;
    if (![path isKindOfClass:NSString.class]) path = nil;
    if (!force && (sg_uri == uri || [sg_uri isEqual:uri]) && (sg_path == path || [sg_path isEqual:path])) return;
    NSUInteger generation = ++sg_generation;
    sg_uri = [uri copy]; sg_path = [path copy]; sg_sheet = nil;
    for (UIButton *button in sg_buttons) button.hidden = YES;
    sg_loading = local || SGImportedLRCLinkedTo(uri) != nil;
    if (sg_loading) {
        SGPlaybackLyricsFetch(local ? SGLocalFileLyricsKey(uri) : uri, path, ^(SGLyricsResult *result) {
            if (sg_generation != generation) return;
            sg_loading = NO; sg_sheet = result;
            for (UIButton *button in sg_buttons) button.hidden = !result.karaokeLines.count;
            [NSNotificationCenter.defaultCenter postNotificationName:SGNativeFileSheetDidChange object:uri];
        });
    }
    if (force || !sg_loading)
        [NSNotificationCenter.defaultCenter postNotificationName:SGNativeFileSheetDidChange object:uri];
}

SGLyricsResult *SGNativeCurrentFileSheet(BOOL *loading) {
    refresh(SGPlayerState(), NO);
    *loading = sg_loading;
    return sg_sheet;
}

@interface SGLocalLyricsButtons : NSObject <SGPlayerStateObserver>
@end

@implementation SGLocalLyricsButtons
- (void)playerStateDidChange:(SPTPlayerState *)state {
    if (sg_buttons.count) refresh(state, NO);
}
- (void)playerStateDidReport:(SPTPlayerState *)state {
    if (sg_buttons.count) refresh(state, NO); // the core can supply local_file_path after the track
}
@end

static void addButton(UIViewController *unit) {
    UIView *host = unit.view;
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[UIImage systemImageNamed:@"quote.bubble" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightRegular]]
            forState:UIControlStateNormal];
    button.tintColor = UIColor.whiteColor;
    button.accessibilityLabel = SGL(@"settings.player.hide.lyrics.title", @"Lyrics");
    button.translatesAutoresizingMaskIntoConstraints = NO;
    __weak UIViewController *weakUnit = unit;
    [button addAction:[UIAction actionWithHandler:^(UIAction *action) {
        [weakUnit presentViewController:SGLocalLyricsPage() animated:YES completion:nil];
    }] forControlEvents:UIControlEventTouchUpInside];
    [host addSubview:button];

    UILayoutGuide *fifth = [UILayoutGuide new];
    [host addLayoutGuide:fifth];
    [NSLayoutConstraint activateConstraints:@[
        [fifth.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
        [fifth.widthAnchor constraintEqualToAnchor:host.widthAnchor multiplier:0.2],
        [fifth.topAnchor constraintEqualToAnchor:host.topAnchor],
        [fifth.heightAnchor constraintEqualToConstant:0],
        [button.centerXAnchor constraintEqualToAnchor:fifth.trailingAnchor],
        [button.centerYAnchor constraintEqualToAnchor:host.centerYAnchor],
        [button.widthAnchor constraintEqualToConstant:44],
        [button.heightAnchor constraintEqualToConstant:44],
    ]];
    [sg_buttons addObject:button];
    refresh(SGPlayerState(), NO);
    button.hidden = !sg_sheet.karaokeLines.count;
}

%hook _TtC20NowPlaying_ModesImpl18FooterElementsUnit
- (void)viewDidLoad {
    %orig;
    addButton((UIViewController *)self);
}
%end

// Read for every track in every list many times a second: a prefix check for any other track.
%hook SPTPlayerTrack
- (NSDictionary *)metadata {
    NSDictionary *metadata = %orig;
    NSString *uri = SGURIString(self.URI);
    if (!SGLocalFileIs(uri) || [@"true" isEqual:metadata[@"has_lyrics"]] || !SGImportedLRCLinkedTo(uri)) return metadata;
    NSMutableDictionary *linked = metadata ? [metadata mutableCopy] : [NSMutableDictionary dictionary];
    linked[@"has_lyrics"] = @"true";
    return linked;
}
%end

%ctor {
    if (!SGNativeUI()) return;
    %init;
    sg_buttons = [NSHashTable weakObjectsHashTable];
    static SGLocalLyricsButtons *observer;
    observer = [SGLocalLyricsButtons new];
    SGAddPlayerStateObserver(observer);
    // An import for the track playing, or the delete of its file, changes the button with no new track.
    for (NSString *name in @[SGImportedLRCDidChangeNotification, SGLocalFileEditsDidChangeNotification])
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
            refresh(SGPlayerState(), YES);
        }];
    SGRequireClasses(@[@"_TtC20NowPlaying_ModesImpl18FooterElementsUnit", @"SPTPlayerTrack"]);
}

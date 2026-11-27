#import "../shared/redesigned-page-stubs.m"

#import "motion-player-double.h"

#import "../shared/no-music-spectrum.h"

// Shared/Fonts/FontImport.m: no font of the user's own in the harness.
NSString *SGRegisterCustomFont(void) { return nil; }

// MotionSources.m: Apple Music is on, as it is by default.
BOOL SGMotionAppleMusicOn(void) { return YES; }

// ListeningStats.x: the album's play counts read a log of the harness's own, in its temporary folder.
#import "Shared/ListeningStats/SGPlayLog.h"
SGPlayLog *SGListeningLog(void) {
    static SGPlayLog *log;
    if (!log) {
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"plays.tsv"];
        if ([NSProcessInfo.processInfo.arguments containsObject:@"ordinal-count"]) {
            path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ordinal-plays.tsv"];
            [@"1700000000\t60000\tspotify:track:5673WA8EEUSPx1ir26lhGW\tI Can't Fucking Sing\tThe Weeknd\tHurry Up Tomorrow\n"
                writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        }
        log = [[SGPlayLog alloc] initWithPath:path];
    }
    return log;
}

// Shared/AlbumQueue/AlbumQueueMenu.x: the ⋯ menu's album queue is a part of a native menu, not of the page.
void SGAlbumQueueMarkSource(UIView *view) {}

// Redesigned/Album/AlbumPlaysMenu.x: a track's plays in its ⋯ menu belong to the native menu, not to the page.
void SGRAlbumPlaysMarkMenu(NSString *album, NSString *title) {}
#import "Redesigned/Album/AlbumSpotifyCounts.h"
#import "../motion/no-recording-lookup.h"
void SGRAlbumPlaysMarkSpotifyMenu(NSString *trackURI, SGRAlbumCountPage *page) {}
dispatch_block_t SGSpotifyMetadataRequest(NSString *path, NSData *body, SGSpotifyMetadataReply done) {
    if ([NSProcessInfo.processInfo.arguments containsObject:@"ordinal-layout"] && !body) {
        NSData *json = [NSJSONSerialization dataWithJSONObject:@{@"disc": @[@{@"track": @[
            @{@"uri": @"spotify:track:5673WA8EEUSPx1ir26lhGW"}]}]} options:0 error:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{ done(json, 200, nil); });
        return ^{};
    }
    NSLog(@"[harness] unexpected Spotify network request");
    exit(1);
}
dispatch_block_t SGSpotifyMetadataRequestAllowConstrained(NSString *path, NSData *body, BOOL allow, SGSpotifyMetadataReply done) {
    return SGSpotifyMetadataRequest(path, body, done);
}

// SGPageStyle.m: the cover viewer is presented over whatever is on top of the harness's window.
UIViewController *SGTopController(void) {
    UIWindowScene *scene = (UIWindowScene *)UIApplication.sharedApplication.connectedScenes.anyObject;
    UIViewController *top = scene.windows.firstObject.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}

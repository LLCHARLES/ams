#!/usr/bin/env python3
"""Host regression for language-independent catalog and operation identities."""
from pathlib import Path
import argparse
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT.parent


def method(source, signature):
    start = source.index(signature)
    return source[start:source.index("\n}", start) + 2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mutation", action="store_true",
                        help="Prove the regression rejects localized grouping keys")
    args = parser.parse_args()
    ui = (ROOT / "src/Library/OfflineLibraryUI.m").read_text()
    helpers = ui[ui.index("static NSString * const SAPOfflineUnknownArtist"):
                 ui.index("@class SAPOfflineLibraryController")]
    if args.mutation:
        helpers = helpers.replace(
            'SAPOfflineString(row[@"artist_name"], SAPOfflineUnknownArtist)',
            'SAPOfflineString(row[@"artist_name"], SAPL(@"settings.pixie.artist.unknown",@"Unknown artist"))')
    controller = ui[ui.index("@implementation SAPOfflineLibraryController"):]
    grouping = "\n".join(method(controller, signature) for signature in (
        "+ (NSArray<NSDictionary *> *)artistRowsForTracks:",
        "- (NSArray<NSDictionary *> *)buildReleaseSections {"))
    export = (ROOT / "src/Export/TrackExport.m").read_text()
    export = export[export.index("NSString *const SAPAudioExportBusyIdentifier"):
                    export.index("static void SAPStartAudioExportURI(")]
    repository = (ROOT / "src/Playlists/PlaylistRepository.m").read_text()
    repository = repository[repository.index("static NSString *const SAPPlaylistLoadingIdentifier"):
                            repository.index("@interface SAPPlaylistRead")]
    internal = (ROOT / "src/Playlists/PlaylistDownloadsInternal.h").read_text()
    internal = internal[internal.index("enum { SAPPlaylistPageSize"):
                        internal.index("@interface SAPPlaylistDownloadTask")]
    artist = (ROOT / "src/Catalog/ArtistMetadata.m").read_text()
    artist = artist[artist.index("static BOOL validURI"):
                    artist.index("// Spotify's metadata GID")]
    fixture = r'''
#import <Foundation/Foundation.h>
#import "Localization.h"
#import "WireProto.h"
#import "PlaylistArtwork.h"
#define SAP_PLAYLIST_INTERNAL
static NSDictionary *translations;
NSString *SGL(NSString *key, NSString *english) { return translations[key] ?: english; }
static BOOL require(BOOL condition, NSString *message) {
    if(!condition)fprintf(stderr,"FAIL: %s\n",message.UTF8String);
    return condition;
}
'''
    deletion = (ROOT / "src/Library/OfflineLibraryDelete.m").read_text()
    deletion = deletion[deletion.index("NSString *const SAPOfflineLibraryDeleteBusyError"):
                        deletion.index("static NSString *const Offline=")]
    devices = (ROOT / "src/Devices/OfflineDeviceManager.m").read_text()
    fixture += helpers + export + artist + internal + repository + deletion
    fixture += method(devices, "static NSString *directReadStatus(")
    fixture += r'''
@interface SAPOfflineLibraryController : NSObject
@property(nonatomic,strong) NSArray *scope;
+ (NSArray *)artistRowsForTracks:(NSArray *)tracks;
- (NSArray *)buildReleaseSections;
@end
@implementation SAPOfflineLibraryController
'''
    fixture += grouping + "\n@end\n"
    observation = (ROOT / "src/Downloads/ArtistSessionObservation.m").read_text()
    fixture += r'''
@interface SAPObservationFixture : NSObject
@property(nonatomic) NSUInteger repairEpisodes;
@property(nonatomic) BOOL observationPaused, watchSuspended;
@property(nonatomic,copy) NSString *error;
@property(nonatomic,strong) NSDictionary *states;
- (void)repairWatch:(NSString *)reason;
- (void)resumeObservation;
@end
@implementation SAPObservationFixture
- (void)repairWatch:(NSString *)reason {}
'''
    fixture += method(observation, "- (void)resumeObservation {") + "\n@end\n"
    fixture += r'''
int main(int argc, const char **argv) {
    @autoreleasepool {
        NSString *bundle=[NSString stringWithUTF8String:argv[1]];
        NSArray *tracks=@[
            @{@"uri":@"spotify:track:aaaaaaaaaaaaaaaaaaaaaa",@"artist_name":@"",
              @"album_name":@"",@"category":@"Albums"},
            @{@"uri":@"spotify:track:bbbbbbbbbbbbbbbbbbbbbb",@"artist_uri":@"artist-1",
              @"artist_name":@"Actual artist",@"album_uri":@"album-1",
              @"album_name":@"Actual album",@"category":@"Singles"}
        ];
        NSMutableData *loading=[SAPProtoInteger(98,200) mutableCopy];
        [loading appendData:SAPProtoBytes(1,SAPProtoInteger(12,1))];
        for(NSString *language in @[@"en",@"ko"]) {
            translations=[NSDictionary dictionaryWithContentsOfFile:
                [bundle stringByAppendingPathComponent:[language stringByAppendingString:@".lproj/Localizable.strings"]]];
            BOOL korean=[language isEqual:@"ko"];
            if(!require([directReadStatus(NO,YES)isEqual:@"timeout"]&&[directReadStatus(NO,NO)isEqual:@"unavailable"]&&[directReadStatus(YES,NO)isEqual:@"received"],@"device read status must use transport state, not localized error text"))return 1;
            if(!require(translations.count>0,@"translation resources must load"))return 1;
            SAPObservationFixture *observer=[SAPObservationFixture new];
            observer.observationPaused=YES;
            observer.error=korean?@"관찰 중지":@"Observation paused";
            NSMutableDictionary *paused=[@{@"error":observer.error}mutableCopy];
            NSMutableDictionary *unrelated=[@{@"error":[NSMutableString stringWithString:observer.error]}mutableCopy];
            observer.states=@{@"paused":paused,@"unrelated":unrelated};
            [observer resumeObservation];
            if(!require(!paused[@"error"]&&unrelated[@"error"]!=nil,@"resume must clear only its own error occurrence, not equal translated text"))return 1;
            NSArray *artists=[SAPOfflineLibraryController artistRowsForTracks:tracks];
            NSDictionary *unknown=nil;
            for(NSDictionary *row in artists)if([row[@"key"]isEqual:@"Unknown artist|spotify:track:aaaaaaaaaaaaaaaaaaaaaa"])unknown=row;
            if(!require(unknown!=nil,@"artist grouping identity must not depend on display language"))return 1;
            if(!require([unknown[@"name"]isEqual:korean?@"알 수 없는 아티스트":@"Unknown artist"],@"missing artist display must follow language"))return 1;
            SAPOfflineLibraryController *controller=[SAPOfflineLibraryController new];
            controller.scope=tracks;
            NSArray *sections=[controller buildReleaseSections];
            if(!require([[sections valueForKey:@"category"]isEqual:@[@"Albums",@"Singles"]],@"category identities and order must stay stable"))return 1;
            if(!require([SAPCategoryTitle(sections[0][@"category"])isEqual:korean?@"앨범":@"Albums"],@"category display must follow language"))return 1;
            if(!require([sections[0][@"releases"][0][@"key"]isEqual:@"Unknown album|spotify:track:aaaaaaaaaaaaaaaaaaaaaa"],@"release grouping identity must stay stable"))return 1;
            if(!require(SAPAudioExportIsBusy(@"pixie.export.busy")&&!SAPAudioExportIsBusy(@"Another export is already running.")&&!SAPAudioExportIsBusy(@"다른 내보내기가 이미 진행 중입니다."),@"busy branch must accept only the operation identifier"))return 1;
            if(!require(SAPOfflineLibraryDeleteIsBusy(@"pixie.library.download_active")&&!SAPOfflineLibraryDeleteIsBusy(@"Download in progress")&&!SAPOfflineLibraryDeleteIsBusy(@"다운로드 중"),@"deletion block must accept only the download identity"))return 1;
            if(!require([SAPAudioExportErrorText(@"pixie.export.busy")isEqual:korean?@"다른 내보내기가 이미 진행 중입니다.":@"Another export is already running."],@"busy display must follow language"))return 1;
            NSString *error=nil;
            if(!require(SAPParseWritablePlaylistPage(loading,&error)==nil&&[error isEqual:@"pixie.playlist.loading"],@"playlist loading must return a stable retry identifier"))return 1;
            if(!require([SAPDeviceL(@"this_copy")isEqual:korean?@"이 사본":@"This copy"],@"device text must use Retrine resources"))return 1;
            printf("PASS: %s grouping, busy/loading identifiers and localized display\n",language.UTF8String);
        }
    }
    return 0;
}
'''
    with tempfile.TemporaryDirectory(prefix="pixie-localization-identity-") as temporary:
        work = Path(temporary)
        source, binary = work / "identity.m", work / "identity"
        source.write_text(fixture)
        subprocess.run([
            "xcrun", "clang", "-fobjc-arc", "-fblocks",
            "-I" + str(ROOT / "src/Public"),
            "-I" + str(ROOT / "src/Spotify"),
            "-I" + str(ROOT / "src/Artwork"),
            str(source), str(ROOT / "src/UI/Localization.m"),
            str(ROOT / "src/Spotify/WireProto.m"),
            "-framework", "Foundation", "-o", str(binary)
        ], check=True)
        subprocess.run([str(binary), str(PROJECT / "tweak/layout/Library/Application Support/Retrine.bundle")], check=True)


if __name__ == "__main__":
    main()

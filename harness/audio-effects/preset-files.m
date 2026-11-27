// Checks preset files (AudioEffectsPresets.m) on the Mac through the real settings: a preset written and read
// back, and the files the reader refuses or trims.
//
//     ./build.sh presets && build/preset-files-check
//
// Every line prints ok or FAIL; the exit status is the number of failures.
#import <Foundation/Foundation.h>
#import "AudioEffects.h"
#import "AudioEffectsApply.h"
#import "AudioEffectsPresets.h"

static int failures;
static NSString *appliedEffect;

static void check(BOOL ok, NSString *what) {
    printf("%s %s\n", ok ? "ok  " : "FAIL", what.UTF8String);
    failures += !ok;
}

// The engine is not here.
void SGDSPApply(NSString *effect) {
    appliedEffect = effect;
}

static void clearDefaults(void) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    for (NSString *key in store.dictionaryRepresentation) {
        if ([key hasPrefix:@"spotifyglass."]) [store removeObjectForKey:key];
    }
}

static NSData *json(id object) {
    return [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
}

static NSDictionary *readFile(NSData *data, NSString **name, NSString **error) {
    return SGDSPReadPresetFile(data, @"From file", name, error);
}

static void checkTextImports(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *dir = [fm.temporaryDirectory URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
    check([fm createDirectoryAtURL:dir withIntermediateDirectories:NO attributes:nil error:nil], @"create import fixtures");
    for (NSNumber *number in @[@(SGDSPFileLiveprog), @(SGDSPFileDDC)]) {
        SGDSPFileKind kind = number.integerValue;
        NSString *ext = SGDSPFileExtensions(kind).firstObject;
        NSURL *file = [dir URLByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingPathExtension:ext]];
        NSURL *link = [dir URLByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingPathExtension:ext]];
        NSMutableData *data = [NSMutableData dataWithLength:1 << 20];
        const char *marker = kind == SGDSPFileLiveprog ? "@sample\n" : "SR_44100\nSR_48000\n";
        memcpy(data.mutableBytes, marker, strlen(marker));
        check([data writeToURL:file atomically:YES], @"write boundary file");
        check(SGDSPImportFile(kind, file, nil) != nil, @"1 MiB text file imports");
        check([fm createSymbolicLinkAtURL:link withDestinationURL:file error:nil], @"create import link");
        check(SGDSPImportFile(kind, link, nil) == nil, @"text import refuses a symlink");
        [data appendBytes:" " length:1];
        check([data writeToURL:file atomically:YES], @"grow boundary file");
        check(SGDSPImportFile(kind, file, nil) == nil, @"oversized text file cannot replace an import");
        SGDSPDeleteFile(kind, file.lastPathComponent);
        SGDSPDeleteFile(kind, link.lastPathComponent);
    }
    [fm removeItemAtURL:dir error:nil];
}

int main(void) {
    @autoreleasepool {
        clearDefaults();

        checkTextImports();
        check(SGDSPFileKey((SGDSPFileKind)-1) == nil, @"invalid file kind has no selection key");
        check([SGDSPPresetMissingFiles(@{
            SGKeyDSPConvolverFile: @"refactor-missing-ir.wav",
            SGKeyDSPDDCFile: @"refactor-missing-ddc.vdc",
            SGKeyDSPLiveprogFile: @"refactor-missing-script.eel"
        }) isEqual:@[@"refactor-missing-ir.wav", @"refactor-missing-ddc.vdc", @"refactor-missing-script.eel"]],
              @"missing files retain effect order");
        check([SGDSPPresetMissingFiles(@{
            SGKeyDSPConvolverFile: @"refactor-missing.wav", SGKeyDSPDDCFile: @"refactor-missing.wav"
        }) isEqual:@[@"refactor-missing.wav"]], @"missing names are deduplicated");
        const SGDSPFileKind kinds[] = {SGDSPFileImpulseResponse, SGDSPFileDDC, SGDSPFileLiveprog};
        NSArray *effects = @[@"spotifyglass.dsp.convolver", @"spotifyglass.dsp.ddc", @"spotifyglass.dsp.liveprog"];
        for (NSUInteger i = 0; i < 3; ++i) {
            NSString *name = [NSUUID.UUID.UUIDString stringByAppendingPathExtension:SGDSPFileExtensions(kinds[i]).firstObject];
            NSString *path = [SGDSPLibraryDirectory(kinds[i]) stringByAppendingPathComponent:name];
            check([NSData.data writeToFile:path atomically:YES], @"create owned deletion fixture");
            SGDSPSetString(SGDSPFileKey(kinds[i]), name);
            appliedEffect = nil;
            check(SGDSPDeleteFile(kinds[i], name), @"delete chosen library file");
            check([appliedEffect isEqual:effects[i]], @"deletion reapplies the owning effect");
        }
        clearDefaults();

        // Preset loading owns settings round trips; AutoEq owns download and correction races.
        SGDSPSetSwitch(SGKeyDSPTube, YES);
        SGDSPSetSwitch(SGKeyDSPGraphicEq, YES);
        SGDSPSetString(SGKeyDSPGraphicEqNodes, @"GraphicEQ: 20 -1.2;");
        SGDSPSetString(SGKeyDSPGraphicEqHeadphone, @"Fixture/Headphones");
        SGDSPSetSwitch(SGKeyDSP, NO);
        SGDSPLoadBuiltInPreset(0);
        check(!SGDSPSwitch(SGKeyDSPTube) && SGDSPSwitch(SGKeyDSP), @"built-in replaces other effects and enables processing");
        check(SGDSPSwitch(SGKeyDSPGraphicEq) && [SGDSPString(SGKeyDSPGraphicEqNodes) isEqual:@"GraphicEQ: 20 -1.2;"]
              && [SGDSPString(SGKeyDSPGraphicEqHeadphone) isEqual:@"Fixture/Headphones"], @"built-in preserves headphone correction");
        SGDSPSetSwitch(SGKeyDSPCompander, YES);
        SGDSPSetNumber(SGKeyDSPPostGain, 2.5);
        SGDSPSaveUserPreset(@"Mine");
        SGDSPSaveUserPreset(@"another");
        check([SGDSPUserPresetNames() isEqual:@[@"another", @"Mine"]], @"saved presets listed by name");
        SGDSPResetAll();
        SGDSPSetSwitch(SGKeyDSP, NO);
        SGDSPSetString(SGKeyDSPGraphicEqNodes, @"GraphicEQ: 1000 3;");
        check(SGDSPLoadUserPreset(@"Mine") && SGDSPSwitch(SGKeyDSP), @"saved preset loads and enables processing");
        check(SGDSPSwitch(SGKeyDSPCompander) && SGDSPNumber(SGKeyDSPPostGain) == 2.5, @"saved effects and values restored");
        check(SGDSPSwitch(SGKeyDSPGraphicEq) && [SGDSPString(SGKeyDSPGraphicEqNodes) isEqual:@"GraphicEQ: 20 -1.2;"]
              && [SGDSPString(SGKeyDSPGraphicEqHeadphone) isEqual:@"Fixture/Headphones"], @"saved headphone correction restored");
        check(!SGDSPLoadUserPreset(@"nobody's"), @"unknown preset loads nothing");
        SGDSPDeleteUserPreset(@"another");
        check([SGDSPUserPresetNames() isEqual:@[@"Mine"]], @"preset deleted");
        clearDefaults();

        // A preset of the user's, written and read back.
        SGDSPSetSwitch(SGKeyDSPBass, YES);
        SGDSPSetNumber(SGKeyDSPBassGain, 9);
        SGDSPSetGains(SGKeyDSPEqualizerGains, @[@1, @2, @3]);
        SGDSPSetString(SGKeyDSPConvolverFile, @"Hall.wav");
        SGDSPSetSwitch(SGKeyDSP, YES);
        SGDSPSaveUserPreset(@"Late/night: mine");
        NSString *fileName = nil;
        NSData *data = SGDSPPresetFileData(@"Late/night: mine", &fileName);
        check(data != nil, @"a saved preset becomes a file");
        check([fileName isEqualToString:@"Late-night- mine.retrine-preset.json"], [NSString stringWithFormat:@"its file name is safe for Files (%@)", fileName]);
        NSDictionary *file = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        check([file[@"format"] isEqual:@"retrine.audio-preset"] && [file[@"version"] isEqual:@1], @"the file says what it is");
        check(file[@"values"][SGKeyDSP] == nil, @"the master switch stays out of the file");
        NSString *name = nil, *error = nil;
        NSDictionary *values = readFile(data, &name, &error);
        check([name isEqualToString:@"Late/night: mine"], @"the name comes back as it was");
        check([values[SGKeyDSPBass] boolValue] && [values[SGKeyDSPBassGain] doubleValue] == 9, @"switches and numbers come back");
        check([values[SGKeyDSPConvolverFile] isEqualToString:@"Hall.wav"], @"a file name comes back");
        check([SGDSPPresetMissingFiles(values) containsObject:@"Hall.wav"], @"the impulse response it names is missing here");
        check(SGDSPPresetFileData(@"Nobody", NULL) == nil, @"no file for a preset that is not there");

        // Saved under a free name, then loaded.
        SGDSPResetAll();
        check([SGDSPUniquePresetName(@"Late/night: mine") isEqualToString:@"Late/night: mine 2"], @"a taken name gets a number");
        SGDSPSaveUserPresetValues(@"Imported", values);
        check(SGDSPUserPresetExists(@"Imported") && SGDSPLoadUserPreset(@"Imported"), @"an imported preset is saved and loads");
        check(SGDSPSwitch(SGKeyDSPBass) && SGDSPNumber(SGKeyDSPBassGain) == 9, @"loading it sets the effects");
        check([[SGDSPGains(SGKeyDSPEqualizerGains) subarrayWithRange:NSMakeRange(0, 3)] isEqual:@[@1, @2, @3]],
              @"loading restores the user's equalizer bands");

        // What the reader refuses.
        check(!readFile(nil, NULL, &error) && error.length, @"no data is refused");
        check(!readFile([@"[1,2]" dataUsingEncoding:NSUTF8StringEncoding], NULL, &error) && error.length, @"an array is refused");
        check(!readFile(json(@{@"format": @"other", @"version": @1, @"values": @{SGKeyDSPBass: @YES}}), NULL, &error), @"another format is refused");
        check(!readFile(json(@{@"format": @"vitrine.audio-preset", @"version": @2, @"values": @{SGKeyDSPBass: @YES}}), NULL, &error)
              && [error containsString:@"newer"], [NSString stringWithFormat:@"a later version says to update (%@)", error]);
        check(!readFile(json(@{@"format": @"vitrine.audio-preset", @"version": @YES, @"values": @{SGKeyDSPBass: @YES}}), NULL, &error), @"a boolean version is refused");
        check(!readFile(json(@{@"format": @"vitrine.audio-preset", @"version": @1.5, @"values": @{SGKeyDSPBass: @YES}}), NULL, &error), @"a fractional version is refused");
        check(!readFile(json(@{@"format": @"vitrine.audio-preset", @"version": @1, @"values": @[]}), NULL, &error), @"values that are not a dictionary are refused");
        check(!readFile(json(@{@"format": @"vitrine.audio-preset", @"version": @1, @"values": @{@"spotifyglass.font": @3, SGKeyDSP: @YES}}), NULL, &error), @"nothing usable is refused");
        NSMutableData *big = [NSMutableData dataWithLength:256 * 1024 + 1];
        check(!readFile(big, NULL, &error) && [error containsString:@"large"], @"over 256 KB is refused");

        // What it trims.
        NSDictionary *trimmed = readFile(json(@{@"format": @"vitrine.audio-preset", @"version": @1, @"name": @"  ",
            @"values": @{SGKeyDSPBass: @YES, SGKeyDSP: @YES, @"spotifyglass.font": @3, SGKeyDSPBassGain: @"loud",
                         SGKeyDSPConvolverFile: @"../../etc/passwd", SGKeyDSPDDCFile: @".hidden.vdc", SGKeyDSPLiveprogFile: @"ok.eel"}}), &name, &error);
        check(trimmed[SGKeyDSPBass] && !trimmed[SGKeyDSP] && !trimmed[@"spotifyglass.font"], @"only this build's keys are kept, never the master switch");
        check(!trimmed[SGKeyDSPBassGain], @"a value of the wrong type is dropped");
        check(!trimmed[SGKeyDSPConvolverFile] && !trimmed[SGKeyDSPDDCFile] && [trimmed[SGKeyDSPLiveprogFile] isEqual:@"ok.eel"], @"a file name with a path or a dot first is dropped");
        check([name isEqualToString:@"From file"], @"a blank name takes the file's");
        NSString *longName = [@"" stringByPaddingToLength:120 withString:@"가" startingAtIndex:0];
        readFile(json(@{@"format": @"vitrine.audio-preset", @"version": @1, @"name": longName, @"values": @{SGKeyDSPBass: @YES}}), &name, NULL);
        check(name.length == 80, @"a long name is cut to 80 characters");

        clearDefaults();
        printf("%d failure(s)\n", failures);
        return failures;
    }
}

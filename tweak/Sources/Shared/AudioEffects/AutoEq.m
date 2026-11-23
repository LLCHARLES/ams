// AutoEq's headphone corrections, read straight from its public repository: github.com/jaakkopasanen/AutoEq,
// MIT License, Copyright (c) 2018-2022 Jaakko Pasanen. Nothing of it ships in the mod; results/INDEX.md and
// the chosen headphone's GraphicEQ file are downloaded when asked for.
//
// INDEX.md, as of October 2026, is a heading and a note, then one line per result:
//     - [1MORE Quad Driver](./crinacle/711%20in-ear/1MORE%20Quad%20Driver) by crinacle on 711
// and the folder holds "<folder's last part> GraphicEQ.txt", one "GraphicEQ: 20 -0.2; 21 -0.2; ..." line.
// The file is named after the folder, not the name in brackets: the name can carry a target the folder
// does not.
#import "Core/SGLocalize.h"
#import "Core/SGLog.h"
#import "Core/SGDataRoot.h"
#import "AudioEffects.h"
#import "AudioEffectsPresets.h"

static NSString *const kResults = @"https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/results/";
static const NSTimeInterval kIndexLife = 30 * 24 * 3600;

@implementation SGAutoEqHeadphone
@end

NSArray<SGAutoEqHeadphone *> *SGAutoEqParseIndex(NSString *markdown) {
    NSMutableArray<SGAutoEqHeadphone *> *headphones = [NSMutableArray array];
    [markdown enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
        if (![line hasPrefix:@"- ["]) return;
        // The last "](./" and the last ") by ": names hold brackets and folders parentheses.
        NSRange link = [line rangeOfString:@"](./" options:NSBackwardsSearch];
        NSRange by = [line rangeOfString:@") by " options:NSBackwardsSearch];
        if (link.location == NSNotFound || by.location == NSNotFound || by.location <= NSMaxRange(link)) return;
        SGAutoEqHeadphone *headphone = [SGAutoEqHeadphone new];
        headphone.name = [line substringWithRange:NSMakeRange(3, link.location - 3)];
        headphone.path = [line substringWithRange:NSMakeRange(NSMaxRange(link), by.location - NSMaxRange(link))];
        headphone.source = [line substringFromIndex:NSMaxRange(by)];
        if (headphone.name.length && headphone.path.length) [headphones addObject:headphone];
    }];
    return headphones;
}

// Decoded and encoded again: INDEX.md leaves some characters raw ("$", "&", parentheses) that a URL may not.
NSURL *SGAutoEqGraphicEqURL(NSString *path) {
    NSString *folder = path.stringByRemovingPercentEncoding ?: path;
    NSString *file = [NSString stringWithFormat:@"%@/%@ GraphicEQ.txt", folder, folder.lastPathComponent];
    NSString *encoded = [file stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet];
    return encoded ? [NSURL URLWithString:[kResults stringByAppendingString:encoded]] : nil;
}

NSString *SGAutoEqNameOf(NSString *path) {
    NSString *folder = path.stringByRemovingPercentEncoding ?: path;
    return folder.lastPathComponent;
}

NSArray<SGAutoEqHeadphone *> *SGAutoEqSearch(NSArray<SGAutoEqHeadphone *> *all, NSString *query) {
    NSStringCompareOptions loose = NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch;
    NSArray<NSString *> *words = [query componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    words = [words filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
    if (!words.count) return all;
    NSMutableArray<SGAutoEqHeadphone *> *found = [NSMutableArray array];
    for (SGAutoEqHeadphone *headphone in all) {
        NSString *text = [NSString stringWithFormat:@"%@ %@", headphone.name, headphone.source];
        BOOL match = YES;
        for (NSString *word in words) match = match && [text rangeOfString:word options:loose].location != NSNotFound;
        if (match) [found addObject:headphone];
    }
    return found;
}

NSArray<SGAutoEqHeadphone *> *SGAutoEqFilterByForm(NSArray<SGAutoEqHeadphone *> *all, SGAutoEqForm form) {
    static NSString *const words[] = {nil, @"in-ear", @"over-ear", @"earbud"};
    if (form == SGAutoEqFormAll) return all;
    NSMutableArray<SGAutoEqHeadphone *> *found = [NSMutableArray array];
    for (SGAutoEqHeadphone *headphone in all) {
        NSString *folder = headphone.path.stringByRemovingPercentEncoding ?: headphone.path;
        if ([folder rangeOfString:words[form] options:NSCaseInsensitiveSearch].location != NSNotFound) [found addObject:headphone];
    }
    return found;
}

#pragma mark - downloads

static NSURL *cachedIndex(void) {
    NSURL *folder = [SGDataRoot(NSCachesDirectory) URLByAppendingPathComponent:@"AutoEq" isDirectory:YES];
    if (!folder) return nil;
    [NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil];
    return [folder URLByAppendingPathComponent:@"INDEX.md"];
}

// The body of a 200 answer as text, or nil and why not. `done` on URLSession's queue, not the main one.
static void fetchText(NSURL *url, void (^done)(NSString *text, NSString *error)) {
    NSURLRequest *request = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:30];
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        NSString *text = status == 200 && data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
        NSString *why = text ? nil : error ? error.localizedDescription : [NSString stringWithFormat:SGL(@"settings.audioeffects.autoeq.error.github_status", @"GitHub answered %ld"), (long)status];
        if (why) SGLog(@"autoeq: %@ failed (%@)", url.path, why);
        done(text, why);
    }] resume];
}

void SGAutoEqLoadIndex(BOOL refresh, void (^done)(NSArray<SGAutoEqHeadphone *> *, NSString *)) {
    NSURL *cache = cachedIndex();
    NSDate *saved = [NSFileManager.defaultManager attributesOfItemAtPath:cache.path error:nil].fileModificationDate;
    void (^fromCache)(NSString *) = ^(NSString *why) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSString *text = [NSString stringWithContentsOfURL:cache encoding:NSUTF8StringEncoding error:nil];
            NSArray<SGAutoEqHeadphone *> *headphones = text ? SGAutoEqParseIndex(text) : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                // A failed refresh still says so over the saved list.
                done(headphones.count ? headphones : nil, why ?: (headphones.count ? nil : SGL(@"settings.audioeffects.autoeq.error.cache_read", @"The saved list could not be read")));
            });
        });
    };
    if (saved && !refresh && -saved.timeIntervalSinceNow < kIndexLife) {
        fromCache(nil);
        return;
    }
    // Its 8850 lines are read and saved off the main thread, which has only the answer.
    fetchText([NSURL URLWithString:[kResults stringByAppendingString:@"INDEX.md"]], ^(NSString *text, NSString *error) {
        // A page that answers but holds no headphones is not kept over a good copy.
        NSArray<SGAutoEqHeadphone *> *headphones = text ? SGAutoEqParseIndex(text) : nil;
        if (!headphones.count) {
            fromCache(error ?: SGL(@"settings.audioeffects.autoeq.error.empty_list", @"AutoEq's list has no headphones in it"));
            return;
        }
        [text writeToURL:cache atomically:YES encoding:NSUTF8StringEncoding error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{ done(headphones, nil); });
    });
}

#pragma mark - a correction per output

static NSString *sg_outputUID, *sg_outputName;
static NSUInteger sg_pickGeneration;

static NSDictionary<NSString *, NSDictionary *> *outputs(void) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:SGKeyDSPOutputs];
    return [value isKindOfClass:NSDictionary.class] ? value : @{};
}

static void setOutput(NSString *uid, NSDictionary *entry) {
    NSMutableDictionary *all = [outputs() mutableCopy];
    all[uid] = entry;
    [NSUserDefaults.standardUserDefaults setObject:all forKey:SGKeyDSPOutputs];
}

static NSString *followed(void) {
    return [NSUserDefaults.standardUserDefaults stringForKey:SGKeyDSPOutputFollowed] ?: @"";
}

static void setFollowed(NSString *uid) {
    [NSUserDefaults.standardUserDefaults setObject:uid ?: @"" forKey:SGKeyDSPOutputFollowed];
}

static void changed(void) {
    [NSNotificationCenter.defaultCenter postNotificationName:SGAutoEqOutputsChangedNotification object:nil];
}

// A headphone's correction is what the Graphic EQ plays, rather than nothing or the user's own curve.
BOOL SGAutoEqCorrectionInUse(void) {
    return SGDSPSwitch(SGKeyDSPGraphicEq) && SGDSPString(SGKeyDSPGraphicEqHeadphone).length;
}

static void takeOff(void) {
    if (!SGAutoEqCorrectionInUse()) return;
    SGDSPSetString(SGKeyDSPGraphicEqHeadphone, @"");
    SGDSPSetSwitch(SGKeyDSPGraphicEq, NO);
}

// The output playing now remembers what the Graphic EQ plays, when it is remembered.
static void rememberPick(void) {
    if (!sg_outputUID.length || !outputs()[sg_outputUID]) return;
    BOOL on = SGAutoEqCorrectionInUse();
    NSMutableDictionary *entry = [outputs()[sg_outputUID] mutableCopy];
    entry[@"name"] = sg_outputName ?: sg_outputUID;
    entry[@"path"] = on ? SGDSPString(SGKeyDSPGraphicEqHeadphone) : @"";
    entry[@"nodes"] = on ? SGDSPString(SGKeyDSPGraphicEqNodes) : @"";
    setOutput(sg_outputUID, entry);
    setFollowed(sg_outputUID);
    changed();
}

BOOL SGAutoEqApplyText(NSString *path, NSString *text) {
    NSString *line = SGDSPGraphicEqLine(text);
    if (!line || !path.length) return NO;
    ++sg_pickGeneration;
    SGDSPSetString(SGKeyDSPGraphicEqNodes, line);
    SGDSPSetString(SGKeyDSPGraphicEqHeadphone, path);
    SGDSPSetSwitch(SGKeyDSPGraphicEq, YES);
    // The correction is meant to be heard: the master switch, off until asked for, comes on with it.
    if (!SGDSPSwitch(SGKeyDSP)) SGDSPSetSwitch(SGKeyDSP, YES);
    rememberPick();
    return YES;
}

void SGAutoEqTakeOff(void) {
    ++sg_pickGeneration;
    takeOff();
    rememberPick();
}

#pragma mark - a preset per output

static NSDictionary *storedBaseline(void) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:SGKeyDSPOutputBaseline];
    return [value isKindOfClass:NSDictionary.class] && [value[@"values"] isKindOfClass:NSDictionary.class]
           && [value[@"applied"] isKindOfClass:NSString.class] ? value : nil;
}

// The user's preset the entry names, as the values to apply: the preset's, with the entry's remembered
// correction over its Graphic EQ. Nil for None and for a preset since deleted.
static NSDictionary<NSString *, id> *presetValuesFor(NSDictionary *entry) {
    NSString *name = [entry[@"preset"] isKindOfClass:NSString.class] ? entry[@"preset"] : nil;
    NSDictionary<NSString *, id> *preset = name.length ? SGDSPUserPresetValues(name) : nil;
    if (!preset) return nil;
    NSMutableDictionary<NSString *, id> *values = [preset mutableCopy];
    NSString *path = entry[@"path"], *nodes = entry[@"nodes"];
    if (path.length && nodes.length) {
        values[SGKeyDSPGraphicEq] = @YES;
        values[SGKeyDSPGraphicEqNodes] = nodes;
        values[SGKeyDSPGraphicEqHeadphone] = path;
    }
    return values;
}

// The baseline is stored, with the digest of what is about to be applied, before anything is: a launch killed
// in between finds both. Moving between outputs with a preset keeps the first baseline. The baseline names the
// output the preset was applied for, so a relaunch on that output can tell it was never left, and is pending
// until the apply is done, so a launch can tell values the apply left half-way from the user's own edits.
static void applyPreset(NSDictionary<NSString *, id> *values, NSString *outputUID) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    NSDictionary *saved = storedBaseline();
    if (!saved && followed().length) takeOff();   // another output's correction is not the user's to keep
    NSDictionary *before = saved ? saved[@"values"] : SGDSPCurrentValues();
    NSDictionary *done = @{@"values": before, @"applied": SGDSPValuesDigest(values), @"output": outputUID};
    NSMutableDictionary *pending = [done mutableCopy];
    pending[@"pending"] = @YES;
    [store setObject:pending forKey:SGKeyDSPOutputBaseline];
    setFollowed(@"");
    SGDSPApplyValues(values);
    [store setObject:done forKey:SGKeyDSPOutputBaseline];
}

// The user's values come back when they are what the preset left (or an apply or an earlier restore was cut
// short); otherwise they changed something and keep it. Either way the baseline goes, after the restore is
// done. It is pending while the restore runs, so a launch that finds it half-done puts the values back again:
// applying them is the same each time.
static void leavePreset(NSDictionary *saved) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    BOOL untouched = [saved[@"pending"] boolValue] || [SGDSPValuesDigest(SGDSPCurrentValues()) isEqualToString:saved[@"applied"]];
    if (untouched) {
        NSMutableDictionary *restoring = [saved mutableCopy];
        restoring[@"pending"] = @YES;
        [store setObject:restoring forKey:SGKeyDSPOutputBaseline];
        SGDSPApplyValues(saved[@"values"]);
    }
    SGLog(@"autoeq: left a preset, %@", untouched ? @"the earlier values are back" : @"the values changed meanwhile, kept");
    setFollowed(@"");
    [store removeObjectForKey:SGKeyDSPOutputBaseline];
}

// `launch`: the first output this process hears of, which may be the one the last launch was killed on.
static void arriveAtOutput(BOOL launch) {
    ++sg_pickGeneration;
    NSString *uid = sg_outputUID;
    NSDictionary *entry = outputs()[uid];
    if (entry && ![entry[@"name"] isEqual:sg_outputName]) {
        NSMutableDictionary *renamed = [entry mutableCopy];
        renamed[@"name"] = sg_outputName;
        setOutput(uid, renamed);
        entry = renamed;
    }
    NSDictionary<NSString *, id> *preset = presetValuesFor(entry);
    NSDictionary *saved = storedBaseline();
    if (preset) {
        // Still on the output the preset was applied for: entered already, so the user's edits since stay, and
        // the baseline with its digest, which they will differ from when this output is left.
        if (launch && [saved[@"output"] isEqual:uid] && ![saved[@"pending"] boolValue]) {
            SGLog(@"autoeq: %@ is where the last launch ended, its preset %@ stays as it is", sg_outputName, entry[@"preset"]);
            changed();
            return;
        }
        applyPreset(preset, uid);
        SGLog(@"autoeq: %@ connected, its preset %@ applied", sg_outputName, entry[@"preset"]);
        changed();
        return;
    }
    if (saved) leavePreset(saved);
    if (entry) {
        NSString *path = entry[@"path"], *nodes = entry[@"nodes"];
        if (path.length && nodes.length) {
            SGDSPSetString(SGKeyDSPGraphicEqNodes, nodes);
            SGDSPSetString(SGKeyDSPGraphicEqHeadphone, path);
            SGDSPSetSwitch(SGKeyDSPGraphicEq, YES);
            SGLog(@"autoeq: %@ connected, its correction %@ on%@", sg_outputName, SGAutoEqNameOf(path), SGDSPSwitch(SGKeyDSP) ? @"" : @" (Audio effects are off)");
        } else {
            takeOff();
            SGLog(@"autoeq: %@ connected, None remembered for it", sg_outputName);
        }
        setFollowed(uid);
    } else if (followed().length) {
        // The correction came on for another output; this one has none.
        if (SGAutoEqCorrectionInUse()) SGLog(@"autoeq: %@ connected, with no correction remembered: %@ off", sg_outputName, SGAutoEqNameOf(SGDSPString(SGKeyDSPGraphicEqHeadphone)));
        takeOff();
        setFollowed(@"");
    }
    changed();
}

void SGAutoEqOutputChanged(NSString *uid, NSString *name) {
    if (!uid.length || [uid isEqualToString:sg_outputUID]) return;
    BOOL launch = !sg_outputUID;
    sg_outputUID = [uid copy];
    sg_outputName = name.length ? [name copy] : sg_outputUID;
    arriveAtOutput(launch);
}

void SGAutoEqPresetDeleted(NSString *name) {
    NSMutableDictionary<NSString *, NSDictionary *> *all = [outputs() mutableCopy];
    BOOL playing = NO, any = NO;
    for (NSString *uid in outputs()) {
        if (![outputs()[uid][@"preset"] isEqual:name]) continue;
        NSMutableDictionary *entry = [outputs()[uid] mutableCopy];
        [entry removeObjectForKey:@"preset"];
        all[uid] = entry;
        any = YES;
        playing = playing || [uid isEqualToString:sg_outputUID];
    }
    if (!any) return;
    [NSUserDefaults.standardUserDefaults setObject:all forKey:SGKeyDSPOutputs];
    if (playing) arriveAtOutput(NO);
    else changed();
}

void SGAutoEqSetOutputPreset(NSString *name) {
    if (!sg_outputUID.length || (!name.length && ![SGAutoEqOutputPreset(sg_outputUID) length])) return;
    if (!SGAutoEqOutputRemembered(sg_outputUID)) SGAutoEqRememberOutput(YES);
    NSMutableDictionary *entry = [outputs()[sg_outputUID] mutableCopy];
    if (name.length) entry[@"preset"] = name;
    else [entry removeObjectForKey:@"preset"];
    setOutput(sg_outputUID, entry);
    arriveAtOutput(NO);
}

NSString *SGAutoEqOutputPreset(NSString *uid) {
    id name = outputs()[uid][@"preset"];
    return [name isKindOfClass:NSString.class] ? name : @"";
}

NSString *SGAutoEqOutputUID(void) {
    return sg_outputUID;
}

NSString *SGAutoEqOutputName(void) {
    return sg_outputName;
}

void SGAutoEqRememberOutput(BOOL remember) {
    if (!sg_outputUID.length) return;
    if (!remember) {
        SGAutoEqForgetOutput(sg_outputUID);
        return;
    }
    if (!outputs()[sg_outputUID]) setOutput(sg_outputUID, @{@"name": sg_outputName, @"path": @"", @"nodes": @""});
    rememberPick();
}

BOOL SGAutoEqOutputRemembered(NSString *uid) {
    return uid.length && outputs()[uid] != nil;
}

// What plays stays: forgetting an output does not take its correction off now.
void SGAutoEqForgetOutput(NSString *uid) {
    if (!uid.length) return;
    NSMutableDictionary *all = [outputs() mutableCopy];
    [all removeObjectForKey:uid];
    [NSUserDefaults.standardUserDefaults setObject:all forKey:SGKeyDSPOutputs];
    if ([followed() isEqualToString:uid]) setFollowed(@"");
    changed();
}

NSArray<NSDictionary<NSString *, NSString *> *> *SGAutoEqRememberedOutputs(void) {
    NSMutableArray *list = [NSMutableArray array];
    [outputs() enumerateKeysAndObjectsUsingBlock:^(NSString *uid, NSDictionary *entry, BOOL *stop) {
        if (![entry isKindOfClass:NSDictionary.class]) return;
        [list addObject:@{@"uid": uid, @"name": entry[@"name"] ?: uid, @"path": entry[@"path"] ?: @"", @"preset": SGAutoEqOutputPreset(uid)}];
    }];
    [list sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)]]];
    return list;
}

void SGAutoEqApply(SGAutoEqHeadphone *headphone, void (^done)(NSString *)) {
    NSURL *url = SGAutoEqGraphicEqURL(headphone.path);
    if (!url) {
        done(SGL(@"settings.audioeffects.autoeq.error.invalid_url", @"Its address could not be made"));
        return;
    }
    NSString *outputUID = [sg_outputUID copy];
    NSUInteger generation = ++sg_pickGeneration;
    NSUInteger revision = SGDSPGraphicEqRevision();
    fetchText(url, ^(NSString *text, NSString *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // A pick, an output change, or any write to the curve or headphone since the request makes it stale.
            if (generation != sg_pickGeneration || revision != SGDSPGraphicEqRevision()
                || !(outputUID == sg_outputUID || [outputUID isEqualToString:sg_outputUID])) {
                // Complete the UI request without applying or remembering stale audio.
                done(nil);
                return;
            }
            if (error) done(error);
            else done(SGAutoEqApplyText(headphone.path, text) ? nil : SGL(@"settings.audioeffects.autoeq.error.invalid_format", @"The file is not a GraphicEQ line"));
        });
    });
}

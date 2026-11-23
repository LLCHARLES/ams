// Checks Presets and Headphones (Shared/AudioEffects/AudioEffectsPresets.h) on the Mac: INDEX.md's parsing on
// lines written to be awkward, the raw addresses made from them, search, correction selection races
// through the real settings, and, with `online`, AutoEq's real index fetched, cached and one headphone applied.
//
//     ./build.sh && build/autoeq-check [online]
//
// Every line prints ok or FAIL; the exit status is the number of failures. The settings live in the check's
// own defaults domain, cleared before and after.
#import <Foundation/Foundation.h>
#import "AudioEffects.h"
#import "AudioEffectsApply.h"
#import "AudioEffectsPresets.h"

static int failures;

// URLSession transport double: the test decides when each response arrives.
static NSMutableArray<NSURLProtocol *> *pending;
@interface AuditProtocol : NSURLProtocol
- (void)finish;
@end
@implementation AuditProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    return [request.URL.path containsString:@"/Audit/"];
}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    dispatch_async(dispatch_get_main_queue(), ^{ [pending addObject:self]; });
}
- (void)stopLoading {}
- (void)finish {
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:nil];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:[@"GraphicEQ: 20 -9;" dataUsingEncoding:NSUTF8StringEncoding]];
    [self.client URLProtocolDidFinishLoading:self];
}
@end

static void check(BOOL ok, NSString *what) {
    printf("%s %s\n", ok ? "ok  " : "FAIL", what.UTF8String);
    failures += !ok;
}

// The engine is not here: what it was handed is counted instead.
static NSCountedSet<NSString *> *applied;
void SGDSPApply(NSString *effect) {
    [applied addObject:effect];
}

static void clearDefaults(void) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    for (NSString *key in store.dictionaryRepresentation) {
        if ([key hasPrefix:@"spotifyglass."]) [store removeObjectForKey:key];
    }
}

// Runs the main queue until `done` says so, the way the app's run loop would.
static void waitFor(BOOL (^done)(void)) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:60];
    while (!done() && limit.timeIntervalSinceNow > 0) [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}

static void checkParsing(void) {
    NSString *index =
        @"# Index\n"
        @"This is a list of all equalization profiles. Target is in parentheses if there are results with multiple targets\n"
        @"from the same source.\n\n"
        @"- [1Custom SA02](./crinacle/711%20in-ear/1Custom%20SA02) by crinacle on 711\n"
        @"- [1MORE Aero (ANC Off)](./HypetheSonics/GRAS%20RA0045%20in-ear/1MORE%20Aero%20(ANC%20Off)) by HypetheSonics on GRAS RA0045\n"
        @"- [Sennheiser HD 600](./oratory1990/over-ear/Sennheiser%20HD%20600) by oratory1990\n"
        @"- [AKG K371 [Harman] (Bass)](./Rtings/over-ear/AKG%20K371%20(Bass)) by Rtings\n"
        @"- [Sennheiser HD 600](./crinacle/GRAS%2043AG-7%20over-ear/Sennheiser%20HD%20600) by crinacle on GRAS 43AG-7\n"
        @"- [Sony WH-1000XM4 & $50 tips](./Super%20Review/over-ear/Sony%20WH-1000XM4%20&%20$50%20tips) by Super Review\n"
        @"- not a link\n"
        @"- [Broken](./no/closing by nobody\n";
    NSArray<SGAutoEqHeadphone *> *all = SGAutoEqParseIndex(index);
    check(all.count == 6, [NSString stringWithFormat:@"6 headphones parsed, the heading and the broken lines skipped (%lu)", (unsigned long)all.count]);
    if (all.count < 6) return;
    check([all[1].name isEqualToString:@"1MORE Aero (ANC Off)"] && [all[1].path isEqualToString:@"HypetheSonics/GRAS%20RA0045%20in-ear/1MORE%20Aero%20(ANC%20Off)"]
          && [all[1].source isEqualToString:@"HypetheSonics on GRAS RA0045"], @"parentheses in the name and the folder");
    check([all[3].name isEqualToString:@"AKG K371 [Harman] (Bass)"] && [all[3].path isEqualToString:@"Rtings/over-ear/AKG%20K371%20(Bass)"],
          @"brackets in the name");
    check([SGAutoEqGraphicEqURL(all[2].path).absoluteString isEqualToString:
           @"https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/results/oratory1990/over-ear/Sennheiser%20HD%20600/Sennheiser%20HD%20600%20GraphicEQ.txt"],
          @"the raw address of a GraphicEQ file");
    NSString *aero = SGAutoEqGraphicEqURL(all[1].path).absoluteString;
    check([aero hasSuffix:@"/1MORE%20Aero%20(ANC%20Off)/1MORE%20Aero%20(ANC%20Off)%20GraphicEQ.txt"], aero);
    NSString *sony = SGAutoEqGraphicEqURL(all[5].path).absoluteString;
    check([sony hasSuffix:@"/Sony%20WH-1000XM4%20&%20$50%20tips%20GraphicEQ.txt"] && [NSURL URLWithString:sony], sony);
    check([SGAutoEqNameOf(all[2].path) isEqualToString:@"Sennheiser HD 600"], @"a folder's name for the page's row");

    check(SGAutoEqSearch(all, @"hd 600").count == 2, @"search: two HD 600s");
    check(SGAutoEqSearch(all, @"  HD600 ").count == 0, @"search: words, not a squashed name");
    check(SGAutoEqSearch(all, @"600 ORATORY").count == 1, @"search: any order, any case, the source too");
    check(SGAutoEqSearch(all, @"").count == 6, @"search: empty shows all");
}

// The form filter on a sample INDEX.md: the folder's text decides, case aside; a folder that says none shows under All only.
static NSString *sg_sampleIndexPath;   // next to this file, whatever folder the check runs from

static void checkForms(void) {
    NSString *index = [NSString stringWithContentsOfFile:sg_sampleIndexPath encoding:NSUTF8StringEncoding error:nil];
    NSArray<SGAutoEqHeadphone *> *all = SGAutoEqParseIndex(index);
    check(all.count == 7, @"the sample index has 7 headphones");
    NSArray<NSString *> *(^names)(SGAutoEqForm) = ^NSArray<NSString *> *(SGAutoEqForm form) {
        return [[SGAutoEqFilterByForm(all, form) valueForKey:@"name"] sortedArrayUsingSelector:@selector(compare:)];
    };
    check(SGAutoEqFilterByForm(all, SGAutoEqFormAll).count == 7, @"All shows every headphone, those with no form too");
    check([names(SGAutoEqFormInEar) isEqualToArray:(@[@"1MORE Quad Driver", @"Etymotic ER4SR"])], @"In-ear: the folders saying in-ear, in any case");
    check([names(SGAutoEqFormOverEar) isEqualToArray:(@[@"AKG K371", @"Sennheiser HD 600"])], @"Over-ear: the folders saying over-ear, in any case");
    check([names(SGAutoEqFormEarbuds) isEqualToArray:(@[@"Apple EarPods", @"Moondrop Chu"])], @"Earbuds: the folders saying earbud, singular or plural");
    NSArray<SGAutoEqHeadphone *> *searched = SGAutoEqSearch(all, @"rtings");
    check(SGAutoEqFilterByForm(searched, SGAutoEqFormInEar).count == 0, @"a form that leaves nothing leaves an empty list (the page says No headphones match)");
    check(SGAutoEqFilterByForm(searched, SGAutoEqFormEarbuds).count == 1, @"a form filters a search's result");
}

static void checkPresets(void) {
    clearDefaults();
    NSString *line = SGDSPGraphicEqLine(@"  GraphicEQ: 20 -1.2;\n 21 -1.1;\n\n");
    check([line isEqualToString:@"GraphicEQ: 20 -1.2; 21 -1.1;"], @"a GraphicEQ file's text onto one line");
    check(SGDSPGraphicEqLine(@"Preamp: -6 dB") == nil, @"other text is not a GraphicEQ line");

    // A headphone's correction in place, and other effects on.
    check(SGAutoEqApplyText(@"oratory1990/over-ear/Sennheiser%20HD%20600", @"GraphicEQ: 20 -1.2; 21 -1.1;\n"), @"a GraphicEQ file applied");
    check(SGDSPSwitch(SGKeyDSPGraphicEq) && [SGDSPString(SGKeyDSPGraphicEqNodes) isEqualToString:@"GraphicEQ: 20 -1.2; 21 -1.1;"]
          && [SGDSPString(SGKeyDSPGraphicEqHeadphone) isEqualToString:@"oratory1990/over-ear/Sennheiser%20HD%20600"],
          @"the Graphic EQ on, with the nodes and the headphone");
    check([applied countForObject:SGKeyDSPGraphicEq] > 0, @"the Graphic EQ handed to the engine");
    check(SGDSPSwitch(SGKeyDSP) && [applied countForObject:SGKeyDSP] > 0, @"the effects' master switch on with the headphone");
    check(!SGAutoEqApplyText(@"a/b", @"<html>404</html>"), @"a page that is not GraphicEQ is refused");
}

// A download of `headphone` held in flight while `during` edits the settings, then released: `expected` says
// what the settings must hold afterwards, and the request's callback must have been completed.
static void checkEditDuringDownload(NSString *what, SGAutoEqHeadphone *headphone, void (^during)(void), BOOL (^expected)(void)) {
    [pending removeAllObjects];
    __block BOOL done = NO;
    SGAutoEqApply(headphone, ^(NSString *error) { done = YES; });
    waitFor(^BOOL { return pending.count == 1; });
    if (pending.count != 1) { check(NO, [what stringByAppendingString:@": download intercepted"]); return; }
    during();
    [(AuditProtocol *)pending[0] finish];
    waitFor(^BOOL { return done; });
    check(done && expected(), what);
}

static void checkStaleDownload(void) {
    pending = [NSMutableArray array];
    [NSURLProtocol registerClass:AuditProtocol.class];
    SGAutoEqOutputChanged(@"audit-A", @"A");
    SGAutoEqHeadphone *headphone = [SGAutoEqHeadphone new];
    headphone.path = @"Audit/A";
    __block BOOL done = NO;
    SGAutoEqApply(headphone, ^(NSString *error) { done = YES; });
    waitFor(^BOOL { return pending.count == 1; });
    check(pending.count == 1, @"download intercepted without networking");
    if (pending.count != 1) return;
    SGAutoEqOutputChanged(@"audit-B", @"B");
    SGAutoEqRememberOutput(YES);
    SGAutoEqApplyText(@"Audit/B", @"GraphicEQ: 20 -3;");
    [(AuditProtocol *)pending[0] finish];
    waitFor(^BOOL { return done; });
    check(done && [SGDSPString(SGKeyDSPGraphicEqNodes) isEqualToString:@"GraphicEQ: 20 -3;"],
          @"A's late download leaves B's active correction unchanged");
    SGAutoEqOutputChanged(@"audit-A", @"A");
    SGAutoEqOutputChanged(@"audit-B", @"B");
    check([SGDSPString(SGKeyDSPGraphicEqNodes) isEqualToString:@"GraphicEQ: 20 -3;"],
          @"A's late download leaves B's remembered correction unchanged");

    [pending removeAllObjects];
    done = NO;
    SGAutoEqApply(headphone, ^(NSString *error) { done = YES; });
    waitFor(^BOOL { return pending.count == 1; });
    if (pending.count != 1) { check(NO, @"second download intercepted"); return; }
    SGAutoEqTakeOff();
    [(AuditProtocol *)pending[0] finish];
    waitFor(^BOOL { return done; });
    check(done && !SGDSPSwitch(SGKeyDSPGraphicEq), @"a newer None pick cancels the pending correction");

    // Edits made while a download is in flight, through the same setters the pages use.
    checkEditDuringDownload(@"nothing in between: the download is applied", headphone, ^{}, ^BOOL {
        return SGDSPSwitch(SGKeyDSPGraphicEq) && [SGDSPString(SGKeyDSPGraphicEqNodes) isEqualToString:@"GraphicEQ: 20 -9;"]
               && [SGDSPString(SGKeyDSPGraphicEqHeadphone) isEqualToString:@"Audit/A"];
    });
    checkEditDuringDownload(@"a saved or pasted curve (the Graphic EQ editor's save)", headphone, ^{
        SGDSPSetString(SGKeyDSPGraphicEqHeadphone, @"");
        SGDSPSetString(SGKeyDSPGraphicEqNodes, @"GraphicEQ: 100 4;");
    }, ^BOOL {
        return [SGDSPString(SGKeyDSPGraphicEqNodes) isEqualToString:@"GraphicEQ: 100 4;"] && !SGDSPString(SGKeyDSPGraphicEqHeadphone).length;
    });
    checkEditDuringDownload(@"a built-in preset loaded", headphone, ^{
        SGDSPSetString(SGKeyDSPGraphicEqHeadphone, @"Audit/Kept");
        SGDSPSetString(SGKeyDSPGraphicEqNodes, @"GraphicEQ: 200 5;");
        SGDSPLoadBuiltInPreset(0);
    }, ^BOOL {
        return [SGDSPString(SGKeyDSPGraphicEqNodes) isEqualToString:@"GraphicEQ: 200 5;"]
               && [SGDSPString(SGKeyDSPGraphicEqHeadphone) isEqualToString:@"Audit/Kept"];
    });
    checkEditDuringDownload(@"a user preset loaded", headphone, ^{
        SGDSPSaveUserPreset(@"Audit mine");
        SGDSPSetString(SGKeyDSPGraphicEqHeadphone, @"");
        SGDSPSetString(SGKeyDSPGraphicEqNodes, @"GraphicEQ: 300 6;");
        SGDSPLoadUserPreset(@"Audit mine");
    }, ^BOOL {
        return [SGDSPString(SGKeyDSPGraphicEqNodes) isEqualToString:@"GraphicEQ: 200 5;"]
               && [SGDSPString(SGKeyDSPGraphicEqHeadphone) isEqualToString:@"Audit/Kept"];
    });
    checkEditDuringDownload(@"a reset", headphone, ^{ SGDSPResetAll(); }, ^BOOL {
        return !SGDSPSwitch(SGKeyDSPGraphicEq) && !SGDSPString(SGKeyDSPGraphicEqHeadphone).length
               && [SGDSPString(SGKeyDSPGraphicEqNodes) isEqualToString:@"GraphicEQ: 0.0 0.0;"];
    });
    [NSURLProtocol unregisterClass:AuditProtocol.class];
}

static void checkOnline(void) {
    clearDefaults();
    __block NSArray<SGAutoEqHeadphone *> *all;
    __block NSString *error;
    __block BOOL done = NO;
    SGAutoEqLoadIndex(YES, ^(NSArray<SGAutoEqHeadphone *> *headphones, NSString *why) {
        all = headphones, error = why, done = YES;
    });
    waitFor(^BOOL { return done; });
    check(all.count > 5000 && !error, [NSString stringWithFormat:@"AutoEq's index fetched: %lu headphones (%@)", (unsigned long)all.count, error ?: @"no error"]);
    NSURL *caches = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
    NSString *cache = [caches URLByAppendingPathComponent:@"Retrine/AutoEq/INDEX.md"].path;
    check([NSFileManager.defaultManager fileExistsAtPath:cache], @"and cached");

    done = NO;
    __block NSArray<SGAutoEqHeadphone *> *cached;
    SGAutoEqLoadIndex(NO, ^(NSArray<SGAutoEqHeadphone *> *headphones, NSString *why) {
        cached = headphones, done = YES;
    });
    waitFor(^BOOL { return done; });
    check(cached.count == all.count, @"read back from the cache");

    NSArray<SGAutoEqHeadphone *> *found = SGAutoEqSearch(all, @"Sennheiser HD 600 oratory1990");
    check(found.count == 1, [NSString stringWithFormat:@"search: Sennheiser HD 600 by oratory1990 (%lu)", (unsigned long)found.count]);
    if (!found.count) return;
    done = NO;
    error = nil;
    SGAutoEqApply(found[0], ^(NSString *why) {
        error = why, done = YES;
    });
    waitFor(^BOOL { return done; });
    NSString *nodes = SGDSPString(SGKeyDSPGraphicEqNodes);
    check(!error && SGDSPSwitch(SGKeyDSPGraphicEq) && [nodes hasPrefix:@"GraphicEQ: 20 "] && [nodes componentsSeparatedByString:@";"].count > 100
          && [SGDSPString(SGKeyDSPGraphicEqHeadphone) isEqualToString:found[0].path],
          [NSString stringWithFormat:@"HD 600's GraphicEQ downloaded and applied (%@, %lu points)", error ?: @"no error",
           (unsigned long)[nodes componentsSeparatedByString:@";"].count - 1]);

    // Spot-check the rest of the index: each GraphicEQ file is where the address says.
    NSUInteger reached = 0, tried = 0;
    for (NSUInteger i = 0; i < all.count; i += all.count / 12) {
        tried++;
        NSURL *url = SGAutoEqGraphicEqURL(all[i].path);
        NSData *data = [NSData dataWithContentsOfURL:url];
        NSString *text = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
        if (SGDSPGraphicEqLine(text)) reached++;
        else printf("     missing: %s\n", url.absoluteString.UTF8String);
    }
    check(reached == tried, [NSString stringWithFormat:@"%lu of %lu headphones across the index have their GraphicEQ file", (unsigned long)reached, (unsigned long)tried]);
    [NSFileManager.defaultManager removeItemAtPath:cache error:nil];
}

int main(int argc, char **argv) {
    @autoreleasepool {
        // build.sh puts the check in build/, one folder under the sample.
        NSString *binary = [NSString stringWithUTF8String:argv[0]];
        sg_sampleIndexPath = [[[binary stringByDeletingLastPathComponent] stringByDeletingLastPathComponent]
            stringByAppendingPathComponent:@"sample-INDEX.md"];
        applied = [NSCountedSet set];
        checkParsing();
        checkForms();
        checkPresets();
        checkStaleDownload();
        if (argc > 1 && !strcmp(argv[1], "online")) checkOnline();
        clearDefaults();
        printf("%d failed\n", failures);
    }
    return failures;
}

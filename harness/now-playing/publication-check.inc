// Included by artwork.m: publication through the real setter hooks and controlled render queue.
static NSMutableArray<NSDictionary *> *publishedLyricFrames;
static BOOL publicationFixture;
static UIImage *secondFrame;
BOOL harnessMotionSourcesOff;
static BOOL publicationRenderedOnMain, publicationEntered, publicationGateTimedOut, holdPublicationRender;
static dispatch_semaphore_t publicationRelease;
static NSString *heldPublicationLine;
CGImageRef harnessPublicationFrame(NSString *line, CGImageRef backdrop) {
    BOOL hold = NO;
    @synchronized (cacheRoot) {
        if (publicationFixture) {
            publicationRenderedOnMain |= NSThread.isMainThread;
            if (holdPublicationRender && (!heldPublicationLine || [line isEqual:heldPublicationLine])) {
                holdPublicationRender = NO;
                publicationEntered = YES;
                hold = !NSThread.isMainThread;
            }
        }
    }
    if (hold) {
        BOOL timedOut = dispatch_semaphore_wait(publicationRelease, dispatch_time(DISPATCH_TIME_NOW, HarnessWaitSeconds * (int64_t)NSEC_PER_SEC)) != 0;
        @synchronized (cacheRoot) { publicationGateTimedOut = timedOut; }
    }
    // Mark the interrupted ahead render; a fresh request for this line produces green instead.
    if (hold && [line isEqual:@"Pressure target"]) return CGImageRetain(blue.CGImage);
    // Distinct fixture pixels name the two lyric frames, independently of their fallback handler.
    return CGImageRetain(publicationFixture ? ([line isEqual:@"First"] ? red.CGImage : secondFrame.CGImage) : backdrop);
}
void harnessRecordPublished(NSDictionary *info) {
    if (publishedLyricFrames) [publishedLyricFrames addObject:info];
}
void publicationChecks(void) {
    background(@{@"mode": @0, @"darkness": @0});
    secondFrame = image(UIColor.greenColor);
    publicationFixture = YES;
    publicationRelease = dispatch_semaphore_create(0);
    @synchronized (cacheRoot) {
        holdPublicationRender = YES;
        publicationEntered = publicationRenderedOnMain = publicationGateTimedOut = NO;
    }
    nativeInfo(blue);
    // Gate even a prefetched frame so the cold request truly has no frame in this generation yet.
    NSArray *lines = @[lineOf(@"First", 0, 10000), lineOf(@"Not shown", 12000, 20000), lineOf(@"Second", 24000, 30000)];
    track(@"publish-sequence", SGLockArtworkLyrics, nil, lines);
    MPMediaItemArtwork *coldStill = harnessSystem()[MPMediaItemPropertyArtwork];
    check(NSThread.isMainThread, @"ordinary-artwork cold request is made on main");
    UIImage *pending = [coldStill imageWithSize:CGSizeMake(24, 32)];
    check(!pending, @"first cold ordinary request returns nothing while rendering off main");
    check(await(^BOOL { @synchronized (cacheRoot) { return publicationEntered; } }),
          @"cold ordinary request starts the controlled renderer");
    @synchronized (cacheRoot) {
        check(!publicationRenderedOnMain, @"ordinary artwork never renders on the main request thread");
    }
    dispatch_semaphore_signal(publicationRelease);
    check(await(^BOOL {
        return sameImage([harnessSystem()[MPMediaItemPropertyArtwork] imageWithSize:CGSizeMake(24, 32)], red);
    }), @"ready ordinary frame is republished after an off-main render");
    @synchronized (cacheRoot) { check(!publicationGateTimedOut, @"ordinary render was released without a timeout"); }
    id first = artwork();
    MPMediaItemArtwork *firstStill = harnessSystem()[MPMediaItemPropertyArtwork];
    check(firstStill == coldStill, @"ready-frame resend retains the same lyric ID's static artwork");
    check(first && sameImage([firstStill imageWithSize:CGSizeMake(24, 32)], red),
          @"first lyric publication has a composed ordinary artwork fallback");
    check(!sameImage([firstStill imageWithSize:CGSizeMake(24, 32)], blue),
          @"first lyric fallback is not the plain native cover");
    publishedLyricFrames = [NSMutableArray array];
    @synchronized (cacheRoot) {
        holdPublicationRender = YES;
        publicationEntered = NO;
    }
    // Seek past the prefetched line: this ID has no ready preview, but the generation has First.
    position = 24000;
    report();
    check(sameImage([harnessSystem()[MPMediaItemPropertyArtwork] imageWithSize:CGSizeMake(24, 32)], red),
          @"a pending line synchronously returns the ready generation frame instead of nil");
    check(await(^BOOL { @synchronized (cacheRoot) { return publicationEntered; } }),
          @"pending next-line rendering reaches the controlled worker gate");
    dispatch_semaphore_signal(publicationRelease);
    check(await(^BOOL {
        return sameImage([harnessSystem()[MPMediaItemPropertyArtwork] imageWithSize:CGSizeMake(24, 32)], secondFrame);
    }), @"next ordinary frame becomes ready without a native-cover response");
    @synchronized (cacheRoot) { check(!publicationGateTimedOut, @"pending next-line render was released without a timeout"); }
    id second = artwork();
    MPMediaItemArtwork *secondStill = harnessSystem()[MPMediaItemPropertyArtwork];
    // The OS may request its synchronous fallback inside an asynchronous animated-preview callback.
    __block BOOL nestedDone = NO, nestedMatches = NO;
    Preview previewBlock = objc_getAssociatedObject(second, &previewKey);
    previewBlock(CGSizeMake(24, 32), ^(UIImage *frame) {
        BOOL matches = sameImage([secondStill imageWithSize:CGSizeMake(24, 32)], secondFrame);
        dispatch_async(dispatch_get_main_queue(), ^{ nestedMatches = matches; nestedDone = YES; });
    });
    check(await(^BOOL { return nestedDone; }) && nestedMatches,
          @"ordinary fallback can be requested inside the animated-preview completion");
    check(second && second != first && sameImage([secondStill imageWithSize:CGSizeMake(24, 32)], secondFrame),
          @"line change publishes the next lyric still with its animated offer");
    check(secondStill != firstStill, @"a new lyric ID gets a new static artwork object");
    nativeInfo(blue); // Spotify can resend its cover between animated preview and video requests.
    SGNowPlayingSetExtras(@"publication-test", @{MPNowPlayingInfoPropertyInternationalStandardRecordingCode: @"test"}, @"Song");
    check(harnessSystem()[MPMediaItemPropertyArtwork] == secondStill,
          @"same lyric ID retains its static artwork across Spotify and extras resends");
    SGNowPlayingSetExtras(@"publication-test", nil, nil);
    nativeInfo(nil);
    check(harnessSystem()[MPMediaItemPropertyArtwork] == secondStill
          && MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo[MPMediaItemPropertyArtwork] == nil,
          @"removing native artwork preserves lyric identity without feeding composed pixels back");
    nativeInfo(blue);
    check(!sameImage([harnessSystem()[MPMediaItemPropertyArtwork] imageWithSize:CGSizeMake(24, 32)], blue),
          @"native resend between lyric frames never publishes the plain cover");
    check(publishedLyricFrames.count >= 2, @"sequence captures the transition and Spotify resend");
    for (NSDictionary *info in publishedLyricFrames) {
        UIImage *frame = [info[MPMediaItemPropertyArtwork] imageWithSize:CGSizeMake(24, 32)];
        check(sameImage(frame, red) || sameImage(frame, secondFrame),
              @"every system publication between lyric frames has the previous or next composed frame");
    }
    publishedLyricFrames = nil;
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    check(sameImage([secondStill imageWithSize:CGSizeMake(24, 32)], secondFrame),
          @"memory pressure preserves the immediately available composed fallback");
    // Direct mode switch: no Off step, no new native info and no metadata URL completing later.
    drainMain();
    id outgoing = artwork();
    harnessMotionSourcesOff = YES;
    sourceFile = nil;
    choose(SGLockArtworkEverySong);
    check(await(^BOOL { return artwork() && artwork() != outgoing; }), @"Every song publishes after the direct mode switch");
    check(sameImage(preview(artwork()), blue),
          @"direct Lyrics to Every song uses native cover without a Spotify artwork update");
    check(sameImage([UIImage imageWithContentsOfFile:video(artwork()).path], blue),
          @"direct mode switch keeps native pixels in the fallback clip");
    harnessMotionSourcesOff = NO;
    choose(SGLockArtworkOff);
    check(sameImage([harnessSystem()[MPMediaItemPropertyArtwork] imageWithSize:CGSizeMake(24, 32)], blue),
          @"turning lyrics off restores the native cover");
    track(@"pressure-sequence", SGLockArtworkLyrics, nil, @[lineOf(@"First", 0, 10000),
          lineOf(@"Middle", 12000, 20000), lineOf(@"Pressure target", 24000, 30000)]);
    preview(artwork()); // establish preview demand before the next line is offered
    @synchronized (cacheRoot) {
        heldPublicationLine = @"Pressure target";
        holdPublicationRender = YES;
        publicationEntered = NO;
    }
    position = 12000;
    report();
    check(await(^BOOL { @synchronized (cacheRoot) { return publicationEntered; } }),
          @"next-line preview is rendering before the warning, without a request for that line");
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    dispatch_semaphore_signal(publicationRelease);
    position = 24000;
    report();
    check(sameImage(preview(artwork()), secondFrame),
          @"a speculative preview finishing after pressure is not reinserted");
    @synchronized (cacheRoot) {
        heldPublicationLine = nil;
        check(!publicationGateTimedOut, @"held speculative preview was released by the fixture");
    }
    choose(SGLockArtworkOff);
    publicationFixture = NO;
    [NSFileManager.defaultManager removeItemAtURL:cacheRoot error:nil];
}

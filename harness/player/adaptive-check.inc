// A Spotify-unit fixture, driven through the same hooked layout callbacks as the phone scenarios.
static UIButton *lyricsMenuIn(UIView *stage) {
    __block UIButton *menu = nil;
    SGForEachView(stage, ^(UIView *view) {
        if ([view isKindOfClass:UIButton.class] && ((UIButton *)view).showsMenuAsPrimaryAction && !view.hidden) menu = (UIButton *)view;
    });
    return menu;
}

- (void)runOpeningChecks {
    HARNESS_CHECK(self.window.bounds.size.width > self.window.bounds.size.height);
    HARNESS_CHECK(SGRPlayerIPadRegular(_host) && SGPlayerState().isPlaying);
    UIView *bottom = SGRFindByIdentifier(_host, @"npv.bottomStackView", NULL);
    CGFloat fullHeight = self.window.rootViewController.view.bounds.size.height;
    NSArray<NSNumber *> *heights = getenv("HARNESS_SHORT") ? @[@200, @320, @480] :
                                                             @[@200, @320, @480, @720, @(fullHeight)];
    __block NSUInteger step = 0;
    [NSTimer scheduledTimerWithTimeInterval:1.0 / 60 repeats:YES block:^(NSTimer *timer) {
        CGFloat height = heights[step++].doubleValue;
        self->_host.frame = CGRectMake(0, 0, self->_host.bounds.size.width, height);
        self->_openingSingleFrame = CGRectMake(0, height - bottom.bounds.size.height - 61.33,
                                               self->_host.bounds.size.width, bottom.bounds.size.height);
        bottom.frame = self->_openingSingleFrame;
        [self layOut];
        if (step != heights.count) return;
        [timer invalidate];
        [self checkOpeningSettles];
    }];
}

- (void)checkOpeningSettles {
    __block unsigned lastPasses = atomic_load(&openingLayoutPasses);
    // Compare completed layout frames, not elapsed time while the VM may be descheduled.
    __block NSUInteger idleFrames = 0;
    SGRHarnessFrameCheck *frame = [SGRHarnessFrameCheck new];
    frame.check = ^BOOL {
        [self->_host layoutIfNeeded];
        unsigned passes = atomic_load(&openingLayoutPasses);
        if (passes != lastPasses) {
            lastPasses = passes;
            idleFrames = 0;
            return NO;
        }
        if (++idleFrames < 2) return NO;
        if (!getenv("HARNESS_SHORT") && !getenv("HARNESS_NO_ARTWORK") && !SGRPlayerTwoColumns()) return NO;
        NSLog(@"[harness] opening settled: %u host layout passes", passes);
        if (getenv("HARNESS_NO_ARTWORK")) HARNESS_CHECK(SGRNowPlayingArtwork(NULL, NULL) == nil);
        if (getenv("HARNESS_NO_ARTWORK") || getenv("HARNESS_SHORT")) {
            HARNESS_CHECK(!SGRPlayerTwoColumns());
            // An unchanged Spotify layout notification must not start another layout transaction.
            [self->_units.lastObject viewDidLayoutSubviews];
            [self->_host layoutIfNeeded];
            unsigned extra = atomic_load(&openingLayoutPasses) - passes;
            if (extra) HARNESS_FAIL(@"unchanged fallback caused %u extra host layouts", extra);
        } else {
            HARNESS_CHECK(SGRPlayerTwoColumns());
            UIView *bottom = SGRFindByIdentifier(self->_host, @"npv.bottomStackView", NULL);
            CGRect moved = bottom.frame;
            moved.origin.y -= 12;
            moved.size.height += 8;
            bottom.frame = moved;
            [self layOut];
            CGRect expected = self->_openingSingleFrame;
            expected.origin.y -= 12;
            expected.size.height += 8;
            self.window.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClassCompact;
            [self layOut];
            if (!CGRectEqualToRect(bottom.frame, expected)) {
                HARNESS_FAIL(@"vertical-change restoration %@, expected %@", NSStringFromCGRect(bottom.frame), NSStringFromCGRect(expected));
            }
        }
        dispatch_semaphore_signal(openingFinished);
        NSLog(@"[harness] adaptive checks: PASS (opening)");
        fflush(stdout);
        return YES;
    };
    CADisplayLink *link = [CADisplayLink displayLinkWithTarget:frame selector:@selector(frame:)];
    [link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)runAdaptiveChecks {
    BOOL checkCompactHeader = !getenv("HARNESS_NO_LYRICS");
    BOOL checkLandscapeBadge = getenv("HARNESS_LANDSCAPE") != NULL;
    __block CGRect originalHost, originalBand;
    __block UIUserInterfaceSizeClass originalWidthClass;
    __block UIView *compactOverlay;
    runScript(@[
        @[^BOOL {
            return SGRNowPlayingArtwork(NULL, NULL) != nil;
        }, ^{
            [self layOut];
            [self layOut];
            BOOL wide = UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad && !getenv("HARNESS_COMPACT");
            UIView *bottom = SGRFindByIdentifier(self->_host, @"npv.bottomStackView", NULL);
            if (!wide) {
                HARNESS_CHECK(!SGRPlayerTwoColumns());
                HARNESS_CHECK(fabs(bottom.frame.size.width - self->_host.bounds.size.width) < 1);
                HARNESS_CHECK(!SGRPlayerLyricsOpen());
            } else {
                HARNESS_CHECK(SGRPlayerTwoColumns());
                HARNESS_CHECK(getenv("HARNESS_NO_LYRICS") ? SGRPlayerQueueSideShown() : SGRPlayerLyricsOpen());
                UIView *overlay = firstOfClass(self->_host, @"SGRPlayerLyricsOverlay");
                UIView *stage = [overlay valueForKey:@"stage"], *cover = [overlay valueForKey:@"thumb"];
                CGRect art = [cover convertRect:cover.bounds toView:self->_host];
                CGRect side = [stage convertRect:stage.bounds toView:self->_host];
                CGRect controls = [bottom convertRect:bottom.bounds toView:self->_host];
                BOOL rtl = getenv("HARNESS_RTL") != NULL;
                HARNESS_CHECK(art.size.width >= 72 && fabs(art.size.width - art.size.height) < 1);
                HARNESS_CHECK(CGRectGetMaxY(art) <= CGRectGetMinY(controls));
                HARNESS_CHECK(rtl ? CGRectGetMaxX(side) <= CGRectGetMinX(controls) :
                                   CGRectGetMaxX(controls) <= CGRectGetMinX(side));
                HARNESS_CHECK(CGRectContainsRect(self->_host.bounds, side));
                HARNESS_CHECK(CGRectContainsRect(self->_host.bounds, art));
                HARNESS_CHECK(CGRectContainsRect(self.window.rootViewController.view.bounds, self->_host.frame));
                HARNESS_CHECK([self->_host.accessibilityElements indexOfObject:bottom] <
                              [self->_host.accessibilityElements indexOfObject:overlay]);
                SGRGlyphButton *queue = (id)SGRFindByIdentifier(self->_host, @"retrine.player.queue", NULL);
                HARNESS_CHECK(queue && queue.accessibilityLabel.length && queue.bounds.size.width >= 44);
                queue.onTap();
                HARNESS_CHECK(SGRPlayerQueueSideShown());
                UITableView *list = (id)SGRFindByIdentifier(stage, @"retrine.queue", NULL);
                HARNESS_CHECK(list && list.window && list.bounds.size.height > 100);
                HARNESS_CHECK([list numberOfSections] > 0);
                SGRPlayerToggleLyrics();
                HARNESS_CHECK(getenv("HARNESS_NO_LYRICS") ? SGRPlayerQueueSideShown() : SGRPlayerLyricsOpen());
                // Spotify hides the outgoing cover cell while rebuilding a resized page.
                // Restoration must not depend on finding that hidden page again.
                self->_tilt.hidden = YES;
                self.window.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClassCompact;
                [self layOut];
                HARNESS_CHECK(!SGRPlayerTwoColumns() && !overlay.superview);
                HARNESS_CHECK(self->_covers.alpha == 1);
                HARNESS_CHECK(fabs(bottom.frame.size.width - self->_host.bounds.size.width) < 1);
                self->_tilt.hidden = NO;
                [self layOut];
                CGRect fullHost = self->_host.frame;
                CGRect resizedHost = fullHost;
                resizedHost.size.width += 40;
                self->_host.frame = resizedHost;
                CGRect band = SGRPlayerArtworkAreaIn(self->_host);
                CGRect header = [self->_units[0].view convertRect:self->_units[0].view.bounds toView:self->_host];
                HARNESS_CHECK(!CGRectIsNull(band) && CGRectGetMinY(band) >= CGRectGetMaxY(header));
                HARNESS_CHECK(SGRFindByIdentifier(self->_units[0].view, @"now-playing-minimize-button", NULL).alpha == 0);
                HARNESS_CHECK(SGRFindByIdentifier(self->_units[0].view, @"Context menu", NULL).alpha == 0);
                self->_host.frame = fullHost;
                CGRect singleControls = bottom.frame;
                self.window.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClassRegular;
                [self layOut];
                [self layOut];
                HARNESS_CHECK(SGRPlayerTwoColumns());
                if (getenv("HARNESS_SHRINK")) {
                    CGRect fullHost = self->_host.frame;
                    // A short, regular-width window leaves no artwork band over Spotify's control units.
                    CGRect shortHost = fullHost;
                    shortHost.size.height = 480;
                    self->_host.frame = shortHost;
                    CGRect singleColumn = CGRectMake(0, 140, fullHost.size.width, 280);
                    bottom.frame = singleColumn;
                    [self layOut];
                    HARNESS_CHECK(self.window.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassRegular);
                    HARNESS_CHECK(!SGRPlayerTwoColumns() && !overlay.superview && !SGRPlayerLyricsOpen());
                    if (!CGRectEqualToRect(bottom.frame, singleColumn)) {
                        HARNESS_FAIL(@"shrunken controls %@, expected %@", NSStringFromCGRect(bottom.frame), NSStringFromCGRect(singleColumn));
                    }
                    HARNESS_CHECK(self->_covers.alpha == 1);
                    [self layOut];
                    HARNESS_CHECK(CGRectEqualToRect(bottom.frame, singleColumn) && !overlay.superview);
                    self->_host.frame = fullHost;
                    bottom.frame = singleControls;
                    [self layOut];
                    HARNESS_CHECK(SGRPlayerTwoColumns());
                    NSLog(@"[harness] regular-width shrink restores single-column frames: PASS");
                }
                NSLog(@"[harness] adaptive frames: artwork %@ controls %@ side %@", NSStringFromCGRect(art),
                      NSStringFromCGRect(controls), NSStringFromCGRect(side));
            }
        }],
        // Issue #24: turned to landscape, the iPad player keeps its time row, and the audio quality badge for a song
        // Spotify reports High shows between the times, apart from the tap to seek, and opens its details.
        @[@0, ^{
            if (!checkLandscapeBadge) return;
            HARNESS_CHECK(UIInterfaceOrientationIsLandscape(self.window.windowScene.interfaceOrientation));
            UIViewController *durationUnit = self->_units[2];
            UIView *unit = durationUnit.view;
            NSArray<UILabel *> *labels;
            UISlider *slider = spotifyBar(unit, &labels);
            [NSUserDefaults.standardUserDefaults setBool:YES forKey:SGKeyPlayerAudioQuality];
            SGAudioQualitySettingChanged();
            SPTPlayerState *state = SGPlayerState();
            SGRHarnessQuality *quality = [SGRHarnessQuality new];
            quality.bitrateLevel = 3;
            quality.strategy = 1;
            [state setValue:quality forKey:@"playbackQuality"];
            extern void SGRHarnessReport(SPTPlayerState *state);
            SGRHarnessReport(state);
            [durationUnit viewDidLayoutSubviews];
            UIView *badge = SGAudioQualityShownBadge(unit);
            if (!badge) HARNESS_FAIL(@"no audio quality badge in the landscape %.0fpt time row", unit.bounds.size.width);
            CGRect take = labels.firstObject.superview.frame, remaining = labels.lastObject.superview.frame;
            HARNESS_CHECK(CGRectGetMinX(badge.frame) - CGRectGetMaxX(take) >= 7.5 && CGRectGetMinX(remaining) - CGRectGetMaxX(badge.frame) >= 7.5);
            // The badge reaches below the unit, over the controls' unit: its tap is on the view holding both, which a
            // touch on the badge reaches, and the top of the badge, inside the unit, does not seek while beside it does.
            UIGestureRecognizer *tap = [badge valueForKey:@"tap"];
            CGPoint onBadge = [self.window convertPoint:badge.center fromView:unit];
            HARNESS_CHECK(tap.view == unit.superview && [[self.window hitTest:onBadge withEvent:nil] isDescendantOfView:tap.view]);
            CGFloat top = CGRectGetMinY(badge.frame) + 2;
            HARNESS_CHECK(top < CGRectGetMaxY(unit.bounds));
            HARNESS_CHECK(!SGRSeekTapLands(unit, slider, CGPointMake(badge.center.x, top)));
            HARNESS_CHECK(SGRSeekTapLands(unit, slider, CGPointMake(CGRectGetMinX(badge.frame) - 6, top)));
            NSLog(@"[harness] landscape badge %@ (%@) between times %@ and %@", NSStringFromCGRect(badge.frame), badge.accessibilityLabel,
                  NSStringFromCGRect(take), NSStringFromCGRect(remaining));
            HARNESS_CHECK([badge accessibilityActivate]);
        }],
        @[^BOOL {
            return !checkLandscapeBadge
                || [self.window.rootViewController.presentedViewController isKindOfClass:NSClassFromString(@"SGAudioQualityPanel")];
        }, ^{
            if (!checkLandscapeBadge) return;
            [self.window.rootViewController dismissViewControllerAnimated:NO completion:nil];
            [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyPlayerAudioQuality];
            SGAudioQualitySettingChanged();
        }],
        @[@0, ^{
            if (!checkCompactHeader) return;
            originalHost = self->_host.frame;
            UIView *band = self->_tilt.superview.superview;
            originalBand = band.frame;
            originalWidthClass = self.window.traitCollection.horizontalSizeClass;
            self.window.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClassCompact;
            CGRect compact = originalHost;
            compact.size.width = MIN(compact.size.width, 375);
            self->_host.frame = compact;
            // During resizing the artwork band can still begin above the stationary header.
            CGRect staleBand = originalBand;
            staleBand.origin.y = 0;
            band.frame = staleBand;
            [self layOut];
            HARNESS_CHECK(!SGRPlayerTwoColumns() && !SGRPlayerLyricsOpen());
            SGRPlayerToggleLyrics();
            compactOverlay = firstOfClass(self->_host, @"SGRPlayerLyricsOverlay");
            HARNESS_CHECK(SGRPlayerLyricsOpen() && compactOverlay.superview == self->_host);
        }],
        @[^BOOL {
            if (!checkCompactHeader) return YES;
            UIView *thumb = [compactOverlay valueForKey:@"thumb"], *stage = [compactOverlay valueForKey:@"stage"];
            return thumb.layer.presentationLayer && !thumb.layer.animationKeys.count &&
                   stage.layer.presentationLayer.opacity > 0.99;
        }, ^{
            if (!checkCompactHeader) return;
            UIView *thumb = [compactOverlay valueForKey:@"thumb"];
            CALayer *drawn = thumb.layer.presentationLayer, *host = self->_host.layer.presentationLayer;
            HARNESS_CHECK(drawn && host && drawn.opacity > 0.99);
            CGRect thumbnail = [drawn convertRect:drawn.bounds toLayer:host];
            UIView *header = self->_units[0].view;
            CGRect headerFrame = [header convertRect:header.bounds toView:self->_host];
            if (CGRectGetMinY(thumbnail) < CGRectGetMaxY(headerFrame))
                HARNESS_FAIL(@"compact lyrics thumbnail %@ overlaps header %@", NSStringFromCGRect(thumbnail), NSStringFromCGRect(headerFrame));
            NSLog(@"[harness] rendered compact lyrics thumbnail %@ below header %@", NSStringFromCGRect(thumbnail), NSStringFromCGRect(headerFrame));
            SGRPlayerToggleLyrics();
        }],
        @[^BOOL {
            return !checkCompactHeader || !compactOverlay.superview;
        }, ^{
            if (!checkCompactHeader) return;
            self->_host.frame = originalHost;
            self->_tilt.superview.superview.frame = originalBand;
            self.window.traitOverrides.horizontalSizeClass = originalWidthClass;
            [self layOut];
            [self layOut];
        }],
        @[^BOOL {
            if (!SGRPlayerTwoColumns() || SGRPlayerQueueSideShown()) return YES;
            UIView *overlay = firstOfClass(self->_host, @"SGRPlayerLyricsOverlay");
            UIView *lyrics = [overlay valueForKey:@"madeLyrics"];
            CALayer *drawn = lyrics.layer.presentationLayer;
            return drawn && drawn.opacity > 0.99 && lyricsMenuIn([overlay valueForKey:@"stage"]) != nil;
        }, ^{
            if (SGRPlayerTwoColumns()) {
                CGRect safe = self.window.safeAreaLayoutGuide.layoutFrame;
                UIView *footer = self->_units[5].view;
                CGRect row = [footer convertRect:footer.bounds toView:self.window];
                if (!CGRectContainsRect(safe, row)) HARNESS_FAIL(@"footer %@ outside window safe area %@", NSStringFromCGRect(row), NSStringFromCGRect(safe));
                UIView *overlay = firstOfClass(self->_host, @"SGRPlayerLyricsOverlay");
                UIView *stage = [overlay valueForKey:@"stage"];
                CGRect side = [stage convertRect:stage.bounds toView:self.window];
                HARNESS_CHECK(CGRectContainsRect(safe, side));
                if (SGRPlayerLyricsOpen()) {
                    UIButton *options = lyricsMenuIn(stage);
                    HARNESS_CHECK(options != nil && options.accessibilityLabel.length > 0);
                    CGRect frame = [options convertRect:options.bounds toView:self.window];
                    HARNESS_CHECK(CGRectContainsRect(side, frame) && CGRectContainsRect(safe, frame));
                    HARNESS_CHECK(!CGRectIntersectsRect(row, frame));
                }
                NSLog(@"[harness] safe footer %@ lyrics column %@", NSStringFromCGRect(row), NSStringFromCGRect(side));
            }
            NSLog(@"[harness] adaptive checks: PASS");
            fflush(stdout);
        }]
    ], 0);
}

// The album header's artist faces (Redesigned/Kit/SGRHeaderInfo.h's -showCreatorFaces:from:, Album/AlbumHeader.x, the
// Albums page's Artist picture), on the mocked page: `faces` on the launch line. Spotify's artist row is built again
// for each case -- one to four artists, a hidden face and one under a hidden view, a square badge after the names,
// pictures that land late or are emptied, the header reused for another album -- with each face a solid colour, and
// what the header draws is measured against the spec's numbers: at most three faces in the row's own order (right to
// left under a right-to-left language), each a line's height and a point across and never over 22pt, each next one
// round(0.85 x that) on, 8pt before the name, the two centred together, a clear ring around the one before cut out of
// the next, the line's tap and what VoiceOver reads unchanged, and with the setting off the name alone where it would
// be with no picture. The rows the phone dumped (facesDeviceRow: Trio, Love for Sale and 21, initials inside square
// avatars ahead of one label of names, Trio's last picture wider than its avatar) show every artist's face.
// "[harness] SHOT album-faces-two-on" / "-two-off" / "album-faces-trio" hold the two-artist and the phone's Trio
// header 1.5 s for a screenshot. Logs "[harness] PASS album faces <ltr|rtl>, side ..." and exits 0, or a FAIL line and exits 1.
#import <objc/runtime.h>
#import "pixel-check.h"

// The ovals made while a count is running: the faces' cut rings are the only ovals the header's pass makes.
static NSUInteger facesOvals;
@implementation UIBezierPath (FacesCount)
+ (instancetype)faces_bezierPathWithOvalInRect:(CGRect)rect {
    facesOvals++;
    return [self faces_bezierPathWithOvalInRect:rect];
}
@end

static void facesCountOvals(void) {
    method_exchangeImplementations(class_getClassMethod(UIBezierPath.class, @selector(bezierPathWithOvalInRect:)),
                                   class_getClassMethod(UIBezierPath.class, @selector(faces_bezierPathWithOvalInRect:)));
}

static NSString *const kFacesKey = @"spotifyglass.redesign.album.artistPicture";
static const CGFloat kFacesSourceSide = 24, kFacesSourceStep = 16;
static NSString *const kFacesTrio = @"Dolly Parton • Linda Ronstadt • Emmylou Harris";

static UIImage *facesImage(UIColor *color) {
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(48, 48)] imageWithActions:^(UIGraphicsImageRendererContext *c) {
        [color setFill];
        UIRectFill(CGRectMake(0, 0, 48, 48));
    }];
}

static BOOL facesRTL(UIView *view) {
    return view.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
}

// Spotify's artist row: `count` image views 24pt across, each 16pt on from the one before from the leading edge, then
// the names, the row's accessibility label. `hidden` more faces lead it, one hidden and one under a hidden view, and
// `badge` puts a square picture after the names. Without `label` the names are the row's accessibility label alone,
// with no label drawing them. The faces have no picture yet.
static NSArray<UIImageView *> *facesRow(UIView *row, NSUInteger count, NSString *names, BOOL hidden, BOOL badge, UIImage *decoy,
                                        BOOL label) {
    for (UIView *old in row.subviews.copy) [old removeFromSuperview];
    BOOL rtl = facesRTL(row);
    NSUInteger slots = count + (hidden ? 2 : 0);
    CGFloat facesWidth = kFacesSourceSide + (slots - 1) * kFacesSourceStep, nameWidth = 120;
    CGFloat width = facesWidth + 8 + nameWidth;
    row.frame = CGRectMake(row.frame.origin.x, row.frame.origin.y, width, kFacesSourceSide);
    CGFloat (^place)(CGFloat x, CGFloat w) = ^CGFloat(CGFloat x, CGFloat w) { return rtl ? width - x - w : x; };
    NSMutableArray<UIImageView *> *faces = [NSMutableArray array];
    for (NSUInteger i = 0; i < slots; i++) {
        CGRect frame = CGRectMake(place(i * kFacesSourceStep, kFacesSourceSide), 0, kFacesSourceSide, kFacesSourceSide);
        UIImageView *face = [[UIImageView alloc] initWithFrame:frame];
        face.accessibilityIdentifier = @"Encore.ImageView";
        face.layer.cornerRadius = kFacesSourceSide / 2;
        face.clipsToBounds = YES;
        if (hidden && i == 0) {
            face.hidden = YES;
            face.image = decoy;
            [row addSubview:face];
        } else if (hidden && i == 1) {
            UIView *under = [[UIView alloc] initWithFrame:frame];
            under.hidden = YES;
            face.frame = under.bounds;
            face.image = decoy;
            [under addSubview:face];
            [row addSubview:under];
        } else {
            [row addSubview:face];
            [faces addObject:face];
        }
    }
    if (label) {
        UIView *encore = [[UIView alloc] initWithFrame:CGRectMake(place(facesWidth + 8, nameWidth), 4.33, nameWidth, 15.33)];
        encore.accessibilityIdentifier = @"Encore.Label";
        UILabel *text = [[UILabel alloc] initWithFrame:encore.bounds];
        text.text = names;
        text.font = [UIFont systemFontOfSize:11];
        [encore addSubview:text];
        [row addSubview:encore];
    }
    if (badge) {
        UIImageView *mark = [[UIImageView alloc] initWithFrame:CGRectMake(place(facesWidth + 8 + nameWidth + 4, 16), 4, 16, 16)];
        mark.image = decoy;
        [row addSubview:mark];
    }
    row.accessibilityLabel = names;
    return faces;
}

// Spotify's artist row as the phone dumped it (iOS 27.2, Spotify 9.1.90: .mixdog/review-shots/phone-v100/trees/
// *-artist-parent-annotated.txt), one face per letter of `initials`: a button holding the facepile, each face a 24pt
// square avatar 20.4pt on from the one before holding its initial (a black letter) and, over it, a 24pt square that clips
// a round image view -- the third 32x24 at x -4, a portrait filled across it, as Trio's Emmylou Harris -- then a hidden
// label and a hidden button label, Spotify's own hidden image view with its placeholder, and the names in one label 8pt
// after the faces. Right to left, the same mirrored. The faces have no picture yet.
static NSArray<UIImageView *> *facesDeviceRow(UIView *row, NSArray<NSString *> *initials, NSString *names) {
    for (UIView *old in row.subviews.copy) [old removeFromSuperview];
    static const CGFloat kAvatar = 24, kAvatarStep = 20.4, kNameGap = 8, kNameWidth = 200;
    BOOL rtl = facesRTL(row);
    CGFloat pile = kAvatar + (initials.count - 1) * kAvatarStep, width = pile + kNameGap + kNameWidth;
    row.frame = CGRectMake(row.frame.origin.x, row.frame.origin.y, width, kAvatar);
    CGFloat (^place)(CGFloat x, CGFloat w, CGFloat in) = ^CGFloat(CGFloat x, CGFloat w, CGFloat in) { return rtl ? in - x - w : x; };
    UIView *stack = [[UIView alloc] initWithFrame:row.bounds];
    stack.accessibilityIdentifier = @"Encore.StackView";
    [row addSubview:stack];
    UIView *button = [[UIView alloc] initWithFrame:CGRectMake(place(0, pile, width), 0, pile, kAvatar)];
    [stack addSubview:button];
    // The button's layout views down to the facepile's stack, each the facepile's size.
    UIView *facepile = button;
    for (int i = 0; i < 3; i++) {
        UIView *inner = [[UIView alloc] initWithFrame:CGRectMake(0, 0, pile, kAvatar)];
        [facepile addSubview:inner];
        facepile = inner;
    }
    NSMutableArray<UIImageView *> *faces = [NSMutableArray array];
    [initials enumerateObjectsUsingBlock:^(NSString *initial, NSUInteger i, BOOL *stop) {
        UIView *avatar = [[UIView alloc] initWithFrame:CGRectMake(place(i * kAvatarStep, kAvatar, pile), 0, kAvatar, kAvatar)];
        UIView *letterBox = [[UIView alloc] initWithFrame:CGRectMake(6, 1, 12, 22)];
        letterBox.accessibilityIdentifier = @"Encore.Label";
        UILabel *letter = [[UILabel alloc] initWithFrame:letterBox.bounds];
        letter.text = initial;
        letter.font = [UIFont boldSystemFontOfSize:16];
        letter.textColor = UIColor.blackColor;
        [letterBox addSubview:letter];
        [avatar addSubview:letterBox];
        UIView *clip = [[UIView alloc] initWithFrame:avatar.bounds];
        clip.accessibilityIdentifier = @"Encore.ImageView";
        clip.layer.cornerRadius = kAvatar / 2;
        clip.clipsToBounds = YES;
        CGRect picture = i == 2 ? CGRectMake(-4, 0, 32, 24) : clip.bounds;
        UIImageView *face = [[UIImageView alloc] initWithFrame:picture];
        face.contentMode = UIViewContentModeScaleAspectFill;
        [clip addSubview:face];
        [avatar addSubview:clip];
        [facepile addSubview:avatar];
        [faces addObject:face];
    }];
    UILabel *hiddenLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    UIView *hiddenBox = [[UIView alloc] initWithFrame:CGRectZero];
    hiddenBox.hidden = YES;
    [hiddenBox addSubview:hiddenLabel];
    [button.subviews.firstObject addSubview:hiddenBox];
    UILabel *buttonLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    buttonLabel.hidden = YES;
    [button addSubview:buttonLabel];
    UIView *media = [[UIView alloc] initWithFrame:CGRectMake(place(0, kAvatar, width), 0, kAvatar, kAvatar)];
    media.accessibilityIdentifier = @"Encore.ImageView";
    media.hidden = YES;
    UIImageView *mediaImage = [[UIImageView alloc] initWithFrame:media.bounds];
    mediaImage.alpha = 0;
    [media addSubview:mediaImage];
    [media addSubview:[[UIView alloc] initWithFrame:media.bounds]];
    [stack addSubview:media];
    UIView *nameBox = [[UIView alloc] initWithFrame:CGRectMake(place(pile + kNameGap, kNameWidth, width), 3, kNameWidth, 18)];
    nameBox.accessibilityIdentifier = @"Encore.Label";
    UILabel *name = [[UILabel alloc] initWithFrame:nameBox.bounds];
    name.text = names;
    name.font = [UIFont boldSystemFontOfSize:13];
    [nameBox addSubview:name];
    [stack addSubview:nameBox];
    row.accessibilityLabel = names;
    return faces;
}

// The header's pass, from the row up, the way Spotify's own layout reaches it.
static void facesPass(UIView *row, UIView *root) {
    for (UIView *v = row; v; v = v.superview) [v setNeedsLayout];
    [root layoutIfNeeded];
}

static UIView *facesInfo(UIView *root) {
    return checkFind(root, ^BOOL(UIView *v) { return [NSStringFromClass(v.class) isEqualToString:@"SGRHeaderInfo"]; });
}

static UILabel *facesName(UIView *info, NSString *names) {
    for (UIView *sub in info.subviews) {
        if ([sub isKindOfClass:UILabel.class] && [((UILabel *)sub).text isEqualToString:names]) return (UILabel *)sub;
    }
    HARNESS_FAIL(@"no creator line \"%@\" in the header", names);
}

// The faces the header shows: its image views with one of `palette`'s pictures, shown all the way up to it, in the
// order they read.
static NSArray<UIImageView *> *facesShown(UIView *info, NSArray<UIImage *> *palette) {
    NSMutableArray<UIImageView *> *found = [NSMutableArray array];
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:info];
    while (queue.count) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        [queue addObjectsFromArray:v.subviews];
        if (![v isKindOfClass:UIImageView.class] || ![palette containsObject:((UIImageView *)v).image]) continue;
        BOOL shown = YES;
        for (UIView *up = v; up && up != info; up = up.superview) shown = shown && !up.hidden && up.alpha > 0.01;
        if (shown) [found addObject:(UIImageView *)v];
    }
    BOOL rtl = facesRTL(info);
    return [found sortedArrayUsingComparator:^NSComparisonResult(UIView *one, UIView *other) {
        CGFloat a = CGRectGetMidX([one convertRect:one.bounds toView:info]), b = CGRectGetMidX([other convertRect:other.bounds toView:info]);
        return (rtl ? a < b : a > b) ? NSOrderedDescending : NSOrderedAscending;
    }];
}

// What the spec says of a line showing `expected` (in order) before `names`; nothing for none.
static void facesExpect(NSString *what, UIView *info, NSArray<UIImage *> *palette, NSArray<UIImage *> *expected, NSString *names) {
    if (!HarnessRunUntil(^BOOL {
        BOOL named = NO;
        for (UILabel *label in info.subviews)
            if ([label isKindOfClass:UILabel.class] && [label.text isEqual:names]) named = YES;
        return named && [facesShown(info, palette) count] == expected.count;
    })) HARNESS_FAIL(@"%@: waiting for %@ and %lu faces", what, names, (unsigned long)expected.count);
    [info layoutIfNeeded];
    UILabel *name = facesName(info, names);
    NSArray<UIImageView *> *shown = facesShown(info, palette);
    if (shown.count > 3) HARNESS_FAIL(@"%@: more than three faces, %lu", what, (unsigned long)shown.count);
    if (shown.count != expected.count) HARNESS_FAIL(@"%@: %lu faces, expected %lu", what, (unsigned long)shown.count, (unsigned long)expected.count);
    BOOL rtl = facesRTL(info);
    CGFloat width = info.bounds.size.width;
    CGRect line = name.frame;
    if (!expected.count) {
        // The name alone, where it is with no picture: centred on its own width, no room kept beside it.
        if (fabs(CGRectGetMinX(line) - round((width - line.size.width) / 2)) > 0.5)
            HARNESS_FAIL(@"%@: the name alone at %@, not centred in %.0f", what, NSStringFromCGRect(line), width);
        NSLog(@"[harness] %@: name alone at %@", what, NSStringFromCGRect(line));
        return;
    }
    CGFloat side = MIN(ceil(name.font.lineHeight) + 1, 22), step = round(side * 0.85);
    CGRect group = line;
    for (NSUInteger i = 0; i < shown.count; i++) {
        UIImageView *face = shown[i];
        CGRect frame = [face convertRect:face.bounds toView:info];
        if (face.image != expected[i]) HARNESS_FAIL(@"%@: face %lu is not the row's face %lu", what, (unsigned long)i, (unsigned long)i);
        if (fabs(frame.size.width - side) > 0.01 || fabs(frame.size.height - side) > 0.01 || frame.size.width > 22)
            HARNESS_FAIL(@"%@: face %lu is %@, expected %.0fpt (a line of %.2f, at most 22)", what, (unsigned long)i,
                         NSStringFromCGSize(frame.size), side, name.font.lineHeight);
        if (fabs(CGRectGetMidY(frame) - CGRectGetMidY(line)) > 0.5)
            HARNESS_FAIL(@"%@: face %lu at %@ off the name's line %@", what, (unsigned long)i, NSStringFromCGRect(frame), NSStringFromCGRect(line));
        if (i) {
            CGRect before = [shown[i - 1] convertRect:shown[i - 1].bounds toView:info];
            CGFloat on = rtl ? CGRectGetMinX(before) - CGRectGetMinX(frame) : CGRectGetMinX(frame) - CGRectGetMinX(before);
            if (fabs(on - step) > 0.01) HARNESS_FAIL(@"%@: face %lu is %.2fpt on from the one before, expected %.0f", what, (unsigned long)i, on, step);
        }
        if (face.isAccessibilityElement) HARNESS_FAIL(@"%@: face %lu is an accessibility element", what, (unsigned long)i);
        group = CGRectUnion(group, frame);
    }
    CGRect last = [shown.lastObject convertRect:shown.lastObject.bounds toView:info];
    CGFloat gap = rtl ? CGRectGetMinX(last) - CGRectGetMaxX(line) : CGRectGetMinX(line) - CGRectGetMaxX(last);
    if (fabs(gap - 8) > 0.5) HARNESS_FAIL(@"%@: %.2fpt between the faces and the name, expected 8", what, gap);
    if (fabs(CGRectGetMidX(group) - width / 2) > 1) HARNESS_FAIL(@"%@: faces and name centred at %.1f, not %.1f", what, CGRectGetMidX(group), width / 2);
    // A tap on the faces is the line's.
    CGPoint centre = [shown.firstObject convertPoint:CGPointMake(side / 2, side / 2) toView:info];
    if ([info hitTest:centre withEvent:nil] != name) HARNESS_FAIL(@"%@: a tap on the faces does not reach the artist line", what);
    NSLog(@"[harness] %@: %lu faces of %.0fpt, %.0fpt on, gap %.1f, name at %@", what, (unsigned long)shown.count, side, step, gap,
          NSStringFromCGRect(line));
}

// Each next face is cut 1.5pt clear around the one before it: just outside the one before, inside the next, nothing is
// drawn; a little further in, the next one's colour; just inside the one before, its own.
static void facesExpectRing(NSString *what, UIView *info, NSArray<UIImage *> *palette, NSArray<UIColor *> *colours) {
    NSArray<UIImageView *> *shown = facesShown(info, palette);
    // sgr_setFaces: fades the pile and animates layout of the creator line.
    // Its centres can already have the right colours while a moving face or
    // label still covers the narrow gap measured in final layout coordinates.
    [info layoutIfNeeded];
    [CATransaction flush];
    if (!HarnessRunUntil(^BOOL {
        for (UIView *child in info.subviews)
            if (child.layer.animationKeys.count) return NO;
        for (UIImageView *face in shown)
            if (face.layer.animationKeys.count || face.layer.mask.animationKeys.count) return NO;
        return YES;
    })) HARNESS_FAIL(@"%@: creator-line layout or face fade did not finish", what);
    UIImage *drawn = checkRender(info);
    CGFloat direction = facesRTL(info) ? -1 : 1;
    for (NSUInteger i = 1; i < shown.count; i++) {
        CGRect before = [shown[i - 1] convertRect:shown[i - 1].bounds toView:info], frame = [shown[i] convertRect:shown[i].bounds toView:info];
        CGFloat radius = before.size.width / 2, y = CGRectGetMidY(before);
        CGPoint ring = CGPointMake(CGRectGetMidX(before) + direction * (radius + 0.75), y);
        CGPoint next = CGPointMake(CGRectGetMidX(frame) + direction * (radius - 2), y);
        CGPoint inside = CGPointMake(CGRectGetMidX(before) + direction * (radius - 1), y);
        CheckPixel gap = checkPixel(drawn, ring);
        if (gap.a > 0.15) HARNESS_FAIL(@"%@: the ring around face %lu is drawn (alpha %.2f)", what, (unsigned long)i - 1, gap.a);
        NSArray *checks = @[@[[NSValue valueWithCGPoint:next], colours[i]], @[[NSValue valueWithCGPoint:inside], colours[i - 1]]];
        for (NSArray *check in checks) {
            CheckPixel pixel = checkPixel(drawn, [check[0] CGPointValue]);
            CGFloat r, g, b, a;
            [check[1] getRed:&r green:&g blue:&b alpha:&a];
            if (pixel.a < 0.9 || fabs(pixel.r - r) > 0.15 || fabs(pixel.g - g) > 0.15 || fabs(pixel.b - b) > 0.15)
                HARNESS_FAIL(@"%@: at %@ (%.2f %.2f %.2f a %.2f), expected %@", what, NSStringFromCGPoint([check[0] CGPointValue]),
                             pixel.r, pixel.g, pixel.b, pixel.a, check[1]);
        }
    }
    NSLog(@"[harness] %@: a clear ring between each pair of faces", what);
}

static void facesRun(UIView *root, UIControl *row) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults removeObjectForKey:kFacesKey];
    NSArray<UIColor *> *colours = @[UIColor.redColor, [UIColor colorWithRed:0 green:0.8 blue:0 alpha:1], UIColor.blueColor, UIColor.yellowColor];
    NSMutableArray<UIImage *> *pictures = [NSMutableArray array];
    for (UIColor *colour in colours) [pictures addObject:facesImage(colour)];
    UIImage *decoy = facesImage(UIColor.magentaColor);
    NSArray<UIImage *> *palette = [pictures arrayByAddingObject:decoy];
    UIView *info = facesInfo(root);
    HARNESS_CHECK(info);
    BOOL rtl = facesRTL(info);
    __block NSUInteger fired = 0;
    [row addAction:[UIAction actionWithHandler:^(UIAction *action) { fired++; }] forControlEvents:UIControlEventPrimaryActionTriggered];
    __block NSArray<UIImageView *> *sources;
    __block UIView *hiddenUnder;
    void (^fill)(NSUInteger count) = ^(NSUInteger count) {
        for (NSUInteger i = 0; i < count; i++) sources[i].image = pictures[i];
    };
    NSArray<UIImage *> *(^first)(NSUInteger) = ^(NSUInteger count) { return [pictures subarrayWithRange:NSMakeRange(0, count)]; };

    checkSteps(@[
        ^{
            sources = facesRow(row, 1, @"Ada", NO, NO, decoy, YES);
            fill(1);
            facesPass(row, root);
        }, ^{
            facesExpect(@"one artist", info, palette, first(1), @"Ada");
            sources = facesRow(row, 2, @"Ada, Ben", NO, NO, decoy, YES);
            fill(2);
            facesPass(row, root);
        }, ^{
            facesExpect(@"two artists", info, palette, first(2), @"Ada, Ben");
            facesExpectRing(@"two artists", info, palette, colours);
            UILabel *name = facesName(info, @"Ada, Ben");
            // What VoiceOver reads: the label's text, a button.
            NSString *spoken = name.accessibilityLabel ?: name.text;
            if (!(name.accessibilityTraits & UIAccessibilityTraitButton) || ![spoken isEqualToString:@"Ada, Ben"])
                HARNESS_FAIL(@"the artist line reads \"%@\" without the button trait", spoken);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            // What the line's tap runs: Spotify's own row, once.
            [info performSelector:NSSelectorFromString(@"sgr_creatorTapped")];
#pragma clang diagnostic pop
            if (fired != 1) HARNESS_FAIL(@"the artist line fired Spotify's row %lu times", (unsigned long)fired);
            checkShot(@"album-faces-two-on");
        }, ^{
            [defaults setBool:NO forKey:kFacesKey];
        }, ^{
            facesExpect(@"two artists, Artist picture off", info, palette, @[], @"Ada, Ben");
            UILabel *name = facesName(info, @"Ada, Ben");
            if (!(name.accessibilityTraits & UIAccessibilityTraitButton) || [info hitTest:CGPointMake(CGRectGetMidX(name.frame), CGRectGetMidY(name.frame)) withEvent:nil] != name)
                HARNESS_FAIL(@"with Artist picture off the artist line lost its button");
            checkShot(@"album-faces-two-off");
        }, ^{
            [defaults removeObjectForKey:kFacesKey];
        }, ^{
            facesExpect(@"two artists, Artist picture on again", info, palette, first(2), @"Ada, Ben");
            sources = facesRow(row, 3, @"Ada, Ben, Cy", NO, NO, decoy, YES);
            fill(3);
            facesPass(row, root);
        }, ^{
            facesExpect(@"three artists", info, palette, first(3), @"Ada, Ben, Cy");
            // The rows the phone showed one face for: initials in the avatars ahead of the names, and the last picture
            // wider than the avatar that clips it.
            sources = facesDeviceRow(row, @[@"D", @"L", @"E"], kFacesTrio);
            fill(3);
            facesPass(row, root);
        }, ^{
            facesExpect(@"the phone's Trio row", info, palette, first(3), kFacesTrio);
            facesExpectRing(@"the phone's Trio row", info, palette, colours);
            checkShot(@"album-faces-trio");
        }, ^{
            // Dolly's picture hidden while her initial still shows: the initial is still not the name, and the two
            // pictures left are the faces. Then the same with the square that clips it hidden instead.
            sources[0].hidden = YES;
            facesPass(row, root);
        }, ^{
            facesExpect(@"the phone's Trio row, Dolly's picture hidden", info, palette, @[pictures[1], pictures[2]], kFacesTrio);
            sources[0].hidden = NO;
            sources[0].superview.hidden = YES;
            facesPass(row, root);
        }, ^{
            facesExpect(@"the phone's Trio row, Dolly's clip hidden", info, palette, @[pictures[1], pictures[2]], kFacesTrio);
            sources = facesDeviceRow(row, @[@"T", @"L"], @"Tony Bennett • Lady Gaga");
            fill(2);
            facesPass(row, root);
        }, ^{
            facesExpect(@"the phone's Love for Sale row", info, palette, first(2), @"Tony Bennett • Lady Gaga");
            sources = facesDeviceRow(row, @[@"A"], @"Adele");
            fill(1);
            facesPass(row, root);
        }, ^{
            facesExpect(@"the phone's 21 row, one artist", info, palette, first(1), @"Adele");
            sources = facesRow(row, 4, @"Ada, Ben, Cy, Dee", NO, NO, decoy, YES);
            fill(4);
            facesPass(row, root);
        }, ^{
            facesExpect(@"four artists", info, palette, first(3), @"Ada, Ben, Cy, Dee");
            facesExpectRing(@"four artists", info, palette, colours);
            sources = facesRow(row, 2, @"Ada and Ben", YES, YES, decoy, YES);
            fill(2);
            facesPass(row, root);
        }, ^{
            facesExpect(@"two shown, two hidden, a badge after the names", info, palette, first(2), @"Ada and Ben");
            // Pictures that land after the header's pass, together: the faces follow without another pass.
            sources = facesRow(row, 2, @"Eve, Fay", NO, NO, decoy, YES);
            facesPass(row, root);
        }, ^{
            facesExpect(@"two artists before their pictures", info, palette, @[], @"Eve, Fay");
            fill(2);
        }, ^{
            facesExpect(@"two artists, pictures landed late", info, palette, first(2), @"Eve, Fay");
            for (UIImageView *source in sources) source.image = nil;
        }, ^{
            facesExpect(@"the same line's pictures emptied", info, palette, first(2), @"Eve, Fay");
            facesPass(row, root);
        }, ^{
            facesExpect(@"the same line's pictures emptied, laid out again", info, palette, first(2), @"Eve, Fay");
            // The header reused for another album: its line, the same view, says someone else.
            sources = facesRow(row, 1, @"Gus", NO, NO, decoy, YES);
            facesPass(row, root);
        }, ^{
            facesExpect(@"another album before its picture", info, palette, @[], @"Gus");
            fill(1);
        }, ^{
            facesExpect(@"another album", info, palette, first(1), @"Gus");
            // Pictures landing in views hidden since the header's pass, one itself and one under a hidden view.
            sources = facesRow(row, 3, @"Hal, Ida, Jo", NO, NO, decoy, YES);
            UIView *under = [[UIView alloc] initWithFrame:sources[2].frame];
            [row insertSubview:under belowSubview:sources[2]];
            sources[2].frame = under.bounds;
            [under addSubview:sources[2]];
            hiddenUnder = under;
            facesPass(row, root);
        }, ^{
            facesExpect(@"three artists before their pictures", info, palette, @[], @"Hal, Ida, Jo");
            sources[1].hidden = YES;
            hiddenUnder.hidden = YES;
            fill(3);
        }, ^{
            facesExpect(@"hidden before their pictures landed", info, palette, first(1), @"Hal, Ida, Jo");
            // The one shown emptied: it waits for its picture, and the face stays.
            sources[0].image = nil;
        }, ^{
            facesExpect(@"the one shown emptied, the others hidden", info, palette, first(1), @"Hal, Ida, Jo");
            // Hidden too, then given its picture: no view shown is waiting, so nothing is kept.
            sources[0].hidden = YES;
            sources[0].image = pictures[0];
        }, ^{
            facesExpect(@"every face hidden", info, palette, @[], @"Hal, Ida, Jo");
            // The name only in the row's accessibility label, a square badge where the name would be drawn.
            sources = facesRow(row, 2, @"Kim", NO, YES, decoy, NO);
            fill(2);
            facesPass(row, root);
        }, ^{
            facesExpect(@"no name label, a square badge after the faces", info, palette, @[], @"Kim");
            sources = facesRow(row, 3, @"Lu, Mo, Ny", NO, NO, decoy, YES);
            fill(3);
            facesPass(row, root);
        }, ^{
            facesExpect(@"three artists again", info, palette, first(3), @"Lu, Mo, Ny");
            // Laid out again and again with nothing changed: the cut rings are the ones already made.
            NSArray<UIImageView *> *shown = facesShown(info, palette);
            NSMutableArray *masks = [NSMutableArray array];
            NSMutableArray<NSValue *> *paths = [NSMutableArray array];
            for (UIImageView *face in shown) {
                CALayer *mask = face.layer.mask;
                [masks addObject:mask ?: NSNull.null];
                CGPathRef path = [mask isKindOfClass:CAShapeLayer.class] ? ((CAShapeLayer *)mask).path : NULL;
                [paths addObject:[NSValue valueWithPointer:path]];
            }
            facesOvals = 0;
            facesCountOvals();
            for (int i = 0; i < 5; i++) {
                [info setNeedsLayout];
                [info layoutIfNeeded];
                facesPass(row, root);
            }
            facesCountOvals();
            if (facesOvals) HARNESS_FAIL(@"five layouts that changed nothing made %lu cut-ring paths", (unsigned long)facesOvals);
            [shown enumerateObjectsUsingBlock:^(UIImageView *face, NSUInteger i, BOOL *stop) {
                CALayer *mask = face.layer.mask;
                CGPathRef path = [mask isKindOfClass:CAShapeLayer.class] ? ((CAShapeLayer *)mask).path : NULL;
                if ((mask ?: (id)NSNull.null) != masks[i] || path != paths[i].pointerValue)
                    HARNESS_FAIL(@"face %lu's cut ring was made again by a layout that changed nothing", (unsigned long)i);
            }];
            if (shown.count != 3 || [paths[1] pointerValue] == NULL) HARNESS_FAIL(@"the faces lost their cut rings");
            facesExpectRing(@"three artists laid out again", info, palette, colours);
            UILabel *name = facesName(info, @"Lu, Mo, Ny");
            CGFloat side = MIN(ceil(name.font.lineHeight) + 1, 22);
            BOOL capped = ceil(name.font.lineHeight) + 1 > 22;
            NSString *pass = [NSString stringWithFormat:@"[harness] PASS album faces %@, side %.0f from a line of %.2f%@", rtl ? @"rtl" : @"ltr",
                              side, name.font.lineHeight, capped ? @", capped at 22" : @""];
            NSLog(@"%@", pass);
            fprintf(stderr, "%s\n", pass.UTF8String);
            exit(0);
        },
    ], 0);
}

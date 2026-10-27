// A line of text that scrolls side to side when it does not fit, the way the Music app's titles do: it
// rests at its start, glides to show its end, rests, and glides back, its overflowing edge faded. Text
// that fits stands still. Under Reduce Motion it ends in "…" instead.
//
// Threading: main thread only.
#import <UIKit/UIKit.h>

@interface SGMarqueeLabel : UIView
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) UIFont *font;
@property (nonatomic, strong) UIColor *textColor;
// Its leading edge faded too while it scrolls, as the Music app's mini player has both. Off unless set. The text then
// starts leadingInset in (0 unless set), so that much of the fade lies before it at rest: the caller places the view that
// much further out.
@property (nonatomic) BOOL fadesLeadingEdge;
@property (nonatomic) CGFloat leadingInset;
@end

#import "Redesigned/Kit/SGRHeaderInfo.h"

#define SGRKeyCoverBeside @"spotifyglass.redesign.pages.coverBeside"

// Album and playlist supply their existing containers; the Kit owns fitting and live invalidation.
@interface SGRHeaderInfo (CoverBeside)
@property (nonatomic, readonly) BOOL sgr_coverBeside;
- (CGRect)sgr_coverBesideIn:(UIView *)space available:(CGRect)available fitHeight:(BOOL)fitHeight
                 direction:(UIUserInterfaceLayoutDirection)direction
             stackedParent:(UIView *)parent stackedFrame:(CGRect)frame
                      more:(UIView *)more download:(UIView *)download
                   refresh:(dispatch_block_t)refresh;
@end

#import "PixiePageController.h"
#import "SpotifyPageContract.h"

BOOL SAPRegisterPixiePageProtocols(void) {
    return SAPSpotifyPageContract(SAPPixiePageController.class,YES);
}

@implementation SAPPixiePageController
- (instancetype)initWithStyle:(UITableViewStyle)style {
    SAPRegisterPixiePageProtocols();
    return [super initWithStyle:style];
}
- (NSString *)spt_pageIdentifier {return NSStringFromClass(self.class);}
- (NSURL *)spt_pageURI {
    return [NSURL URLWithString:[@"spotify:internal:pixie:" stringByAppendingString:self.spt_pageIdentifier]];
}
@end

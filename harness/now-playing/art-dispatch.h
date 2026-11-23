#import <Foundation/Foundation.h>
void HarnessArtDispatch(dispatch_queue_t queue, dispatch_block_t block);
#define dispatch_async HarnessArtDispatch

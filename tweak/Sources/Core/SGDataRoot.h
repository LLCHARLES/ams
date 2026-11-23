#import <Foundation/Foundation.h>

// Host-only. One choice per directory for this process. Nil means storage is unavailable.
NSURL *SGDataRoot(NSSearchPathDirectory directory);

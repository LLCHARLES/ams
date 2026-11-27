#import <Foundation/Foundation.h>

// Suspended so callers can register cancellation before resume. A zero resource timeout
// keeps URLSession's default; the request's own timeout is always preserved.
NSURLSessionDataTask *SGBoundedRequestTask(NSURLRequest *request, NSTimeInterval resourceTimeout,
    void (^done)(NSData *, NSURLResponse *, NSError *));

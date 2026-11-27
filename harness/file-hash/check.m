#import <Foundation/Foundation.h>
#import "../harness-fail.h"

// The factory normally returns the real handle. For the fault case, let one real read
// succeed and inject EIO on the next one, as on a volume that becomes unavailable.
static BOOL inject, closed;
@interface FaultHandle : NSObject
@property NSFileHandle *underlying;
@property BOOL readOnce;
@end
@implementation FaultHandle
+ (id)fileHandleForReadingFromURL:(NSURL *)url error:(NSError **)error {
    NSFileHandle *file = [NSFileHandle fileHandleForReadingFromURL:url error:error];
    if (!inject) return file;
    FaultHandle *fault = [self new];
    fault.underlying = file;
    return fault;
}
- (NSData *)readDataUpToLength:(NSUInteger)size error:(NSError **)error {
    if (self.readOnce) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:EIO userInfo:nil];
        return nil;
    }
    self.readOnce = YES;
    return [self.underlying readDataUpToLength:size error:error];
}
- (void)closeFile { [self.underlying closeFile]; closed = YES; }
@end
#define NSFileHandle FaultHandle
#import "Core/SGFileHash.m"
#undef NSFileHandle

int main(int argc, const char **argv) { @autoreleasepool {
    NSURL *file = [NSURL fileURLWithPath:@(argv[1])];
    HARNESS_CHECK([[NSData data] writeToURL:file atomically:YES]);
    HARNESS_CHECK([SGFileSHA256(file) isEqual:@"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"]);
    HARNESS_CHECK([[NSMutableData dataWithLength:(1 << 20) + 1] writeToURL:file atomically:YES]);
    HARNESS_CHECK([SGFileSHA256(file) isEqual:@"2cb74edba754a81d121c9db6833704a8e7d417e5b13d1a19f4a52f007d644264"]);
    inject = YES;
    HARNESS_CHECK(!SGFileSHA256(file) && closed);
    puts("file hash: ok");
}}

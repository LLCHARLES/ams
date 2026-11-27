#import "SGFileHash.h"
#import <CommonCrypto/CommonDigest.h>

NSString *SGDataSHA256(NSData *data) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:2 * CC_SHA256_DIGEST_LENGTH];
    for (NSUInteger i = 0; i < sizeof(digest); i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

NSString *SGFileSHA256(NSURL *url) {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:url error:nil];
    if (!handle) return nil;
    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    NSError *error = nil;
    for (;;) {
        @autoreleasepool {
            NSData *chunk = [handle readDataUpToLength:1 << 20 error:&error];
            if (error || !chunk.length) break;
            CC_SHA256_Update(&context, chunk.bytes, (CC_LONG)chunk.length);
        }
    }
    [handle closeFile];
    if (error) return nil;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &context);
    NSMutableString *hex = [NSMutableString stringWithCapacity:2 * CC_SHA256_DIGEST_LENGTH];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

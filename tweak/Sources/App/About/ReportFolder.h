#import <Foundation/Foundation.h>

// A new identifier is publishable only after its directory exists.
static inline NSURL *SGCreateReportFolder(NSURL *root) {
    if (!root) return nil;
    NSURL *folder = [root URLByAppendingPathComponent:NSUUID.UUID.UUIDString.lowercaseString isDirectory:YES];
    return [NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil] ? folder : nil;
}

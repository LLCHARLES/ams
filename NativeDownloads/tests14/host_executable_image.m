#import <Foundation/Foundation.h>
#include "NativeAdmission.h"
#include <assert.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <unistd.h>

int main(void) {@autoreleasepool {
    // LiveContainer: dyld's image 0 is its own LiveProcess, and the app it dlopens
    // later is the file _NSGetExecutablePath names.
    NSString *folder = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    assert([NSFileManager.defaultManager createDirectoryAtPath:[folder stringByAppendingPathComponent:@"Spotify.app"] withIntermediateDirectories:YES attributes:nil error:nil]);
    NSString *app = [folder stringByAppendingPathComponent:@"Spotify.app/Spotify"];
    NSString *other = [folder stringByAppendingPathComponent:@"Spotify"];
    assert([@"app" writeToFile:app atomically:NO encoding:NSUTF8StringEncoding error:nil]);
    assert([@"other" writeToFile:other atomically:NO encoding:NSUTF8StringEncoding error:nil]);
    NSString *respelled = [folder stringByAppendingPathComponent:@"Spotify.app/../Spotify.app/Spotify"];
    const struct mach_header *loader = (const void *)0x1000, *guest = (const void *)0x2000;

    assert(SAPImageIsHostExecutable(guest, app.UTF8String, loader, app.UTF8String));
    assert(SAPImageIsHostExecutable(guest, respelled.UTF8String, loader, app.UTF8String));
    // Another file named Spotify, an unreadable executable path or no image never pass.
    assert(!SAPImageIsHostExecutable(guest, other.UTF8String, loader, app.UTF8String));
    assert(!SAPImageIsHostExecutable(guest, app.UTF8String, loader, NULL));
    assert(!SAPImageIsHostExecutable(guest, NULL, loader, app.UTF8String));
    assert(!SAPImageIsHostExecutable(NULL, app.UTF8String, NULL, app.UTF8String));
    // A normal launch: image 0 is the app, whatever the paths say.
    assert(SAPImageIsHostExecutable(loader, NULL, loader, NULL));

    // The real process: its executable is admitted, a system library is not.
    assert(SAPIsHostExecutableImage(_dyld_get_image_header(0)));
    Dl_info info;
    assert(dladdr((const void *)&dladdr, &info) && info.dli_fbase);
    assert(!SAPIsHostExecutableImage(info.dli_fbase));
    // Once the guest is admitted, only that exact header matches: not LiveProcess
    // at image 0, not an address inside the guest; and its unload revokes it.
    static const uint8_t guestImage[64];
    const struct mach_header *admitted = (const void *)guestImage;
    assert(!SAPIsAdmittedMainImage(admitted));
    SAPTestAdmitMainImage(admitted);
    assert(SAPIsAdmittedMainImage(admitted));
    assert(!SAPIsAdmittedMainImage(_dyld_get_image_header(0)));
    assert(!SAPIsAdmittedMainImage((const void *)(guestImage + 16)));
    assert(!SAPIsAdmittedMainImage(NULL));
    SAPTestRemoveImage(_dyld_get_image_header(0));
    assert(SAPIsAdmittedMainImage(admitted));
    SAPTestRemoveImage(admitted);
    assert(!SAPIsAdmittedMainImage(admitted));
    [NSFileManager.defaultManager removeItemAtPath:folder error:nil];
    puts("PASS: the host executable is image 0, or the later image whose file _NSGetExecutablePath names; lookalikes are rejected");
    return 0;
}}

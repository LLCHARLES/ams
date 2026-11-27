#import <Foundation/Foundation.h>
#import "SupportLog.h"
#include <assert.h>
int main(void) {@autoreleasepool {
    NSURL *folder=[NSURL fileURLWithPath:[NSTemporaryDirectory()stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:NULL];
    NSMutableArray *files=[NSMutableArray array];
    NSString *(^redact)(NSString *)=^NSString *(NSString *s){return [s stringByReplacingOccurrencesOfString:@"private" withString:@"[redacted]"];};
    for(NSString *name in @[@"eeveespotify_debug.log",@"SpotifyAudioProbeJournal.log",@"retrine-diagnostics.txt"]) {
        NSURL *url=[folder URLByAppendingPathComponent:name];
        [@"private\nUnicode: ✓\n" writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        NSDictionary *entry=SAPSupportLogReadFile(url,redact);assert([entry[@"content"]isEqual:@"[redacted]\nUnicode: ✓\n"]);[files addObject:entry];
        assert(!SAPSupportLogReadFile(url,nil)[@"content"]);
    }
    NSURL *binary=[folder URLByAppendingPathComponent:@"non-utf8.log"];
    NSData *raw=[NSData dataWithBytes:(uint8_t[]){0xff,0x00,0xfe} length:3];[raw writeToURL:binary atomically:YES];
    NSDictionary *binaryEntry=SAPSupportLogReadFile(binary,redact);assert(!binaryEntry[@"content"]);[files addObject:binaryEntry];
    NSDictionary *missing=SAPSupportLogReadFile([folder URLByAppendingPathComponent:@"missing.log"],redact);
    assert([missing[@"read_status"]isEqual:@"unavailable"]);[files addObject:missing];
    NSDictionary *journal=@{@"snapshots":@{@"license_status":@{@"free_licenses":@0,@"max_licenses":@5}},@"core_errors":@[@{@"code":@7028}]};
    NSURL *out=[folder URLByAppendingPathComponent:@"PixieSupportLog.json"];NSError *error=nil;
    NSDictionary *device=@{@"device_id":@"private-device-17",@"cache_id":@"old-cache-id",@"name":@"Personal phone",@"selection_token":@"opaque-row-token"};
    NSDictionary *oldFacts=@{@"devices":@[device],@"response_base64":@"T2xkUmVnaXN0cnk="};
    NSDictionary *action=@{@"event":@"offline_slot_registry_read",@"facts":oldFacts};
    NSString *old=[[NSString alloc]initWithData:[NSJSONSerialization dataWithJSONObject:action options:0 error:nil] encoding:NSUTF8StringEncoding];
    for(NSString *name in @[@"PixieActions.log",@"PixieActions.1.log"]) {
        NSURL *url=[folder URLByAppendingPathComponent:name];
        [[old stringByAppendingString:@"\n{\"event\":\"keep_action\",\"facts\":{\"note\":\"private\"}}\npartial opaque-row-token"]
             writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        NSDictionary *entry=SAPSupportLogReadFile(url,redact);
        assert([entry[@"content"] containsString:@"keep_action"] && [entry[@"content"] containsString:@"[redacted]"]);
        [files addObject:entry];
    }
    NSDictionary *keep=@{@"event_id":@1,@"category":@"startup",@"stage":@"ready"};
    NSDictionary *trace=@{@"events":@[keep,@{@"category":@"offline_devices",@"stage":@"registry_readback",@"facts":oldFacts},
        @{@"category":@"pixie_action",@"stage":@"offline_slot_release_confirmed",@"facts":@{@"selected_cache_ids":@[@"opaque-row-token"]}},
        @{@"category":@"operation",@"stage":@"begin",@"facts":@{@"kind":@"management_https_request",@"path":@"offline/v1/devices/old-path-id/cache/other/disable"}},
        @{@"category":@"startup",@"stage":@"snapshot",@"facts":@{@"compatibility_check":oldFacts}}],@"coverage":@{@"scope":@"fixture"}};
    assert(SAPSupportLogWrite(out,@{@"configured_mode":@0,@"diagnostic_trace":trace},journal,@"DEVICE_LIMIT_REACHED",files,&error));
    NSDictionary *result=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:out] options:0 error:&error];
    assert([result[@"sections"][@"download_journal"]isEqual:journal]);
    assert([result[@"sections"][@"log_files"]isEqual:files]);
    assert([result[@"sections"][@"download_summary"]isEqual:@"DEVICE_LIMIT_REACHED"]);
    assert([result[@"log_schema"]isEqual:@"Pixie support log 3"] && [result[@"sections"][@"trace"][@"events"] isEqual:@[keep]]);
    NSString *package=[NSString stringWithContentsOfURL:out encoding:NSUTF8StringEncoding error:NULL];
    for(NSString *secret in @[@"device-17",@"old-cache-id",@"Personal phone",@"opaque-row-token",@"T2xkUmVnaXN0cnk=",@"old-path-id"])
        assert(![package containsString:secret]);
    assert(!result[@"sections"][@"diagnostics"][@"diagnostic_trace"]);
    assert(!SAPSupportLogWrite([folder URLByAppendingPathComponent:@"missing/out.json"],@{},@{},@"",@[],&error));
    [NSFileManager.defaultManager removeItemAtURL:folder error:NULL];
    puts("PASS package includes redacted text only; binary and unredactable attachments omitted");
}return 0;}

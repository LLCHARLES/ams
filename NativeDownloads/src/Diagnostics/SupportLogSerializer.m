#import "SupportLog.h"

// Old action/trace files outlive the code that produced them. Omit device
// operations as units: besides dictionary values a URL path or opaque wire
// payload can carry an identity. Leave the originals on disk untouched.
static BOOL deviceAction(NSString *event) {
    return [event hasPrefix:@"offline_slot_"] || [event hasPrefix:@"offline_current_device_"] ||
           [event hasPrefix:@"quota_license_check_"];
}
static BOOL includesRegistry(id value) {
    if([value isKindOfClass:NSDictionary.class]) {
        NSDictionary *fields=value;
        if(fields[@"device_id"] || fields[@"cache_id"] || fields[@"selection_token"] ||
           fields[@"selected_cache_ids"] || fields[@"released_cache_ids"] || fields[@"response_base64"])return YES;
        for(NSString *key in fields)if(includesRegistry(fields[key]))return YES;
    }else if([value isKindOfClass:NSArray.class])
        for(id item in value)if(includesRegistry(item))return YES;
    return NO;
}
static NSString *exportableActionLines(NSString *text) {
    NSMutableArray *safe=[NSMutableArray array];
    [text enumerateLinesUsingBlock:^(NSString *line,BOOL *stop){
        id row=[NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
        if([row isKindOfClass:NSDictionary.class] && [row[@"event"] isKindOfClass:NSString.class] &&
           !deviceAction(row[@"event"]) && !includesRegistry(row))[safe addObject:line];
    }];
    return [safe componentsJoinedByString:@"\n"];
}
static NSDictionary *exportableTrace(NSDictionary *trace) {
    NSMutableArray *events=[NSMutableArray array];
    for(NSDictionary *row in trace[@"events"]) {
        NSString *category=row[@"category"],*stage=row[@"stage"];
        if([category isEqual:@"offline_devices"] || [category isEqual:@"compatibility"] ||
           ([category isEqual:@"pixie_action"] && [stage isKindOfClass:NSString.class] && deviceAction(stage)) ||
           ([category isEqual:@"operation"] && [row[@"facts"] isKindOfClass:NSDictionary.class] &&
            [row[@"facts"][@"kind"] isEqual:@"management_https_request"]) || includesRegistry(row))continue;
        [events addObject:row];
    }
    NSMutableDictionary *copy=[trace mutableCopy];copy[@"events"]=events;return copy;
}

NSDictionary *SAPSupportLogReadFile(NSURL *url,NSString *(^redact)(NSString *)) {
    NSError *error=nil;
    NSData *data=[NSData dataWithContentsOfURL:url options:0 error:&error];
    NSMutableDictionary *entry=[@{@"name":url.lastPathComponent?:@"unknown",
        @"captured_at":[[NSISO8601DateFormatter new]stringFromDate:NSDate.date]} mutableCopy];
    if(!data) {
        entry[@"read_status"]=@"unavailable";
        entry[@"error_domain"]=error.domain?:@"unknown";entry[@"error_code"]=@(error.code);
    }else {
        NSString *text=[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];
        if(text && ([url.lastPathComponent isEqual:@"PixieActions.log"] || [url.lastPathComponent isEqual:@"PixieActions.1.log"]))
            text=exportableActionLines(text);
        NSString *safe=text && redact ? redact(text) : nil;
        if(safe) {
            entry[@"read_status"]=@"included";entry[@"encoding"]=@"utf-8";entry[@"content"]=safe;
            entry[@"bytes"]=@([safe lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
        }else {
            entry[@"read_status"]=@"omitted";entry[@"error"]=text?@"redaction unavailable":@"not UTF-8 text";
        }
    }
    return entry;
}
BOOL SAPSupportLogWrite(NSURL *url,NSDictionary *diagnostics,NSDictionary *journal,
                        NSString *summary,NSArray *files,NSError **error) {
    NSMutableDictionary *report=[diagnostics mutableCopy]?:[NSMutableDictionary dictionary];
    NSDictionary *trace=report[@"diagnostic_trace"]?exportableTrace(report[@"diagnostic_trace"]):@{@"status":@"not_included"};[report removeObjectForKey:@"diagnostic_trace"];
    NSDictionary *value=@{@"log_schema":@"Pixie support log 3",
        @"generated_at":[[NSISO8601DateFormatter new]stringFromDate:NSDate.date],
        @"snapshot_note":@"Sections have their own observation times. File contents are captured separately; this is not an atomic snapshot of Spotify or its server.",
        @"sections":@{@"diagnostics":report,@"trace":trace,@"download_journal":journal?:@{},
            @"download_summary":summary?:@"",@"log_files":files?:@[]}};
    NSData *data=[NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:error];
    return data && [data writeToURL:url options:NSDataWritingAtomic error:error];
}

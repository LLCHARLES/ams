#pragma once
#import <Foundation/Foundation.h>
NSDictionary *SAPSupportLogReadFile(NSURL *url, NSString *(^redact)(NSString *));
BOOL SAPSupportLogWrite(NSURL *url, NSDictionary *diagnostics, NSDictionary *journal,
                        NSString *summary, NSArray *files, NSError **error);

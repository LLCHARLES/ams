#import <Foundation/Foundation.h>

// The receipt belongs to this particular linked import, not to a name in Files.
BOOL SGWriteImportedLyric(NSString *text, NSURL *url, NSDictionary **receipt, NSError **error);
BOOL SGRemoveRetiredLyric(NSURL *folder, id receipt, BOOL *removed);

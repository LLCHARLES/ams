// Offline lyrics. All file work is serialized on a utility queue;
// completions arrive on main. The codec does no I/O and may be used on either queue.
#import <Foundation/Foundation.h>
@class SGKaraokeLine, SGLyricsResult;

// The codec preserves each translation's own language provenance, independently of preferences.
NSDictionary *SGLyricsStoreEncode(NSArray<SGKaraokeLine *> *lines, NSString *credit);
NSArray<SGKaraokeLine *> *SGLyricsStoreDecode(id record, NSString **credit);
// Shared live/store acceptance rule. Copies only changed lines (including nested lines);
// Any keeps all, a specific target drops unknown/mismatched provider translations.
// Generated translations remain owned by their separate store.
NSArray<SGKaraokeLine *> *SGLyricsProviderTranslationsForLanguage(NSArray<SGKaraokeLine *> *lines, NSString *language);
// Save is called on main to snapshot the provider's credit registry along with its lines.
void SGLyricsStoreSave(NSString *track, NSArray<SGKaraokeLine *> *lines, NSString *credit);
// Loading does not register credits. The caller registers metadata only after accepting the lines.
// A specific selection at delivery discards unknown or mismatched translation languages; Any keeps them.
void SGLyricsStoreLoad(NSString *track, void (^done)(NSArray<SGKaraokeLine *> *lines, NSString *credit, SGLyricsResult *metadata));
void SGLyricsStoreDelete(NSString *track);
void SGLyricsStoreSize(void (^done)(unsigned long long bytes));
void SGLyricsStoreDeleteAll(void (^done)(unsigned long long remainingBytes));

@class SGLyricsLease;
typedef NS_ENUM(NSInteger, SGBulkWrite) { SGBulkFailed, SGBulkWritten, SGBulkAlreadyPresent, SGBulkCapacity };
extern NSNotificationName const SGLyricsStoreChanged;
void SGLyricsStoreInventory(NSArray<NSString *> *tracks, void (^done)(NSSet<NSString *> *present, unsigned long long writableBytes));
void SGLyricsStoreAddAutomatic(NSString *track, SGLyricsResult *result, SGLyricsLease *lease, void (^done)(SGBulkWrite));
void SGLyricsStoreRemoveAutomatic(NSArray<NSString *> *tracks);

// For tests only: enqueue an isolated directory and caps, resetting the prune cooldown.
// Call before any test operations. Nothing touches the real store in that case.
void SGLyricsStoreConfigureForTests(NSURL *directory, NSUInteger countCap, unsigned long long byteCap);

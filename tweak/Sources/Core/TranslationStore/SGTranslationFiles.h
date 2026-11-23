#import <Foundation/Foundation.h>

extern NSUInteger const SGTranslationRecordBytes;
extern NSUInteger const SGTranslationTransferBytes;
extern NSUInteger const SGTranslationTransferEntries;
NSError *SGTranslationStorageError(NSString *message);
id SGTranslationReadJSON(NSData *data, NSError **error);
BOOL SGTranslationMapValid(id map, NSString *space);
BOOL SGTranslationRecordKeyValid(NSString *key);
NSDictionary *SGTranslationEnvelope(NSString *space, NSString *key, NSDictionary *lines, BOOL recovery);
BOOL SGTranslationEnvelopeValid(id record);
NSString *SGTranslationRecoveryKey(NSDictionary *record);
NSString *SGTranslationRecordIdentity(NSDictionary *record);
NSDictionary *SGTranslationRecordDescriptor(NSDictionary *record, unsigned long long bytes);

// Every method runs on the caller's single storage executor, including reads and migration.
// No method calls main synchronously.
@interface SGTranslationFiles : NSObject
@property (nonatomic, readonly) NSURL *root;
@property (nonatomic, readonly) NSURL *legacy;
@property (nonatomic, readonly) NSArray<NSDictionary *> *unresolved;
@property (nonatomic) unsigned long long ceiling;
- (instancetype)initWithRoot:(NSURL *)root legacy:(NSURL *)legacy;
// Read both the active cache and any conflicting files left at its previous name.
- (instancetype)initWithRoot:(NSURL *)root renamedCache:(NSURL *)cache;
- (BOOL)prepare:(NSError **)error;
- (NSNumber *)importAuthority:(NSError **)error;
- (BOOL)permitsImport:(NSDictionary *)record authority:(NSNumber *)authority error:(NSError **)error;
- (BOOL)migrate:(NSError **)error;
- (NSDictionary *)read:(NSString *)space key:(NSString *)key error:(NSError **)error;
- (BOOL)save:(NSDictionary *)lines space:(NSString *)space key:(NSString *)key
     replace:(BOOL)replace preserveMissing:(BOOL)preserveMissing grandfather:(BOOL)grandfather
     allowed:(BOOL (^)(void))allowed error:(NSError **)error;
- (BOOL)enumerateRecords:(BOOL (^)(NSDictionary *descriptor, NSError **error))visit
        includeRecovery:(BOOL)includeRecovery error:(NSError **)error;
- (NSDictionary *)record:(NSDictionary *)descriptor error:(NSError **)error;
- (NSDictionary *)summary:(NSError **)error;
- (unsigned long long)bytes:(NSError **)error;
- (BOOL)removeRecords:(NSArray<NSDictionary *> *)records all:(BOOL)all error:(NSError **)error;
- (BOOL)writeJSON:(id)value to:(NSURL *)url grandfather:(BOOL)grandfather
          allowed:(BOOL (^)(void))allowed error:(NSError **)error;
- (BOOL)installRecovery:(NSDictionary *)record grandfather:(BOOL)grandfather error:(NSError **)error;
@end

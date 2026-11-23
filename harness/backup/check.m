#import "App/About/Backup.m"
#import "../harness-fail.h"

int main(void) {
    @autoreleasepool {
        NSString *suite = [@"retrine.backup.check." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *store = [[NSUserDefaults alloc] initWithSuiteName:suite];
        NSString *wg = @"spotifyglass.wireguard", *server = SGKeySponsorBlockServer;
        NSString *ordinary = SGKeySponsorBlock;
        NSDictionary *local = @{wg: @{@"host": @"local.example"}, server: @"https://local.example", ordinary: @NO};
        [store setPersistentDomain:local forName:suite];
        NSDictionary *exported = exportSettings(local);
        importSettings(@{wg: @{@"host": @"import.example"}, server: @"https://import.example", ordinary: @YES}, store, local);
        NSDictionary *after = [store persistentDomainForName:suite];
        [store removePersistentDomainForName:suite];
        BOOL exportOK = [exported isEqual:@{ordinary: @NO}];
        BOOL importOK = [after isEqual:@{wg: local[wg], server: local[server], ordinary: @YES}];
        if (!exportOK || !importOK) HARNESS_FAIL(@"private settings: export %d, import %d", exportOK, importOK);
        puts("backup: ok");
    }
}

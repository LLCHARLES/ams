#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "CredentialSettings.h"

NSString *SGLyricsCleanCredential(NSString *text, NSUInteger maxCharacters) {
    NSMutableCharacterSet *around = [NSCharacterSet.whitespaceAndNewlineCharacterSet mutableCopy];
    [around addCharactersInString:@"\"'“”‘’"];
    NSString *key = [text stringByTrimmingCharactersInSet:around];
    return key.length <= maxCharacters && [key rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location == NSNotFound ? key : nil;
}

void SGLyricsCredentialPrompt(NSString *title, NSString *message, NSString *placeholder,
                             BOOL (^valid)(NSString *), void (^saveKey)(NSString *),
                             BOOL (^hasKey)(void), void (^remove)(void)) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    __weak UIAlertController *weakAlert = alert;
    UIAlertAction *save = [UIAlertAction actionWithTitle:SGL(@"common.save", @"Save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        saveKey(weakAlert.textFields.firstObject.text);
    }];
    save.enabled = NO;
    __weak UIAlertAction *weakSave = save;
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = placeholder;
        field.secureTextEntry = YES;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        [field addAction:[UIAction actionWithHandler:^(UIAction *action) {
            weakSave.enabled = valid(weakAlert.textFields.firstObject.text);
        }] forControlEvents:UIControlEventEditingChanged];
    }];
    [alert addAction:save];
    if (hasKey()) [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.remove", @"Remove") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { remove(); }]];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    SGPresentDark(alert);
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

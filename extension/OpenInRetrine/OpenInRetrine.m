// Based on FlicksDaModdle/vitrine 5c0401a (GPL-3.0); validation is shared with the receiving app.
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/message.h>
#import "LinkURL.h"

@interface OIRViewController : UIViewController
@end

static const NSUInteger OIRMaximumSharedItems = 8;
static const NSUInteger OIRMaximumItemProviders = 8;

@implementation OIRViewController {
    BOOL _started;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (_started) return;
    _started = YES;
    NSArray *input = self.extensionContext.inputItems;
    NSArray *items = [input subarrayWithRange:NSMakeRange(0, MIN(input.count, OIRMaximumSharedItems))];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self findLink:items];
    });
}
- (void)finishWithURL:(NSURL *)url {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (url) [self openURL:url];
        else [self fail:@"There's no Spotify link in what was shared."];
    });
}
- (void)findLink:(NSArray<NSExtensionItem *> *)input {
    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    NSUInteger providers = 0;
    for (NSExtensionItem *item in input) {
        NSURL *url = SGSpotifyLinkInSharedText(item.attributedContentText.string);
        if (url) { [self finishWithURL:SGRetrineURLForSpotifyURL(url)]; return; }
        for (NSItemProvider *provider in item.attachments) {
            if (providers == OIRMaximumItemProviders) break;
            providers++;
            for (NSString *type in @[UTTypeURL.identifier, UTTypePlainText.identifier]) {
                if ([provider hasItemConformingToTypeIdentifier:type])
                    [items addObject:@{@"provider": provider, @"type": type}];
            }
        }
    }
    [self loadItems:items index:0];
}
- (void)loadItems:(NSArray<NSDictionary *> *)items index:(NSUInteger)index {
    if (index == items.count) {
        [self finishWithURL:nil];
        return;
    }
    NSDictionary *entry = items[index];
    [entry[@"provider"] loadItemForTypeIdentifier:entry[@"type"] options:nil completionHandler:^(id item, NSError *error) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSString *text = [item isKindOfClass:NSURL.class] ? [item absoluteString] :
                             ([item isKindOfClass:NSString.class] ? item : nil);
            NSURL *url = SGRetrineURLForSpotifyURL(SGSpotifyLinkInSharedText(text));
            if (url) [self finishWithURL:url];
            else [self loadItems:items index:index + 1];
        });
    }];
}
- (void)openURL:(NSURL *)url {
    void (^finished)(BOOL) = ^(BOOL success) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
            else [self fail:@"iOS didn't let the share sheet open Retrine."];
        });
    };
    // Action extensions cannot use UIApplication.sharedApplication. Sideloaded hosts may expose it
    // on the responder chain; an unavailable or refused handoff is reported, never called a success.
    SEL open = NSSelectorFromString(@"openURL:options:completionHandler:");
    for (UIResponder *responder = self; responder; responder = responder.nextResponder) {
        if ([responder isKindOfClass:NSClassFromString(@"UIApplication")] && [responder respondsToSelector:open]) {
            ((void (*)(id, SEL, NSURL *, NSDictionary *, id))objc_msgSend)(responder, open, url, @{}, finished);
            return;
        }
    }
    [self.extensionContext openURL:url completionHandler:finished];
}
- (void)fail:(NSString *)message {
    NSBundle *bundle = [NSBundle bundleForClass:OIRViewController.class];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"]
                                                                 message:[bundle localizedStringForKey:message value:nil table:nil]
                                                          preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"OK" value:nil table:nil]
                                            style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end

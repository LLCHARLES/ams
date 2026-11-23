#import "TranslationLibrary.h"
#import "Core/SGCore.h"
#import "Core/SGGlass.h"
#import "Settings/SGPage.h"
#import "Settings/SGPageStyle.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface SGTranslationLibraryPage : SGPage <UIDocumentPickerDelegate>
@property NSArray<NSDictionary *> *records;
@property NSMutableIndexSet *selected;
@property NSString *warning;
@property BOOL busy;
@property NSString *pageStart, *nextPage;
@property NSMutableArray<NSString *> *previousPages;
@property NSDictionary *summary;
@end

@implementation SGTranslationLibraryPage
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = SGL(@"settings.translation.savedtranslations.title", @"Saved translations");
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    _selected = [NSMutableIndexSet indexSet];
    _previousPages = [NSMutableArray array];
    [self reload];
}
- (void)reload {
    _busy = YES;
    __weak typeof(self) weak = self;
    SGSavedRecords(_pageStart, ^(NSArray *records, NSString *next, NSDictionary *summary, NSString *warning) {
        SGTranslationLibraryPage *page = weak;
        if (!page) return;
        page.busy = NO; page.records = records ?: @[]; page.warning = warning;
        page.nextPage = next; page.summary = summary;
        [page.selected removeAllIndexes]; [page.tableView reloadData];
    });
}
- (void)show:(UIViewController *)controller {
    SGPresentDark(controller);
    [self presentViewController:controller animated:YES completion:nil];
}
- (void)message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:self.title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.ok", @"OK") style:UIAlertActionStyleCancel handler:nil]];
    [self show:alert];
}
- (void)finish:(NSError *)error {
    _busy = NO;
    if (error) [self message:error.localizedDescription];
    [self reload];
}
- (NSArray *)selection { return [_records objectsAtIndexes:_selected]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return 3; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 8 : section == 1 ? (NSInteger)_records.count : (NSInteger)(_previousPages.count > 0) + (NSInteger)(_nextPage != nil);
}
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section {
    if (!section) return _busy ? SGL(@"settings.translation.library.working", @"Working…") :
        [NSString stringWithFormat:@"%@ · %@", [NSString stringWithFormat:SGL(@"settings.translation.library.count", @"%lu records"), [_summary[@"count"] unsignedLongValue]],
            [NSByteCountFormatter stringFromByteCount:[_summary[@"bytes"] longLongValue] countStyle:NSByteCountFormatterCountStyleFile]];
    return section == 1 ? SGL(@"settings.translation.library.records", @"Active and recovery records") : nil;
}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    if (!section) return _warning;
    if (section == 2) return nil;
    return SGL(@"settings.translation.library.footer", @"Tap records to select them. Recovery copies are never automatically deleted. Export before uninstalling or going back to an older version: an older version may not see these records.");
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [table dequeueReusableCellWithIdentifier:@"saved"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"saved"];
    cell.textLabel.numberOfLines = 0; cell.detailTextLabel.numberOfLines = 0;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.textLabel.textColor = UIColor.labelColor;
    cell.detailTextLabel.text = nil;
    if (!path.section) {
        cell.textLabel.text = @[
            SGL(@"settings.translation.library.exportall", @"Export all (including recovery)"),
            SGL(@"settings.translation.library.exportselected", @"Export selected"),
            SGL(@"settings.translation.library.import", @"Import JSON or ZIP"),
            SGL(@"settings.translation.library.retry", @"Retry saves / resume import and migration"),
            SGL(@"settings.translation.library.restore", @"Restore selected recovery record"),
            SGL(@"settings.translation.library.deleteselected", @"Delete selected"),
            SGL(@"settings.translation.library.deleteall", @"Delete all saved records"),
            SGL(@"settings.translation.library.refresh", @"Refresh")
        ][path.row];
        if (path.row == 5 || path.row == 6) cell.textLabel.textColor = UIColor.systemRedColor;
    } else if (path.section == 1) {
        NSDictionary *record = _records[path.row];
        BOOL recovery = [record[@"recovery"] boolValue], unsaved = [record[@"unsaved"] boolValue];
        NSString *kind = unsaved ? SGL(@"settings.translation.library.unsavedlabel", @"Not saved") :
            recovery ? SGL(@"settings.translation.library.recovery", @"Recovery") : record[@"namespace"];
        cell.textLabel.text = record[@"key"];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", kind,
            [NSByteCountFormatter stringFromByteCount:[record[@"bytes"] longLongValue] countStyle:NSByteCountFormatterCountStyleFile]];
        cell.accessoryType = [_selected containsIndex:path.row] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    } else {
        cell.textLabel.text = _previousPages.count && path.row == 0 ? SGL(@"settings.translation.library.previous", @"Previous records") :
            SGL(@"settings.translation.library.next", @"Next records");
    }
    cell.userInteractionEnabled = !_busy;
    cell.contentView.alpha = _busy ? 0.5 : 1;
    return cell;
}
- (void)export:(NSArray *)selection {
    _busy = YES; [self.tableView reloadData];
    SGSavedExport(selection, ^(NSArray<NSURL *> *files, NSError *error) {
        self.busy = NO; [self.tableView reloadData];
        if (error) { [self message:error.localizedDescription]; return; }
        UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:files applicationActivities:nil];
        sheet.popoverPresentationController.sourceView = self.view;
        sheet.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2, 1, 1);
        sheet.completionWithItemsHandler = ^(UIActivityType type, BOOL completed, NSArray *returned, NSError *failure) {
            NSError *cleanup = nil;
            if (![NSFileManager.defaultManager removeItemAtURL:files.firstObject.URLByDeletingLastPathComponent error:&cleanup])
                [self message:cleanup.localizedDescription];
        };
        [self show:sheet];
    });
}
- (void)confirmDelete:(BOOL)all {
    NSArray *selection = [self selection];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGL(@"settings.translation.library.deleteconfirm", @"Delete saved records?")
        message:all ? SGL(@"settings.translation.library.deletewarning", @"This deletes active records, recovery copies and the legacy Caches copies. Migration suppression is kept. If any deletion fails, the remaining copies will be reported.")
                    : SGL(@"settings.translation.library.selectedwarning", @"Only the selected records are deleted. Deleting an active record also suppresses its legacy cache copy.")
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.delete", @"Delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        self.busy = YES; [self.tableView reloadData];
        SGSavedRemove(selection, all, ^(NSError *error) { [self finish:error]; });
    }]];
    [self show:alert];
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (_busy) return;
    if (path.section == 2) {
        if (_previousPages.count && path.row == 0) {
            _pageStart = _previousPages.lastObject.length ? _previousPages.lastObject : nil;
            [_previousPages removeLastObject];
        } else {
            [_previousPages addObject:_pageStart ?: @""];
            _pageStart = _nextPage;
        }
        [self reload]; return;
    }
    if (path.section == 1) {
        if ([_selected containsIndex:path.row]) [_selected removeIndex:path.row]; else [_selected addIndex:path.row];
        [table reloadRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationNone]; return;
    }
    if ((path.row == 1 || path.row == 4 || path.row == 5) && !_selected.count) {
        [self message:SGL(@"settings.translation.library.select", @"Select at least one record.")]; return;
    }
    switch (path.row) {
        case 0: [self export:nil]; break;
        case 1: [self export:[self selection]]; break;
        case 2: {
            UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeJSON, UTTypeZIP] asCopy:YES];
            picker.delegate = self; [self show:picker]; break;
        }
        case 3: {
            _busy = YES; [table reloadData];
            SGSavedRetry(^(NSError *error) { [self finish:error]; });
            break;
        }
        case 4: {
            NSDictionary *record = [self selection].firstObject;
            if (_selected.count != 1 || ![record[@"recovery"] boolValue]) { [self message:SGL(@"settings.translation.library.selectrecovery", @"Select one recovery record to restore.")]; break; }
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGL(@"settings.translation.library.restore", @"Restore selected recovery record")
                message:SGL(@"settings.translation.library.restorewarning", @"The current active record will first be preserved as a recovery copy.")
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:SGL(@"settings.translation.library.restoreaction", @"Restore") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
                self.busy = YES; SGSavedRestore(record, ^(NSError *error) { [self finish:error]; });
            }]];
            [self show:alert]; break;
        }
        case 5: [self confirmDelete:NO]; break;
        case 6: [self confirmDelete:YES]; break;
        case 7: _pageStart = nil; [_previousPages removeAllObjects]; [self reload]; break;
    }
}
- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    BOOL scoped = [url startAccessingSecurityScopedResource];
    _busy = YES; [self.tableView reloadData];
    SGSavedImport(url, NO, YES, ^(NSDictionary *preview, NSError *error) {
        if (scoped) [url stopAccessingSecurityScopedResource];
        self.busy = NO; [self.tableView reloadData];
        if (error) { [self message:error.localizedDescription]; return; }
        NSString *message = [NSString stringWithFormat:SGL(@"settings.translation.library.preview", @"%lu new · %lu matching · %lu conflicting records. Merge keeps local values and preserves incoming conflicts in recovery. Replace first preserves each previous record."),
            [preview[@"added"] unsignedLongValue], [preview[@"matching"] unsignedLongValue], [preview[@"conflicts"] unsignedLongValue]];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGL(@"settings.translation.library.import", @"Import JSON or ZIP") message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
            SGSavedDiscardPreview(^(NSError *failure) { if (failure) [self message:failure.localizedDescription]; });
        }]];
        for (NSNumber *replace in @[@NO, @YES]) [alert addAction:[UIAlertAction actionWithTitle:replace.boolValue ?
            SGL(@"settings.translation.library.replace", @"Replace matching records") : SGL(@"settings.translation.library.merge", @"Merge — keep local values")
            style:replace.boolValue ? UIAlertActionStyleDestructive : UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                self.busy = YES; [self.tableView reloadData];
                SGSavedImport(url, replace.boolValue, NO, ^(NSDictionary *report, NSError *failure) {
                    NSString *result = [NSString stringWithFormat:SGL(@"settings.translation.library.importresult", @"%lu of %lu records committed.%@"),
                        [report[@"completed"] unsignedLongValue], (unsigned long)[report[@"records"] count],
                        failure ? [@"\n" stringByAppendingString:failure.localizedDescription] : @""];
                    [self message:result]; [self reload];
                });
            }]];
        [self show:alert];
    });
}
@end

UIViewController *SGSavedTranslationsPage(void) { return [[SGTranslationLibraryPage alloc] initWithStyle:UITableViewStyleInsetGrouped]; }

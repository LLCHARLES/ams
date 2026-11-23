#import "../timer-lifecycle.h"
#import "Settings/SGModPage.h"

void SGCheckSettingsBackground(void) {
    SGModPage *page = [[SGModPage alloc] initWithTitle:@"Live values" intro:nil
        sections:@[SGSection(nil, @[SGStatRow(@"Value", ^NSString *{ return @"1"; })])] footer:nil];
    SGHarnessCheckPageBackground(page);
    puts("PASS settings refresh stops in background and resumes only on a visible page");
}

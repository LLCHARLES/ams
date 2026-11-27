"""Use the shipped label, layout callback and driver fallback without linking Spotify or ReplayKit."""
from pathlib import Path
import sys

src, out = map(Path, sys.argv[1:])
def part(file, start, end):
    text = (src / file).read_text()
    return text[text.index(start):text.index(end, text.index(start))]

label = part("App/Onboarding/WhatsNew.m", "static UILabel *label(", "#pragma mark - the sheet")
layout = part("App/About/Report.m", "- (void)viewDidLayoutSubviews", "- (void)viewDidAppear:")
sort = part("Diagnostics/Driver.m", "[buttons sort", "// The glass bar stacks")
(out / "audit.inc").write_text(label + '''
@interface ReportLayout : UITableViewController
@end
@implementation ReportLayout
''' + layout + '''
@end
static CGRect screenFrame(UIView *v) { return v.frame; }
static void sortButtons(NSMutableArray *buttons) {
''' + sort + "}\n")

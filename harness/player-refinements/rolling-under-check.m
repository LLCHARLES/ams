#import <CoreText/CoreText.h>
NSUInteger harnessShapedLines;
static CTLineRef countedLine(CFAttributedStringRef value) {
    harnessShapedLines++;
    return CTLineCreateWithAttributedString(value);
}
#define CTLineCreateWithAttributedString countedLine
#define SG_MEDIA_CLOCK SGHarnessDigitsTime
#import "SGRRollingDigits.m"

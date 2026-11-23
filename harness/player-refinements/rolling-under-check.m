#import <CoreText/CoreText.h>
NSUInteger harnessShapedLines;
static CTLineRef countedLine(CFAttributedStringRef value) {
    harnessShapedLines++;
    return CTLineCreateWithAttributedString(value);
}
#define CTLineCreateWithAttributedString countedLine
#import "SGRRollingDigits.m"

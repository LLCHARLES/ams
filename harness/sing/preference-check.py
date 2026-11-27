#!/usr/bin/env python3
"""Run the production preference/row/mic slices on Foundation, without a GUI.

SingSettings and SGRKaraokeView otherwise require the entire audio/UI stack.
Extract executable bodies (not text assertions); only UI objects and the OS
capability boundary are doubles. SGPrefs is linked unchanged.
"""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "tweak/Sources"


def body(text, signature):
    start = text.index(signature)
    opening = text.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (text[end] == "{") - (text[end] == "}")
        end += 1
    return text[start:end]


settings = (SRC / "Shared/Sing/SingSettings.m").read_text()
view = (SRC / "Redesigned/Lyrics/SGRKaraokeView.m").read_text()
header = (SRC / "Shared/Sing/Sing.h").read_text()
keys = "\n".join(line for line in header.splitlines()
                 if line.startswith("#define SGKeySing "))
keys += "\n" + next(line for line in header.splitlines()
                    if line.startswith("#define SGKeySingButton "))
helper = body(settings, "BOOL SGSingButtonShown(void)")
control = (SRC / "Shared/Sing/Sing.x").read_text()
migration = control[control.index("    NSUserDefaults *defaults =", control.index("%ctor {")):
                    control.index("    // The 489 MB model", control.index("%ctor {"))]
keys += "\n" + "\n".join(line for line in header.splitlines()
                         if line.startswith("#define SGKeySingComputeUnits"))
row = settings[settings.index("    SGModRow *button ="):
               settings.index("    SGModRow *heat =")]
initial = next(line for line in view.splitlines() if "_sing.hidden =" in line)
changed = body(view, "- (void)singButtonChanged")
fixture = r'''
#import <Foundation/Foundation.h>
#import "Core/SGPrefs.h"
#define SGL(key, english) english
static BOOL supported;
BOOL SGSingOSSupported(void) { return supported; }
BOOL SGRedesignedUIStored(void) { return YES; }
NSNotificationName const SGSingButtonDidChangeNotification = @"mic-changed";
@interface SGModRow : NSObject
@property BOOL defaultOn;
@property(copy) NSString *key;
@property(copy) void (^changed)(BOOL);
@property(copy) BOOL (^visible)(void);
@end
@implementation SGModRow
@end
SGModRow *SGSwitchRow(NSString *title, NSString *subtitle, NSString *key) {
    SGModRow *r = [SGModRow new]; r.key = key; r.defaultOn = YES; return r;
}
@interface Mic : NSObject
@property BOOL hidden;
@end
@implementation Mic
@end
'''
test = r'''
int main(void) { @autoreleasepool {
    NSUserDefaults *prefs = NSUserDefaults.standardUserDefaults;
    [prefs setInteger:1 forKey:SGKeySingComputeUnits];
    [prefs setInteger:3 forKey:SGKeySingComputeUnitsBefore];
    migrate();
    if ([prefs integerForKey:SGKeySingComputeUnits] != 1 || [prefs objectForKey:SGKeySingComputeUnitsBefore]) return 1;
    [prefs setInteger:2 forKey:SGKeySingComputeUnits];
    migrate();
    if ([prefs objectForKey:SGKeySingComputeUnits]) return 1;
    __block unsigned changes = 0;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification
        object:nil queue:nil usingBlock:^(NSNotification *n) { changes++; }];
    migrate();
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    if (changes) { NSLog(@"FAIL clean Sing launch posted %u changes", changes); return 1; }
    [prefs removeObjectForKey:SGKeyStock];
    [prefs setBool:YES forKey:SGKeySing];
    NSArray *values = @[NSNull.null, @YES, @NO];
    BOOL expected[2][3] = {{NO, YES, NO}, {YES, YES, NO}};
    for (int os = 0; os < 2; os++) {
        supported = os;
        SGModRow *row = makeRow();
        if (row.defaultOn != (BOOL)os) { NSLog(@"FAIL row default at OS boundary"); return 1; }
        for (int choice = 0; choice < 3; choice++) {
            if (choice == 0) [prefs removeObjectForKey:SGKeySingButton];
            else [prefs setObject:values[choice] forKey:SGKeySingButton];
            SGPrefsChanged();
            Lyrics *lyrics = [Lyrics new];
            BOOL shown = expected[os][choice];
            if (lyrics.sing.hidden == shown || SGSingButtonShown() != shown ||
                SGFlag(row.key, row.defaultOn) != shown) {
                NSLog(@"FAIL OS=%d preference=%d: row and initial mic", os, choice); return 1;
            }
            [prefs setBool:!shown forKey:SGKeySingButton]; SGPrefsChanged();
            row.changed(!shown);
            if (lyrics.sing.hidden != shown || ![prefs boolForKey:SGKeySing]) {
                NSLog(@"FAIL live mic update or Karaoke switch changed"); return 1;
            }
            [NSNotificationCenter.defaultCenter removeObserver:lyrics];
        }
    }
    puts("PASS Sing unset/YES/NO below/at iOS 18: row, initial mic, live update, Karaoke unchanged");
    return 0;
}}
'''
source = fixture + keys + "\n#define SGLog(...) ((void)0)\n" + body(control, "static NSInteger runsOn(void)")
source += "\nstatic void migrate(void) {\n" + migration + "}\n"
source += helper + "\nSGModRow *makeRow(void) {\n" + row + "\nreturn button;\n}\n"
source += r'''
@interface Lyrics : NSObject
@property Mic *sing;
- (void)singButtonChanged;
- (void)setNeedsLayout;
@end
@implementation Lyrics
- (instancetype)init {
    if ((self = [super init])) {
        _sing = [Mic new];
''' + initial + r'''
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(singButtonChanged)
            name:SGSingButtonDidChangeNotification object:nil];
    } return self;
}
- (void)setNeedsLayout {}
''' + changed + "\n@end\n" + test

with tempfile.TemporaryDirectory(prefix="sing-preference-") as temp:
    out = Path(temp)
    (out / "check.m").write_text(source)
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks", "-I" + str(SRC),
                    str(out / "check.m"), str(SRC / "Core/SGPrefs.m"),
                    "-framework", "Foundation", "-o", str(out / "sing-pref-check")], check=True)
    env = dict(os.environ, CFFIXED_USER_HOME=str(out / "home"))
    subprocess.run([str(out / "sing-pref-check")], env=env, check=True)

// Presets and headphones, the two rows under the effects' switch on the Audio effects page.
//
//     AudioEffectsPresets.m       the built-in presets, the user's own, and the GraphicEQ line check
//     AutoEq.m                    AutoEq's index of headphones, cached, and a headphone's GraphicEQ applied
//     AudioEffectsPresetsPage.m   their pages
//
// Main thread, except where a function says otherwise.
#import <Foundation/Foundation.h>

// The user's presets, by name, each the spotifyglass.dsp.* keys as they were saved. Outside the dsp.
// prefix, so a preset never holds the presets.
#define SGKeyDSPUserPresets @"spotifyglass.audioPresets"

#pragma mark - presets

// A built-in preset sets a few effects over a reset, leaving the Graphic EQ (the headphones' correction) as
// it is: the correction belongs to the headphones, not to the taste. Loading any preset, or applying a
// headphone, turns the effects' master switch on too, so the pick is heard.
NSArray<NSString *> *SGDSPBuiltInPresetNames(void);
NSString *SGDSPBuiltInPresetDetail(NSInteger index);   // the effects it turns on, for the row's subtitle
void SGDSPLoadBuiltInPreset(NSInteger index);

// A user's preset is everything: every spotifyglass.dsp.* key but the master switch, Graphic EQ included.
NSArray<NSString *> *SGDSPUserPresetNames(void);   // sorted
void SGDSPSaveUserPreset(NSString *name);          // replaces one of the same name
BOOL SGDSPLoadUserPreset(NSString *name);
// Deleting one an output plays settles it as leaving that output does (SGAutoEqPresetDeleted).
void SGDSPDeleteUserPreset(NSString *name);
// The values of the user's preset `name`, nil when there is none.
NSDictionary<NSString *, id> *SGDSPUserPresetValues(NSString *name);
// Every spotifyglass.dsp.* key as stored now (what a user preset saves; never the master switch).
NSDictionary<NSString *, id> *SGDSPCurrentValues(void);
// Resets every effect, then sets `values` through the setters, as one reconfiguration. Unlike loading a
// preset it leaves the master switch as it is.
void SGDSPApplyValues(NSDictionary<NSString *, id> *values);
// A digest of `values` as the settings read them (SGDSPEffectiveValues: a key left out is its default, a number
// within its range, a switch a flag): the digest of the values about to be applied equals the digest of
// SGDSPCurrentValues() once they are, until something changes, whether or not a key was set explicitly.
NSString *SGDSPValuesDigest(NSDictionary<NSString *, id> *values);

#pragma mark - preset files

// A preset as a file to share and import: {"format": "retrine.audio-preset", "version": 1, "name": ...,
// "values": {key: value}}, the values being the preset's spotifyglass.dsp.* keys (never the master switch) as
// they are stored: booleans, numbers and text. An impulse response, DDC or Liveprog file is named, not carried.
//
// The user's preset `name` as the file's bytes, and a file name for it ("Late night.retrine-preset.json");
// nil when there is no such preset.
NSData *SGDSPPresetFileData(NSString *name, NSString **fileName);
// A file's preset: its values, kept to the keys and types this build knows, and its name (`fallbackName` when
// the file has none). Nil and why not, in the person's language, when it is not one: another format, a later
// version, malformed, over 256 KB, or no value this build can use. Any thread.
NSDictionary<NSString *, id> *SGDSPReadPresetFile(NSData *data, NSString *fallbackName, NSString **name, NSString **error);
// Saves the values as the user's preset `name`, replacing one of the same name.
void SGDSPSaveUserPresetValues(NSString *name, NSDictionary<NSString *, id> *values);
BOOL SGDSPUserPresetExists(NSString *name);
// `name` when no preset of the user's has it, else "name 2", "name 3" and on.
NSString *SGDSPUniquePresetName(NSString *name);
// The impulse response, DDC and Liveprog files the values name that are not in this iPhone's libraries.
NSArray<NSString *> *SGDSPPresetMissingFiles(NSDictionary<NSString *, id> *values);

// The text as one GraphicEQ line, trimmed and on one line, or nil when it is not one: what the Graphic EQ
// editor saves and what a headphone's file is checked with.
NSString *SGDSPGraphicEqLine(NSString *text);

#pragma mark - AutoEq

// One headphone of AutoEq's results (github.com/jaakkopasanen/AutoEq, MIT): the name, who measured it
// ("crinacle on 711"), and its folder under results/ as INDEX.md writes it, percent-encoded.
@interface SGAutoEqHeadphone : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *source;
@property (nonatomic, copy) NSString *path;
@end

// INDEX.md's "- [Name](./path) by source" lines; anything else is skipped. Any thread.
NSArray<SGAutoEqHeadphone *> *SGAutoEqParseIndex(NSString *markdown);
// The raw address of the headphone's "<folder> GraphicEQ.txt". Any thread.
NSURL *SGAutoEqGraphicEqURL(NSString *path);
// The headphones whose name and source hold every word of the query, case and accents aside.
NSArray<SGAutoEqHeadphone *> *SGAutoEqSearch(NSArray<SGAutoEqHeadphone *> *all, NSString *query);

// A headphone's form, told by its folder's text ("in-ear", "over-ear", "earbud", case aside). A headphone
// whose folder says none of them is shown under All only.
typedef NS_ENUM(NSInteger, SGAutoEqForm) {
    SGAutoEqFormAll,
    SGAutoEqFormInEar,
    SGAutoEqFormOverEar,
    SGAutoEqFormEarbuds,
};
NSArray<SGAutoEqHeadphone *> *SGAutoEqFilterByForm(NSArray<SGAutoEqHeadphone *> *all, SGAutoEqForm form);
// The headphone a folder names, for the page's row: its last part, decoded.
NSString *SGAutoEqNameOf(NSString *path);

// The index, from Caches/Retrine/AutoEq unless `refresh` or the copy is a month old, else from GitHub (the
// cached copy still answering when GitHub does not). `done` runs once on the main queue, with the
// headphones, and why GitHub did not answer when it did not.
void SGAutoEqLoadIndex(BOOL refresh, void (^done)(NSArray<SGAutoEqHeadphone *> *headphones, NSString *error));
// Downloads the headphone's GraphicEQ and applies it; `done` on the main queue with nil or why not.
void SGAutoEqApply(SGAutoEqHeadphone *headphone, void (^done)(NSString *error));
// The second half of that: the file's text into the Graphic EQ, its switch and the master switch on. NO when
// it is not GraphicEQ. When the output playing now is remembered (below), the pick becomes its correction.
BOOL SGAutoEqApplyText(NSString *path, NSString *text);
// Whether the Graphic EQ has a headphone correction enabled, regardless of the master switch.
BOOL SGAutoEqCorrectionInUse(void);
// None: the headphone's correction off (a curve of the user's own, with no headphone, stays), and None
// remembered for the output playing now when it is remembered.
void SGAutoEqTakeOff(void);

#pragma mark - a correction per output

// The corrections remembered per output, by the port's UID: {uid: {name, path, nodes}}, `path` and `nodes`
// empty for None. Outside the dsp. prefix, so presets never hold it. And the UID whose correction the Graphic
// EQ plays because its output connected, empty when none does.
#define SGKeyDSPOutputs          @"spotifyglass.audioOutputs"
#define SGKeyDSPOutputFollowed   @"spotifyglass.audioOutputs.followed"
// An output's entry may also hold "preset", the name of one of the user's presets. While audio plays through
// it the preset's values are applied (the entry's remembered correction over its Graphic EQ). The user's own
// values are kept here first: {values: SGDSPCurrentValues() from before, applied: the digest of what was applied,
// output: the UID it was applied for}. Written before the preset is applied, removed once the user's values are
// back or are kept as they are. While a preset is being applied, or the values put back, it also holds
// pending = YES (dropped when the apply is done, the baseline when the restore is): a launch that finds it was
// killed half-way, the values in the settings are half one set and half the other, not the user's edits, and
// are put back. A launch on that same output, with no pending, leaves the values and
// the baseline as they are.
#define SGKeyDSPOutputBaseline   @"spotifyglass.audioOutputs.baseline"
// Posted on the main thread when the output or what is remembered changes.
#define SGAutoEqOutputsChangedNotification @"SGAutoEqOutputsChangedNotification"

// Audio went to another output (AVAudioSession's route, its first output; AudioEffects.x calls this at
// launch and on every route change). A remembered output gets its correction, or None. Another output takes
// off a correction that came on for a remembered one; a correction picked with no output remembered, and a
// curve of the user's own, stay. Nothing happens while the UID stays the same. The master switch is left as
// it is: a route change never turns the effects on.
//
// An output with a preset (a preset since deleted counts as none) gets it as one reconfiguration, the user's
// values kept under SGKeyDSPOutputBaseline first. Going to an output without one puts those values back when
// nothing was changed meanwhile, else keeps what the user has and forgets them; going to another output with a
// preset keeps the first baseline. A baseline left by a launch that was killed on such an output is settled the
// same way when the first output is told, except that the first output being the one it was stored for is no
// change of route: nothing is applied or restored, and the baseline stays for when that output is left.
void SGAutoEqOutputChanged(NSString *uid, NSString *name);
// The output playing now, nil before the first call.
NSString *SGAutoEqOutputUID(void);
NSString *SGAutoEqOutputName(void);
// Remembers the correction in use (or None) for the output playing now, or forgets that output.
void SGAutoEqRememberOutput(BOOL remember);
BOOL SGAutoEqOutputRemembered(NSString *uid);
void SGAutoEqForgetOutput(NSString *uid);
// The remembered outputs, sorted by name: {uid, name, path, preset}, the last empty for None.
NSArray<NSDictionary<NSString *, NSString *> *> *SGAutoEqRememberedOutputs(void);
// The output playing now plays the user's preset `name` (nil or empty for None), remembering the output when it
// is not yet; applied at once.
void SGAutoEqSetOutputPreset(NSString *name);
// The preset name stored for the output, empty for None.
NSString *SGAutoEqOutputPreset(NSString *uid);
// A user's preset was deleted: every output that had it has None instead. When the output playing now is one,
// it is left as a route change to an output without a preset would: the baseline's values come back when nothing
// was changed meanwhile, else the user's values stay, and the baseline goes.
void SGAutoEqPresetDeleted(NSString *name);

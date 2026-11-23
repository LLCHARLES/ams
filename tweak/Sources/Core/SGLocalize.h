// The words of the mod's own screens in its chosen language, or Spotify's language for System. Every string a page of the mod's shows goes
// through SGL with a key named for what it means and the English it stands for:
//
//     SGSwitchRow(SGL(@"settings.player.gestures.title", @"Gestures"), nil, SGKeyGestures)
//     [NSString stringWithFormat:SGL(@"settings.stats.songs.format", @"%ld songs"), count]
//
// Vitrine.bundle holds <language>.lproj/Localizable.strings. It is looked for in the app first, where the IPA build
// puts it (cyan copies it out of the .deb), then where a jailbreak installs it, /var/jb/Library/Application Support or
// /Library/Application Support. English, a language without a table, a missing bundle, a missing key and a translation
// whose format specifiers differ from the English all give the English passed in, so nothing a page shows depends on the
// bundle. scripts/check-strings.py keeps the tables, the keys used in Sources/ and their specifiers in step
// (docs/tweaks.md, Localization).
#import <Foundation/Foundation.h>

// 0 or absent: System; 1: English; 2: Simplified Chinese. Read once per launch.
#define SGKeyLanguage @"spotifyglass.language"

// The English is a format argument, so clang checks a stringWithFormat: against it.
NSString *SGL(NSString *key, NSString *english) NS_FORMAT_ARGUMENT(2);

// The language the mod's screens are in this launch: an .lproj of the bundle's, or "en".
NSString *SGLanguage(void);

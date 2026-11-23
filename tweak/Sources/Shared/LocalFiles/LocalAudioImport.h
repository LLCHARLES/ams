// Audio files the user imports from Retrine into the app's Documents folder, where Spotify scans its own
// Local Files once its setting for audio files on this device is on. Retrine only copies a file in; Spotify
// indexes and plays it.
//
//     LocalAudioImport.m   the copy (never over a file, a number after a name that is taken), the list of
//                          what was imported and the delete, which touches only a file on that list
//     LocalAudioPage.m     the Local files settings page, the picker and the Imported files page
//
// The list lives in Retrine's defaults. A file the user put in Documents any other way is never listed,
// deleted or renamed.
#import <Foundation/Foundation.h>

// What was imported, in the order it came: {name, device, inode, size} of each file as the copy made it. A file
// that took the name since (another regular file, a folder, a link) has another identity and is not the import.
#define SGKeyLocalAudioImported @"spotifyglass.localfiles.imported"

// LocalAudioPage.m: the Local files settings page.
@class UIViewController;
UIViewController *SGLocalFilesSettingsPage(void);

// The app's Documents folder.
NSURL *SGLocalAudioFolder(void);

// `name` for the first try, then "<name without extension> 2.<extension>", " 3"…: the nth name to try.
NSString *SGLocalAudioNumberedName(NSString *name, NSUInteger attempt);

// Copies each file into `folder` (the original stays) under its own name, numbered when that is taken, and
// lists the name it got in `store`. Each URL is opened with security-scoped access around its copy. Returns
// the names the copies got; `failed` gets the original names of the files that could not be copied. Off main.
NSArray<NSString *> *SGLocalAudioImport(NSArray<NSURL *> *urls, NSURL *folder, NSUserDefaults *store, NSArray<NSString *> **failed);

// The listed names whose file in `folder` is still the file the copy made (same device, inode and size, not
// followed through a link). Any other entry leaves the list.
NSArray<NSString *> *SGLocalAudioImportedNames(NSURL *folder, NSUserDefaults *store);

// Deletes the imported file of a listed name with a single non-recursive unlink and unlists it; a name already
// gone from `folder` is unlisted and counts as deleted. Under a name whose file is no longer the import
// (replaced since, or a folder) nothing is touched, the entry is unlisted and the answer is NO, as it is for
// a name that is not listed or an unlink that fails (the entry stays then).
BOOL SGLocalAudioDelete(NSString *name, NSURL *folder, NSUserDefaults *store);

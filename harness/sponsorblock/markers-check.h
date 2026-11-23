// SponsorBlock's progress bar marks on a host harness's mock of Spotify's progress slider
// (_TtCO17NowPlaying_ECMKit11ProgressBar6Slider): the engine's real session (SponsorBlockModel.m) plays fixture
// episodes and a song, and each check compares the drawn window against the same bar with no marks, a line each
// with `ok` or `WRONG`. Linked by harness/native-player and harness/player with Shared/SponsorBlock/SponsorBlockMarkers.m,
// SponsorBlockModel.m and SponsorBlockPrefs.m; this file answers the engine's readers the playback hooks answer in the app.
#import <UIKit/UIKit.h>

// Whether this launch has the progress bar switch off: the `sponsorblock-off` launch argument or HARNESS_SCENARIO.
BOOL SBMarksOffRun(void);

// Runs the checks on `slider`, shown in a window and laid out as the look lays it out, and writes `<look>-ltr.png`
// and `<look>-rtl.png` into `shots`. `scrub`, when the look thickens a scrubbed bar, begins (YES) or ends a drag.
// Returns the number of wrong checks; with the switch off, checks only that nothing is drawn.
NSUInteger SBMarksRun(UISlider *slider, NSString *look, void (^scrub)(BOOL dragging), NSString *shots);

#import "Shared/Player/PlayerState.h"

void SGTitleHarnessState(id uri, NSString *title, NSString *artist, BOOL paused);
void SGTitleHarnessClearState(void);
void SGTitleHarnessAnswer(NSString *track, NSString *title, NSString *artist);
void SGTitleHarnessUseTranslations(BOOL enabled);
void SGTitleHarnessSimplify(BOOL enabled);
NSUInteger SGTitleHarnessObserverCount(void);

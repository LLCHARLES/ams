#define main nowPlayingHarnessMain
#import "../now-playing/main.m"
#undef main

extern void checkUnavailableClip(void);
int main(void) { @autoreleasepool {
    sg_player = [SPTEsperantoPlayer new];
    checkUnavailableClip();
    return failures != 0;
} }

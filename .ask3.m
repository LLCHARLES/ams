#import <MetalKit/MetalKit.h>
#import <Metal/Metal.h>
// Force the issue: take the protocol as a plain struct pointer so any method is 'unknown'.
struct Dummy { int x; };
void ask(id<MTLRenderCommandEncoder> e, id<MTLTexture> t) {
    ((struct ObjCSuper *)0)->setFragmentTextureQQQ(e, t, 0);
}

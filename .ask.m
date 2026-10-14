#import <MetalKit/MetalKit.h>
#import <Metal/Metal.h>
// Ask the compiler to spell out what a render command encoder can do.
void ask(id<MTLRenderCommandEncoder> e, id t) {
    [e setFragmentTextureZZZ:t index:0];
}

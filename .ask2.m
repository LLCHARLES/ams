#import <MetalKit/MetalKit.h>
#import <Metal/Metal.h>
// Do the C-style entry points still exist?
void ask(id<MTLRenderCommandEncoder> e, id<MTLTexture> t, id<MTLSamplerState> s, const void *b) {
    [e setRenderPipelineState:(id)nil];
    [e setFragmentTexture:t offset:0 atIndex:0];
    [e setFragmentBytes:b length:0 atIndex:0];
    [e setFragmentSamplerState:s offset:0 atIndex:0];
}

#import <MetalKit/MetalKit.h>
#import <Metal/Metal.h>
void probe(id<MTLDevice> d) {
    id<MTLCommandQueue> q = [d newCommandQueue];
    id<MTLCommandBuffer> c = [q commandBuffer];
    MTLRenderPassDescriptor *rpd = [MTLRenderPassDescriptor renderPassDescriptor];
    id<MTLRenderCommandEncoder> e = [c renderCommandEncoderWithDescriptor:rpd];
    e;
}

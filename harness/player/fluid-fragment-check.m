// Ask Metal which cover textures each compiled copy pass actually reads. No pixel baseline.
#import <Metal/Metal.h>
#import "../harness-fail.h"
#include "shader.inc"

int main(void) {
    @autoreleasepool {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        NSError *error = nil;
        id<MTLLibrary> library = [device newLibraryWithSource:kShader options:nil error:&error];
        if (!library) HARNESS_FAIL(@"shader compilation: %@", error);
        for (NSString *name in @[@"copyFragment", @"fadeFragment"]) {
            MTLRenderPipelineDescriptor *d = [MTLRenderPipelineDescriptor new];
            d.vertexFunction = [library newFunctionWithName:@"copyVertex"];
            d.fragmentFunction = [library newFunctionWithName:name];
            d.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA16Float;
            MTLRenderPipelineReflection *reflection;
            if (![device newRenderPipelineStateWithDescriptor:d options:MTLPipelineOptionBindingInfo reflection:&reflection error:&error])
                HARNESS_FAIL(@"pipeline %@: %@", name, error);
            NSMutableIndexSet *textures = [NSMutableIndexSet indexSet];
            for (id<MTLBinding> binding in reflection.fragmentBindings)
                if (binding.type == MTLBindingTypeTexture && binding.used) [textures addIndex:binding.index];
            NSIndexSet *expected = [name isEqual:@"copyFragment"] ? [NSIndexSet indexSetWithIndex:1] :
                [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)];
            if (![textures isEqual:expected]) HARNESS_FAIL(@"%@ reads cover slots %@", name, textures);
        }
        puts("PASS: settled pass reads only the destination; the fade reads both covers");
    }
    return 0;
}

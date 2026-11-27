#include "../../tweak/Sources/Shared/WireGuard/SGWGLoaderPolicy.h"
#include <stdio.h>

#define CHECK(test) do { if (!(test)) { fprintf(stderr, "FAIL loader policy: %s\n", #test); return 1; } } while (0)

int main(int argc, char **argv) {
    CHECK(argc == 2);
    struct {
        struct mach_header_64 host;
        struct load_command other;
        struct dylinker_command env;
        char entry[68];
    } image = {
        .host = {.magic = MH_MAGIC_64, .filetype = MH_EXECUTE, .ncmds = 2,
                 .sizeofcmds = sizeof(image) - sizeof(image.host)},
        .other = {.cmd = LC_LOAD_DYLIB, .cmdsize = sizeof(image.other)},
        .env = {.cmd = LC_DYLD_ENVIRONMENT, .cmdsize = sizeof(image.env) + sizeof(image.entry),
                .name.offset = sizeof(image.env)},
        .entry = "DYLD_PRINT_LIBRARIES=1",
    };
    CHECK(!SGWGHostOverrides(&image.host));
    strcpy(image.entry, "DYLD_FALLBACK_LIBRARY_PATH=");
    CHECK(SGWGHostOverrides(&image.host));
    strcpy(image.entry, "DYLD_ROOT_PATH=/fixture");
    CHECK(SGWGHostOverrides(&image.host)); // never trusted when embedded
    image.env.name.offset = image.env.cmdsize;
    CHECK(SGWGHostOverrides(&image.host));
    CHECK(!SGWGProcessOverrides());
    setenv("DYLD_ROOT_PATH", "/fixture", 1);
    CHECK(SGWGProcessOverrides() == (strcmp(argv[1], "iphoneos") == 0));
    setenv("DYLD_LIBRARY_PATH", "/fixture", 1);
    CHECK(SGWGProcessOverrides());
    return 0;
}

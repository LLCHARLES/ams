TARGET := iphone:clang:latest:16.0
ARCHS := arm64
FINALPACKAGE := 1
# Logos's .x.m output is kept: an .x object depends on it, and Theos otherwise deletes it after compiling,
# so every .x file would compile again on every build.
KEEP_LOGOS_INTERMEDIATES := 1

# version.txt at the repo root is the one version, bumped by Release Please's release PR. Theos
# stamps PACKAGE_VERSION into the .deb (control has no Version line) and reads it while common.mk
# loads, so it is set above the include.
SG_VERSION := $(or $(shell cat ../version.txt 2>/dev/null),0.0.0)
# A pre-release's hyphen becomes a tilde in the .deb, so dpkg sorts 1.0.0~beta.1 before 1.0.0.
PACKAGE_VERSION := $(subst -,~,$(SG_VERSION))

include $(THEOS)/makefiles/common.mk

# The What's new sheet's text, this version's section of CHANGELOG.md, as a gitignored header that
# App/Onboarding/WhatsNew.m reads. A copy of tweak/ without the scripts beside it builds without it.
ifneq ($(wildcard ../scripts/whats-new.sh),)
$(shell ../scripts/whats-new.sh $(SG_VERSION) ../CHANGELOG.md Sources/App/Onboarding/SGWhatsNewNotes.h)
endif

TWEAK_NAME := spotifyglass

# Every source under Sources/, so a new feature needs no Makefile edit. Shared/Flags/SGFlagList.m
# is generated from the IPA by scripts/extract-flags.py.
spotifyglass_FILES := $(shell find Sources -name '*.m' -o -name '*.x' -o -name '*.swift' | sort)
spotifyglass_CFLAGS := -fobjc-arc -ISources -DSG_VERSION=\"$(SG_VERSION)\"
# The phone driver (Diagnostics/Driver.m) goes only into builds that carry FLEX: scripts/pipeline.sh sets
# SG_DRIVER=1 for those, and every other build (make release, the release workflow's .deb) leaves it out.
SG_DRIVER ?= 0
spotifyglass_CFLAGS += -DSG_DRIVER=$(SG_DRIVER)
# MetalPerformanceShaders is deliberately absent. Its headers declare blit and render selectors
# with slightly different signatures, and importing them alongside Metal/Metal.h made every
# id<MTLBlitCommandEncoder> and id<MTLRenderCommandEncoder> call read as an unknown selector.
# The visualiser uses no MPS kernel, so there is nothing to lose.
spotifyglass_FRAMEWORKS := UIKit QuartzCore UniformTypeIdentifiers MediaPlayer CoreImage AudioToolbox AVFoundation CoreHaptics Accelerate CoreMotion CoreML CoreText OSLog Metal MetalKit
# zlib unpacks KuGou's KRC lyrics (Shared/LyricsSources/KuGou.m).
spotifyglass_LIBRARIES := z
# Runtime swizzling instead of Substrate so the dylib has no extra dependency inside the IPA.
spotifyglass_LOGOS_DEFAULT_GENERATOR := internal

# The audio effects' third-party C (vendor/audio: libbs2b, WDL's EEL2) is built by its own Makefile into a
# static library with its own flags, out of this one's -Werror and with its symbols hidden, into
# vendor/audio/build/ios/, which `clean` leaves alone and later builds only update. Listed as an object file
# it is a prerequisite of the link and linked in; only the two files using it see its headers.
SG_AUDIO := ../vendor/audio
spotifyglass_OBJ_FILES := $(SG_AUDIO)/build/ios/libsgaudio.a
Sources/Shared/AudioEffects/SGDSPCrossfeed.m_CFLAGS := -isystem $(SG_AUDIO)/libbs2b
Sources/Shared/AudioEffects/SGDSPLiveprog.m_CFLAGS := -isystem $(SG_AUDIO)/wdl/eel2

# The Metal visualizer's shaders (Shared/MetalVisualiser/SGRMetalShaders.metal).
#
# Theos has no built-in .metal rule: it compiles C/ObjC/Swift and links objects, and a
# .metallib is not an object, so listing one under spotifyglass_OBJ_FILES does not build.
# So the shaders are compiled here with xcrun -metal and the resulting .metallib is fed to
# the linker with -Wl,-sectcreate,__TEXT,__metallib, which is where -newDefaultLibrary looks
# for them at runtime. Recompiled only when the source is newer than the library.
SG_METAL_SRC := $(wildcard Sources/Redesigned/MetalVisualiser/*.metal)
SG_METAL_LIB := $(SG_METAL_SRC:.metal=.metallib)
# metal is driven straight, not through xcrun's SDK lookup: xcrun parses its own options before
# the tool name and rejects anything it does not know there ("unrecognized option: -O3"), so a
# flag placed after `metal` is read by metal, while $(SDK) — the SDK *name* — is not defined in
# this scope and expanded to nothing, leaving xcrun with no tool to run. xcrun -sdk iphoneos with
# the tool named first is the form that works:
#   xcrun -sdk iphoneos metal -O3 -o out.metallib in.metal
SG_METALLIB_SDK := iphoneos
SG_METALLIB_FLAGS := -O3

$(SG_METAL_LIB): %.metallib: %.metal
	@echo "METALC $@"
	@xcrun -sdk $(SG_METALLIB_SDK) metal $(SG_METALLIB_FLAGS) -o $@ $<
	@test -s $@ || { echo "METALC produced nothing: $@"; exit 1; }

# The pattern rule above is not enough on its own: make only runs a rule when something
# asks for its target, and nothing in Theos's graph asks for the .metallib — LDFLAGS is a
# string, not a dependency. So the linker was handed a path to a file nothing had built:
#   ld: file cannot be open()ed, errno=2 path=Sources/.../SGRMetalShaders.metallib
#
# internal-library-all_ is the target Theos's link rule hangs the dylib off (library.mk:
# "internal-library-all_:: .../spotifyglass.dylib"), so listing the library here puts it
# directly into the link's own prerequisite chain — make finishes it before ld runs.
#
# Double-colon, not single: Theos declares these targets too, and a single-colon rule would
# make the target two different things at once:
#   target file 'before-spotifyglass-all' has both : and :: entries. Stop.
# A double-colon rule adds the prerequisite without redefining the target's recipe.
internal-library-all_:: $(SG_METAL_LIB)
	@echo "SECTCREATE input: $(SG_METAL_LIB)"

# 改shader 后要重新编,靠 .metal/.metallib 的时间戳即可,不需要在解析时删产物 ——
# $(shell rm) 会在 make 还没决定是否重建时就把库删掉,而这一行的求值时机早于目标判断,
# 于是增量构建也会每次重编,并且刚编好的库在同一次make 里可能又被删。
#
# .metallib 必须只走 -sectcreate,不能进 spotifyglass_OBJ_FILES:OBJ_FILES 里的东西被当作
# 目标文件直接交给 ld,而 ld 不认识 metallib 这个类型 ——
#   ld: unknown file type in 'SGRMetalShaders.metallib'
# -sectcreate 才是把任意文件塞进 Mach-O 某个 section 的正确方式,而 __TEXT,__metallib
# 正是 -newLibraryWithURL: 在 dylib 里找 shader 的位置。
#
# 路径取绝对值:ld 在链接阶段的工作目录不是 tweak/,相对路径在那里解析不到
#   ("path=Sources/Redesigned/MetalVisualiser/SGRMetalShaders.metallib").
SG_METAL_LIB_ABS := $(abspath $(SG_METAL_LIB))
spotifyglass_LDFLAGS += -Wl,-sectcreate,__TEXT,__metallib,$(SG_METAL_LIB_ABS)

include $(THEOS_MAKE_PATH)/tweak.mk

# The library is brought up to date before the tweak's instance builds, so the link finds it current.
spotifyglass.all.tweak.variables: sg-audio
.PHONY: sg-audio
sg-audio:
	@$(MAKE) --no-print-directory -C $(SG_AUDIO) PLATFORM=ios

# The layers of Sources/ stay apart (scripts/check-layers.sh): an import across them fails the build.
# A copy of tweak/ made without the scripts beside it builds unchecked.
before-all::
	@if [ -x ../scripts/check-layers.sh ]; then ../scripts/check-layers.sh Sources; fi

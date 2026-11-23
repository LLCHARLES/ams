# Entry points; the real work is in scripts/. IPA defaults to the release base, Spotify 9.2.0, when it is in
# ipa/, and otherwise to the first file there.
IPA ?= $(firstword $(wildcard ipa/Spotify-9.2.0.ipa) $(wildcard ipa/*.ipa))

# What goes on the phone is the mod alone. FLEX is the inspector `make trees` reads the screens
# through, so it rides along only when it is asked for: make install FLEX=1. (A make target cannot
# take --flex; make would read that as an option of its own.)
FLEX ?= 0
FLEX_ARG := $(if $(filter 0,$(FLEX)),--no-flex,)
WIREGUARD ?= 1
export WIREGUARD
PIXIE ?= 1
export PIXIE
ifeq ($(PIXIE),1)
# Explicit IPA= and environment inputs still win over the Pixie primary target.
ifeq ($(origin IPA),file)
IPA := $(or $(wildcard $(shell python3 -B NativeDownloads/tools/pixie_target.py --primary-ipa)),$(IPA))
endif
endif
PIXIE_ARG := $(if $(filter 1,$(PIXIE)),--pixie,--no-pixie)
NO_PLUGINS ?= 0
NO_PLUGINS_ARG := $(if $(filter 1,$(NO_PLUGINS)),--no-plugins,)

# A local install is renamed and re-iconed so it is told apart from the released app on the home
# screen.
DEV_NAME ?= spoti.dev
DEV_ICON ?= docs/icon.png

.PHONY: build release install quick trees session log flags
build:    ## FLEX + glass IPA into out/
	./scripts/pipeline.sh $(IPA) $(PIXIE_ARG) $(NO_PLUGINS_ARG)
release:  ## Pixie IPA by default (PIXIE=0 to exclude), no FLEX
	./scripts/pipeline.sh $(IPA) --no-flex $(PIXIE_ARG) $(NO_PLUGINS_ARG)
install:  ## build, sign with your certificate, push to the phone on USB (FLEX=1 to take FLEX too)
	./scripts/pipeline.sh $(IPA) --install $(FLEX_ARG) $(PIXIE_ARG) $(NO_PLUGINS_ARG) --name "$(DEV_NAME)" --icon "$(DEV_ICON)" -o out/spoti.dev.ipa
quick:    ## a tweak-only change into the app the last build made: rebuild, sign, install in seconds
	./scripts/quick.sh
trees:    ## record per-screen view trees into trees/ (needs a FLEX build on the phone)
	./scripts/record-trees.py
session:  ## record clean trees screen by screen into trees/clean/, Enter per snapshot, n for the next screen (SCREENS="playlist artist" for some)
	./scripts/record-session.py $(SCREENS)
log:     ## stream the tweak's log lines from the phone
	./scripts/dump-log.sh
flags:    ## regenerate tweak/Sources/Shared/Flags/SGFlagList.m, Spotify's remote-config flags, from the IPA
	./scripts/extract-flags.py $(IPA)

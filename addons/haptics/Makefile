# Vitrine Addon: the SpringBoard side of Music Haptics > Everywhere (HapticRelay.x) and, below iOS 26, of the lock
# screen's full-screen cover (LockCover.x), a rootless package of its own.
# Build from here: env -u MAKELEVEL gmake package. Vitrine's own tweak/ does not build or carry it.
TARGET := iphone:clang:latest:16.0
ARCHS := arm64 arm64e
FINALPACKAGE := 1
THEOS_PACKAGE_SCHEME ?= rootless
PACKAGE_VERSION := $(or $(shell cat ../../version.txt 2>/dev/null | tr - '~'),0.0.0)

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := VitrineAddon
VitrineAddon_FILES := HapticRelay.x LockCover.x MediaRemoteUICanvas.x LockClipView.m
VitrineAddon_CFLAGS := -fobjc-arc
VitrineAddon_FRAMEWORKS := UIKit CoreHaptics AVFoundation CoreMedia
VitrineAddon_LOGOS_DEFAULT_GENERATOR := internal

include $(THEOS_MAKE_PATH)/tweak.mk

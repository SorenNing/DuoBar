ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:15.1
THEOS_PACKAGE_SCHEME ?= roothide
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DuoBar
DuoBar_FILES = $(wildcard Tweak/Classes/*.m) \
    $(wildcard Tweak/Hooks/*.m) \
    Tweak/Support/IDICompat.m Tweak/Support/IDIConstructor.m
DuoBar_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable \
    -Wno-unused-function -ITweak/Headers -ITweak/Support -ITweak/Hooks
DuoBar_FRAMEWORKS = UIKit Foundation QuartzCore CoreGraphics CoreFoundation
DuoBar_LIBRARIES = substrate
DuoBar_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries

SUBPROJECTS += Preferences
include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk

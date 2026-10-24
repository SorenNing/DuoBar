ARCHS = arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME ?= roothide

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DuoBarNCGate
DuoBarNCGate_FILES = Sources/Gate.xm
DuoBarNCGate_CFLAGS = -fobjc-arc -Wall
DuoBarNCGate_FRAMEWORKS = UIKit Foundation CoreFoundation QuartzCore
DuoBarNCGate_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk

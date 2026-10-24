include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = DuoBarPrefs
DuoBarPrefs_FILES = $(wildcard *.m)
DuoBarPrefs_CFLAGS = -fobjc-arc -Wno-deprecated-declarations \
    -IHeaders -I../Tweak/Headers -I../Tweak/Support -I.
DuoBarPrefs_FRAMEWORKS = UIKit Foundation
DuoBarPrefs_PRIVATE_FRAMEWORKS = Preferences
DuoBarPrefs_INSTALL_PATH = /Library/PreferenceBundles
DuoBarPrefs_RESOURCE_FILES = Resources/Root.plist Resources/icon.png Resources/icon@2x.png Resources/icon@3x.png

include $(THEOS_MAKE_PATH)/bundle.mk

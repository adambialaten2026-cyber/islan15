include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = DynamicIslandPrefs
DynamicIslandPrefs_FILES = DIRootListController.m
DynamicIslandPrefs_INSTALL_PATH = /Library/PreferenceBundles
DynamicIslandPrefs_FRAMEWORKS = UIKit
DynamicIslandPrefs_PRIVATE_FRAMEWORKS = Preferences

include $(THEOS_MAKE_PATH)/bundle.mk

after-install::
	install.exec "killall -9 Preferences" || true

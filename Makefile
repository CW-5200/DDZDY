ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = WeChat

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DDGPS

DDGPS_FILES = Tweak.xm
DDGPS_CFLAGS = -fobjc-arc
DDGPS_FRAMEWORKS = UIKit CoreLocation MapKit

include $(THEOS_MAKE_PATH)/tweak.mk

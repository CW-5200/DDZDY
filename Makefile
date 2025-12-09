ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = WeChat

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DDAssistant

DDAssistant_FILES = Tweak.xm
DDAssistant_CFLAGS = -fobjc-arc
DDAssistant_FRAMEWORKS = UIKit CoreLocation MapKit

include $(THEOS_MAKE_PATH)/tweak.mk

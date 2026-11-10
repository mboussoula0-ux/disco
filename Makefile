# Optional Theos build (the GitHub workflow uses plain clang and does not need Theos).
ARCHS = arm64
TARGET = iphone:clang:latest:16.0
INSTALL_TARGET_PROCESSES = Discord

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = 8ubahDiscord
8ubahDiscord_FILES = Tweak.m
8ubahDiscord_CFLAGS = -fobjc-arc -w
8ubahDiscord_FRAMEWORKS = UIKit Foundation AVFoundation PhotosUI ImageIO AudioToolbox CoreMedia UniformTypeIdentifiers QuartzCore CoreGraphics
8ubahDiscord_INSTALL_PATH = @executable_path/Frameworks

include $(THEOS_MAKE_PATH)/library.mk

# 递归展开，保证 make test 在未安装 Xcode 时也能执行，不会提前调用 xcrun
SDK = $(shell xcrun --sdk iphoneos --show-sdk-path)
CLANG = $(shell xcrun --sdk iphoneos --find clang)
LIPO = $(shell xcrun --sdk iphoneos --find lipo)
VERSION := v3.6.0
TARGET := build/AntManorPort-$(VERSION).dylib
SOURCES := PortEntry.m antforest/AntManorManager.m antforest/AntManorIntimacy.m antforest/AntManorCapture.m
HEADERS := $(wildcard antforest/*.h) $(wildcard antforest/Headers/PSDJsBridge/*.h)

INCLUDES := -Iantforest -Iantforest/Headers/PSDJsBridge -Iantforest/Headers/PSDJsBridge/Protocol
FRAMEWORKS := -framework Foundation -framework UIKit -framework QuartzCore -framework CoreGraphics -framework WebKit

.PHONY: all clean test package

all: $(TARGET)

test:
	sh tests/check_manor_only_paths.sh

$(TARGET): $(SOURCES) $(HEADERS) Makefile
	@mkdir -p build
	$(CLANG) -target arm64-apple-ios14.0 -isysroot $(SDK) -fobjc-arc -dynamiclib $(SOURCES) $(INCLUDES) $(FRAMEWORKS) -o build/AntManorPort-arm64-ios14.dylib
	$(CLANG) -target arm64e-apple-ios14.0 -isysroot $(SDK) -fobjc-arc -dynamiclib $(SOURCES) $(INCLUDES) $(FRAMEWORKS) -o build/AntManorPort-arm64e-ios14.dylib
	$(LIPO) -create build/AntManorPort-arm64-ios14.dylib build/AntManorPort-arm64e-ios14.dylib -output $@
	rm -f build/AntManorPort-arm64-ios14.dylib build/AntManorPort-arm64e-ios14.dylib

package: $(TARGET)
	sh scripts/package.sh "$(VERSION)"

clean:
	rm -rf build

# SwiftUI macros need full Xcode; Command Line Tools lack the plugin.
export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
SWIFTC = xcrun swiftc
SOURCES = main.swift Bridge.swift USB.swift Gamepad.swift VirtualGamepad.swift
APP = build/King of Drivers 2026.app
# Ad-hoc by default. To use a certificate, pass SIGN=<SHA-1 from `security find-identity -v -p codesigning`>.
SIGN ?= -

.PHONY: all app check clean
all: app

build/usblib.o: usblib.c usblib.h Makefile
	mkdir -p build
	xcrun clang -target arm64-apple-macos26.0 -std=c11 -Wall -Wextra -Werror -O2 -c usblib.c -o $@

build/KingOfDrivers: $(SOURCES) usblib.h build/usblib.o Makefile
	$(SWIFTC) -target arm64-apple-macos26.0 -swift-version 6 -warnings-as-errors -O -parse-as-library \
		-import-objc-header usblib.h $(SOURCES) build/usblib.o -o $@

app: build/KingOfDrivers Info.plist KingOfDrivers.entitlements
	mkdir -p "$(APP)/Contents/MacOS"
	cp Info.plist "$(APP)/Contents/Info.plist"
	cp build/KingOfDrivers "$(APP)/Contents/MacOS/KingOfDrivers"
	codesign --force --options runtime --sign "$(SIGN)" --entitlements KingOfDrivers.entitlements "$(APP)"

check: build/KingOfDrivers
	./build/KingOfDrivers self-test

clean:
	rm -rf build

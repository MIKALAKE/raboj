# Build, sign (ad hoc), verify and package Răboj with only the Xcode Command Line Tools.
# No Apple Developer account needed.

APP_NAME    := Raboj
BUILD_DIR   := build
APP         := $(BUILD_DIR)/$(APP_NAME).app
CONFIG      ?= release
APPDIR      ?= $(HOME)/Applications
VERSION     := $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
DMG         := $(BUILD_DIR)/$(APP_NAME)-$(VERSION).dmg

.PHONY: all build test app verify run install uninstall dmg clean

all: app

build:
	swift build -c $(CONFIG)

test:
	swift test

# Assemble a real .app bundle around the SwiftPM executable and sign it ad hoc with our entitlements.
app: build
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp "$$(swift build -c $(CONFIG) --show-bin-path)/$(APP_NAME)" "$(APP)/Contents/MacOS/$(APP_NAME)"
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	codesign --force --sign - --options runtime \
		--entitlements Resources/Raboj.entitlements "$(APP)"
	@echo "Built $(APP)"

# Print the permissions the built app really has, and fail if they grew beyond the documented set.
verify: app
	codesign --verify --strict "$(APP)"
	@codesign -d --entitlements - --xml "$(APP)" 2>/dev/null | plutil -convert xml1 -o - - | tee $(BUILD_DIR)/entitlements.plist
	@grep -q 'com.apple.security.app-sandbox' $(BUILD_DIR)/entitlements.plist || { echo "FAIL: sandbox missing"; exit 1; }
	@! grep -q 'com.apple.security.network.server' $(BUILD_DIR)/entitlements.plist || { echo "FAIL: incoming connections allowed"; exit 1; }
	@! grep -q 'read-write' $(BUILD_DIR)/entitlements.plist || { echo "FAIL: write access to user files requested"; exit 1; }
	@echo "OK: sandboxed, outgoing connections only, read-only file access"

run: app
	open "$(APP)"

install: app
	mkdir -p "$(APPDIR)"
	rm -rf "$(APPDIR)/$(APP_NAME).app"
	cp -R "$(APP)" "$(APPDIR)/"
	@echo "Installed to $(APPDIR)/$(APP_NAME).app"

uninstall:
	rm -rf "$(APPDIR)/$(APP_NAME).app"

dmg: verify
	rm -f "$(DMG)"
	rm -rf "$(BUILD_DIR)/dmg" && mkdir -p "$(BUILD_DIR)/dmg"
	cp -R "$(APP)" "$(BUILD_DIR)/dmg/"
	ln -s /Applications "$(BUILD_DIR)/dmg/Applications"
	hdiutil create -volname "Răboj $(VERSION)" -srcfolder "$(BUILD_DIR)/dmg" -ov -format UDZO "$(DMG)"
	shasum -a 256 "$(DMG)" | tee "$(DMG).sha256"

clean:
	rm -rf $(BUILD_DIR) .build

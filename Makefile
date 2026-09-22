# Pastiche — build, bundle and run without Xcode's GUI.

APP_NAME    := Pastiche
BUNDLE_NAME := Pastiche
BUNDLE_ID   := io.github.bcollard.Pastiche
VERSION     ?= 1.0.0
BUILD       ?= $(shell git rev-list --count HEAD 2>/dev/null || echo 1)
CONFIG      := release

# Sign with a Developer ID certificate when the keychain has one, falling back
# to an ad-hoc signature.
#
# This matters for more than distribution. An ad-hoc signature pins the app's
# designated requirement to its cdhash, which changes on every single build, so
# macOS treats each rebuild as a different app and silently drops the
# Accessibility grant. A Developer ID signature keys on the team identifier
# instead, and the grant survives.
#
# Override with:  make app SIGN_IDENTITY="Developer ID Application: ..."
SIGN_IDENTITY ?= $(shell security find-identity -p codesigning -v 2>/dev/null \
                   | grep "Developer ID Application" | head -1 \
                   | sed -E 's/.*"(.*)"/\1/')
ifeq ($(strip $(SIGN_IDENTITY)),)
SIGN_IDENTITY := -
endif

# UNIVERSAL=1 builds arm64 + x86_64 in one binary (releases do this). By default
# `make` builds only for the Mac it runs on, which is faster for development.
UNIVERSAL   ?= 0
ifeq ($(UNIVERSAL),1)
SWIFT_ARCHS := --arch arm64 --arch x86_64
BUILD_DIR   := .build/apple/Products/Release
else
SWIFT_ARCHS :=
BUILD_DIR   := .build/$(CONFIG)
endif
DIST_DIR    := dist
APP_BUNDLE  := $(DIST_DIR)/$(BUNDLE_NAME).app
CONTENTS    := $(APP_BUNDLE)/Contents
MACOS_DIR   := $(CONTENTS)/MacOS
RES_DIR     := $(CONTENTS)/Resources
ICONSET     := $(DIST_DIR)/AppIcon.iconset

.PHONY: all build app icon run install uninstall clean relaunch requirement notarize package release appstore

all: app

## Compile the executable only.
build:
	swift build -c $(CONFIG) $(SWIFT_ARCHS)

## Render AppIcon.icns from Tools/make_icon.swift.
icon: $(DIST_DIR)/AppIcon.icns

$(DIST_DIR)/AppIcon.icns: Tools/make_icon.swift
	@mkdir -p $(DIST_DIR)
	@rm -rf $(ICONSET)
	swift Tools/make_icon.swift $(ICONSET)
	iconutil -c icns -o $@ $(ICONSET)
	@rm -rf $(ICONSET)

## Assemble a runnable .app bundle in dist/.
app: build $(DIST_DIR)/AppIcon.icns
	@rm -rf "$(APP_BUNDLE)"
	@mkdir -p "$(MACOS_DIR)" "$(RES_DIR)"
	cp "$(BUILD_DIR)/$(APP_NAME)" "$(MACOS_DIR)/$(APP_NAME)"
	cp "$(DIST_DIR)/AppIcon.icns" "$(RES_DIR)/AppIcon.icns"
	sed -e 's/__VERSION__/$(VERSION)/' -e 's/__BUILD__/$(BUILD)/' \
		Resources/Info.plist > "$(CONTENTS)/Info.plist"
	codesign --force --timestamp=none --sign "$(SIGN_IDENTITY)" \
		--identifier $(BUNDLE_ID) \
		--entitlements Resources/$(APP_NAME).entitlements \
		--options runtime \
		"$(APP_BUNDLE)"
	@echo "Built $(APP_BUNDLE)"
	@if [ "$(SIGN_IDENTITY)" = "-" ]; then \
		echo ""; \
		echo "  NOTE: signed ad-hoc (no Developer ID certificate found)."; \
		echo "  macOS will drop the Accessibility grant on every rebuild."; \
	else \
		echo "  Signed with: $(SIGN_IDENTITY)"; \
	fi

## Print what macOS will match this app against for TCC/Gatekeeper purposes.
requirement: app
	@codesign -d -r- "$(APP_BUNDLE)" 2>&1 | sed 's/^/  /'

## Notarize for distribution outside the App Store. Needs a stored keychain
## profile:  xcrun notarytool store-credentials NOTARY --apple-id <id> \
##             --team-id <team> --password <app-specific-password>
NOTARY_PROFILE ?= NOTARY
# CI has no keychain profile; it passes --apple-id, --team-id and --password.
NOTARY_ARGS    ?= --keychain-profile "$(NOTARY_PROFILE)"
notarize: app
	@test "$(SIGN_IDENTITY)" != "-" || { echo "notarization needs a Developer ID certificate"; exit 1; }
	# `make app` signs with --timestamp=none so local builds work offline, but
	# the notary service rejects anything without a secure timestamp.
	codesign --force --timestamp --sign "$(SIGN_IDENTITY)" \
		--identifier $(BUNDLE_ID) \
		--entitlements Resources/$(APP_NAME).entitlements \
		--options runtime \
		"$(APP_BUNDLE)"
	ditto -c -k --keepParent "$(APP_BUNDLE)" "$(DIST_DIR)/$(APP_NAME).zip"
	xcrun notarytool submit "$(DIST_DIR)/$(APP_NAME).zip" $(NOTARY_ARGS) --wait
	xcrun stapler staple "$(APP_BUNDLE)"
	@echo "Notarized and stapled $(APP_BUNDLE)"

## The file Homebrew and the GitHub release ship: the built app, zipped the way
## macOS expects (ditto keeps signatures and extended attributes intact), plus a
## checksum. Run after `notarize` so the stapled app is what gets zipped.
RELEASE_ZIP := $(DIST_DIR)/$(BUNDLE_NAME)-$(VERSION).zip
package:
	@test -d "$(APP_BUNDLE)" || { echo "no $(APP_BUNDLE): run make app (or make release) first"; exit 1; }
	rm -f "$(RELEASE_ZIP)" "$(RELEASE_ZIP).sha256"
	ditto -c -k --keepParent "$(APP_BUNDLE)" "$(RELEASE_ZIP)"
	cd "$(DIST_DIR)" && shasum -a 256 "$(notdir $(RELEASE_ZIP))" > "$(notdir $(RELEASE_ZIP)).sha256"
	@echo "Packaged $(RELEASE_ZIP)"; cat "$(RELEASE_ZIP).sha256"

## Everything a release needs: universal, signed, notarized, stapled, zipped.
##   make release VERSION=1.2.3
release:
	$(MAKE) UNIVERSAL=1 notarize
	$(MAKE) package

## Mac App Store: a sandboxed build signed with the store certificates and
## packaged as a signed .pkg, ready for Transporter.
##
##   make appstore PROFILE=~/Downloads/Pastiche.provisionprofile
##
## Needs, in the keychain: an "Apple Distribution" certificate and a "Mac
## Installer Distribution" (older name: "3rd Party Mac Developer Installer")
## certificate. Needs from the developer portal: an App ID for BUNDLE_ID and a
## Mac App Store provisioning profile for it. README, "Distribution", has the
## walkthrough. Output goes to dist/appstore/, apart from the Developer ID build.
STORE_APP_IDENTITY ?= $(shell security find-identity -p codesigning -v 2>/dev/null \
                        | grep -E "Apple Distribution|3rd Party Mac Developer Application" \
                        | head -1 | sed -E 's/.*"(.*)"/\1/')
STORE_PKG_IDENTITY ?= $(shell security find-identity -p basic -v 2>/dev/null \
                        | grep -E "Mac Installer Distribution|3rd Party Mac Developer Installer" \
                        | head -1 | sed -E 's/.*"(.*)"/\1/')
# The team ID is the parenthesised suffix of the certificate's common name.
STORE_TEAM_ID  = $(shell echo "$(STORE_APP_IDENTITY)" | sed -E 's/.*\(([A-Z0-9]+)\)$$/\1/')
STORE_DIR      := $(DIST_DIR)/appstore
STORE_APP      := $(STORE_DIR)/$(BUNDLE_NAME).app
STORE_PKG      := $(STORE_DIR)/$(APP_NAME).pkg
PROFILE        ?=
# zsh does not expand ~ in `PROFILE=~/x` given as an argument, so do it here.
PROFILE_FILE   = $(patsubst ~/%,$(HOME)/%,$(PROFILE))

appstore: build $(DIST_DIR)/AppIcon.icns
	@test -n "$(STORE_APP_IDENTITY)" || { echo "No Apple Distribution certificate found in the keychain. See README, Distribution."; exit 1; }
	@test -n "$(STORE_PKG_IDENTITY)" || { echo "No Mac Installer Distribution certificate found in the keychain. See README, Distribution."; exit 1; }
	@test -f "$(PROFILE_FILE)" || { echo "PROFILE=<path to a Mac App Store .provisionprofile> is required. See README, Distribution."; exit 1; }
	@rm -rf "$(STORE_DIR)"
	@mkdir -p "$(STORE_APP)/Contents/MacOS" "$(STORE_APP)/Contents/Resources"
	cp "$(BUILD_DIR)/$(APP_NAME)" "$(STORE_APP)/Contents/MacOS/$(APP_NAME)"
	cp "$(DIST_DIR)/AppIcon.icns" "$(STORE_APP)/Contents/Resources/AppIcon.icns"
	sed -e 's/__VERSION__/$(VERSION)/' -e 's/__BUILD__/$(BUILD)/' \
		Resources/Info.plist > "$(STORE_APP)/Contents/Info.plist"
	cp "$(PROFILE_FILE)" "$(STORE_APP)/Contents/embedded.provisionprofile"
	# A downloaded profile carries quarantine and download-origin attributes, and
	# macOS adds provenance ones. None belong in a store package; they would ship
	# as AppleDouble (._*) entries.
	/usr/bin/xattr -cr "$(STORE_APP)"
	sed -e 's/__TEAM_ID__/$(STORE_TEAM_ID)/g' -e 's/__BUNDLE_ID__/$(BUNDLE_ID)/g' \
		Resources/$(APP_NAME).appstore.entitlements.in > "$(STORE_DIR)/entitlements.plist"
	codesign --force --timestamp --sign "$(STORE_APP_IDENTITY)" \
		--identifier $(BUNDLE_ID) \
		--entitlements "$(STORE_DIR)/entitlements.plist" \
		"$(STORE_APP)"
	COPYFILE_DISABLE=1 productbuild --component "$(STORE_APP)" /Applications \
		--sign "$(STORE_PKG_IDENTITY)" "$(STORE_PKG)"
	@echo "Built $(STORE_PKG)"
	@echo "  App signed with: $(STORE_APP_IDENTITY)"
	@echo "  Pkg signed with: $(STORE_PKG_IDENTITY)"
	@echo "  Upload with Transporter, or: xcrun altool --validate-app -f \"$(STORE_PKG)\" -t macos"

## Build and launch, replacing any running copy.
run: relaunch

relaunch: app
	@pkill -f "$(BUNDLE_NAME).app" 2>/dev/null || true
	open "$(APP_BUNDLE)"

## Copy into /Applications.
install: app
	@rm -rf "/Applications/$(BUNDLE_NAME).app"
	cp -R "$(APP_BUNDLE)" "/Applications/$(BUNDLE_NAME).app"
	@echo "Installed to /Applications/$(BUNDLE_NAME).app"

uninstall:
	@pkill -f "$(BUNDLE_NAME).app" 2>/dev/null || true
	rm -rf "/Applications/$(BUNDLE_NAME).app"

clean:
	rm -rf .build $(DIST_DIR)

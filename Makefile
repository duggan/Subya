# Subya — build, bundle, sign, and notarize a Developer-ID macOS app that
# burns easy-to-read captions into videos. Needs only the Swift toolchain that
# ships with Xcode 26 (plus an Apple ID for `make release`). GPL-3.0.

APP_NAME := Subya
APP_ID   := ie.duggan.Subya
TEAM_ID  := PSPQTHW392

# Override if your identity string differs:
#   make sign SIGN_ID="Developer ID Application: Your Name (TEAMID)"
SIGN_ID ?= Developer ID Application: Ross Duggan (PSPQTHW392)

BUILD_CONFIG ?= release
ARCHFLAGS    ?= --arch arm64 --arch x86_64
APP_BUNDLE   := build/$(APP_NAME).app
CONTENTS     := $(APP_BUNDLE)/Contents
# The `subya` command-line tool ships inside the app. Not in Contents/MacOS: on a
# case-insensitive disk `subya` and the app's `Subya` would be the same file.
CLI          := $(CONTENTS)/Helpers/subya
DMG          := build/$(APP_NAME).dmg
ZIP          := build/$(APP_NAME)-notarize.zip

# Artwork. Each is optional: the build still works while any of them is missing.
APP_ICON       := Resources/$(APP_NAME).icns
DMG_BACKGROUND := Resources/dmg-background.tiff

# `xcrun notarytool store-credentials` keychain profile (see `make notary-setup`).
NOTARY_PROFILE ?= subya

# Styled "drag to Applications" DMG layout (built with create-dmg). The
# background is left out until Resources/dmg-background.png exists.
DMG_STAGE := build/dmg-src
DMG_OPTS  := --volname "$(APP_NAME)" \
             $(if $(wildcard $(DMG_BACKGROUND)),--background "$(DMG_BACKGROUND)") \
             --window-pos 200 120 --window-size 660 420 --icon-size 120 \
             --icon "$(APP_NAME).app" 175 215 --hide-extension "$(APP_NAME).app" \
             --app-drop-link 485 215 --no-internet-enable

.PHONY: all build bundle sign run test icons dmg release notary-setup clean help

all: sign ## Build, bundle, and sign (default)

build: ## Compile the universal (arm64+x86_64) binaries with SwiftPM
	swift build -c $(BUILD_CONFIG) $(ARCHFLAGS)

bundle: build ## Assemble the .app bundle from the built binaries (app + CLI)
	@set -e; \
	BIN="$$(swift build -c $(BUILD_CONFIG) $(ARCHFLAGS) --show-bin-path)"; \
	echo "Using bin path: $$BIN"; \
	rm -rf "$(APP_BUNDLE)"; \
	mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Helpers" "$(CONTENTS)/Resources"; \
	cp "$$BIN/$(APP_NAME)App" "$(CONTENTS)/MacOS/$(APP_NAME)"; \
	cp "$$BIN/subya" "$(CLI)"; \
	cp Resources/App-Info.plist "$(CONTENTS)/Info.plist"; \
	if [ -f "$(APP_ICON)" ]; then cp "$(APP_ICON)" "$(CONTENTS)/Resources/"; \
	else echo "note: $(APP_ICON) not found; bundling without an app icon"; fi; \
	echo "Assembled $(APP_BUNDLE)"

sign: bundle ## Code-sign the CLI, then the app, with Hardened Runtime and verify
	codesign --force --options runtime --timestamp \
	  --sign "$(SIGN_ID)" --identifier "$(APP_ID).cli" "$(CLI)"
	codesign --force --options runtime --timestamp \
	  --sign "$(SIGN_ID)" --entitlements Resources/App.entitlements \
	  --identifier "$(APP_ID)" "$(APP_BUNDLE)"
	codesign --verify --strict --verbose=2 "$(APP_BUNDLE)"
	@echo "Signed & verified $(APP_BUNDLE)"

run: sign ## Sign then launch the app
	open "$(APP_BUNDLE)"

test: ## Run the CaptionKit unit tests
	swift test

icons: ## Regenerate artwork from Resources/art/make_icons.py (needs Inkscape)
	@set -e; command -v inkscape >/dev/null || { echo "Inkscape is required: brew install --cask inkscape" >&2; exit 1; }; \
	ART=Resources/art; TMP="$$(mktemp -d)"; \
	python3 "$$ART/make_icons.py" >/dev/null; \
	mkdir -p "$$TMP/$(APP_NAME).iconset"; \
	for size in 16 32 128 256 512; do \
	  inkscape "$$ART/AppIcon.svg" -o "$$TMP/$(APP_NAME).iconset/icon_$${size}x$${size}.png" -w $$size -h $$size 2>/dev/null; \
	  inkscape "$$ART/AppIcon.svg" -o "$$TMP/$(APP_NAME).iconset/icon_$${size}x$${size}@2x.png" -w $$((size*2)) -h $$((size*2)) 2>/dev/null; \
	done; \
	iconutil -c icns "$$TMP/$(APP_NAME).iconset" -o "$(APP_ICON)"; \
	inkscape "$$ART/DMGBackground.svg" -o "$$TMP/bg.png" -w 660 -h 420 2>/dev/null; \
	inkscape "$$ART/DMGBackground.svg" -o "$$TMP/bg@2x.png" -w 1320 -h 840 2>/dev/null; \
	sips -s dpiWidth 72 -s dpiHeight 72 "$$TMP/bg.png" >/dev/null; \
	sips -s dpiWidth 144 -s dpiHeight 144 "$$TMP/bg@2x.png" >/dev/null; \
	tiffutil -cathidpicheck "$$TMP/bg.png" "$$TMP/bg@2x.png" -out "$(DMG_BACKGROUND)" 2>/dev/null; \
	rm -rf "$$TMP"; \
	echo "Wrote $(APP_ICON) and $(DMG_BACKGROUND)"

dmg: sign ## Build a signed (not-yet-notarized) styled DMG for local testing
	@command -v create-dmg >/dev/null || { echo "create-dmg not found: brew install create-dmg" >&2; exit 1; }
	rm -f "$(DMG)"
	rm -rf "$(DMG_STAGE)" && mkdir -p "$(DMG_STAGE)"
	ditto "$(APP_BUNDLE)" "$(DMG_STAGE)/$(APP_NAME).app"
	create-dmg $(DMG_OPTS) "$(DMG)" "$(DMG_STAGE)" || true
	@test -f "$(DMG)" || { echo "create-dmg did not produce $(DMG)" >&2; exit 1; }
	codesign --force --timestamp --sign "$(SIGN_ID)" "$(DMG)"
	@echo "Built styled $(DMG) (signed only; run 'make release' to notarize)"

release: sign ## Full notarized release: staple the .app, then build+notarize the DMG
	@command -v create-dmg >/dev/null || { echo "create-dmg not found: brew install create-dmg" >&2; exit 1; }
	# 1. Notarize + staple the app, so it's valid offline once copied out of the DMG.
	ditto -c -k --keepParent "$(APP_BUNDLE)" "$(ZIP)"
	xcrun notarytool submit "$(ZIP)" --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple "$(APP_BUNDLE)"
	rm -f "$(ZIP)"
	# 2. Build the styled DMG from the stapled app, then notarize + staple it.
	rm -f "$(DMG)"
	rm -rf "$(DMG_STAGE)" && mkdir -p "$(DMG_STAGE)"
	ditto "$(APP_BUNDLE)" "$(DMG_STAGE)/$(APP_NAME).app"
	create-dmg $(DMG_OPTS) "$(DMG)" "$(DMG_STAGE)" || true
	@test -f "$(DMG)" || { echo "create-dmg did not produce $(DMG)" >&2; exit 1; }
	codesign --force --timestamp --sign "$(SIGN_ID)" "$(DMG)"
	xcrun notarytool submit "$(DMG)" --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple "$(DMG)"
	xcrun stapler validate "$(DMG)"
	@echo "Release ready (notarized + stapled): $(DMG)"

notary-setup: ## One-time: store an Apple ID app-specific password for notarytool
	@echo "Create an app-specific password at https://appleid.apple.com, then run once:"
	@echo ""
	@echo "  xcrun notarytool store-credentials $(NOTARY_PROFILE) \\"
	@echo "      --apple-id <your-apple-id> --team-id $(TEAM_ID) --password <app-specific-password>"
	@echo ""
	@echo "Afterwards, 'make release' notarizes without prompting."

clean: ## Remove build artifacts
	rm -rf .build build

help: ## List targets
	@grep -E '^[a-z][a-z-]*:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  %-13s %s\n", $$1, $$2}'

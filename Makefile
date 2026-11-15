-include local.mk

export DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer
RONEOGRAPH_DEVELOPMENT_TEAM ?=
RONEOGRAPH_BUNDLE_ID ?= org.roneograph.app
IPHONE ?=
PROJECT := Roneograph.xcodeproj
DEVICE_BUILD := build/device
APP_BUILD := build/app
SCANS_DIR ?= build/scans
TESTFLIGHT_BUILD := build/testflight
ICON_PREVIEW := build/app-icon
SAMPLE_PHOTOS ?= tools/sample-photos
ICTOOL := $(DEVELOPER_DIR)/../Applications/Icon Composer.app/Contents/Executables/ictool
ICON_RENDITIONS := Default Dark ClearLight ClearDark TintedLight TintedDark

.PHONY: test test-kit test-app project install scans-pull testflight app-icon-preview screenshots

test: test-kit test-app

test-kit:
	cd ScannerKit && swift test

project:
	RONEOGRAPH_DEVELOPMENT_TEAM="$(RONEOGRAPH_DEVELOPMENT_TEAM)" RONEOGRAPH_BUNDLE_ID="$(RONEOGRAPH_BUNDLE_ID)" xcodegen generate --quiet

test-app: project
	xcodebuild -quiet -project $(PROJECT) -scheme Roneograph -destination 'generic/platform=iOS' \
		-derivedDataPath $(APP_BUILD) CODE_SIGNING_ALLOWED=NO build

install: project
	sh tools/ios-install.sh $(PROJECT) $(DEVICE_BUILD) "$(IPHONE)"

scans-pull:
	sh tools/scans-pull.sh "$(RONEOGRAPH_BUNDLE_ID)" "$(SCANS_DIR)" "$(IPHONE)"

testflight: test project
	sh tools/testflight.sh $(PROJECT) $(TESTFLIGHT_BUILD)

app-icon-preview:
	mkdir -p $(ICON_PREVIEW)
	for rendition in $(ICON_RENDITIONS); do \
		"$(ICTOOL)" App/AppIcon.icon --export-image --output-file $(ICON_PREVIEW)/$$rendition.png \
			--platform iOS --rendition $$rendition --width 1024 --height 1024 --scale 1 >/dev/null || exit 1; \
	done

screenshots: project
	sh tools/screenshots.sh $(PROJECT) build/screenshots-app "$(SAMPLE_PHOTOS)" build/screenshots

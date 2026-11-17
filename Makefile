-include local.mk

export DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer
RONEOGRAPH_DEVELOPMENT_TEAM ?=
RONEOGRAPH_BUNDLE_ID ?= org.roneograph.app
IPHONE ?=
SIMULATOR ?= iPhone 17 Pro Max
PROJECT := Roneograph.xcodeproj
DEVICE_BUILD := build/device
APP_BUILD := build/app
UI_TEST_BUILD := build/ui-test
SCANS_DIR ?= build/scans
ICON_PREVIEW := build/app-icon
ICTOOL := $(DEVELOPER_DIR)/../Applications/Icon Composer.app/Contents/Executables/ictool
ICON_RENDITIONS := Default Dark ClearLight ClearDark TintedLight TintedDark

.PHONY: test test-kit test-app ui-test project install scans-pull app-icon-preview

test: test-kit test-app

test-kit:
	cd ScannerKit && swift test

project:
	RONEOGRAPH_DEVELOPMENT_TEAM="$(RONEOGRAPH_DEVELOPMENT_TEAM)" RONEOGRAPH_BUNDLE_ID="$(RONEOGRAPH_BUNDLE_ID)" xcodegen generate --quiet

test-app: project
	xcodebuild -quiet -project $(PROJECT) -scheme Roneograph -destination 'generic/platform=iOS' \
		-derivedDataPath $(APP_BUILD) CODE_SIGNING_ALLOWED=NO build

ui-test: project
	xcodebuild -quiet -project $(PROJECT) -scheme Roneograph -destination 'platform=iOS Simulator,OS=latest,name=$(SIMULATOR)' \
		-derivedDataPath $(UI_TEST_BUILD) -parallel-testing-enabled NO test

install: project
	sh tools/ios-install.sh $(PROJECT) $(DEVICE_BUILD) "$(IPHONE)"

scans-pull:
	sh tools/scans-pull.sh "$(RONEOGRAPH_BUNDLE_ID)" "$(SCANS_DIR)" "$(IPHONE)"

app-icon-preview:
	mkdir -p $(ICON_PREVIEW)
	for rendition in $(ICON_RENDITIONS); do \
		"$(ICTOOL)" App/AppIcon.icon --export-image --output-file $(ICON_PREVIEW)/$$rendition.png \
			--platform iOS --rendition $$rendition --width 1024 --height 1024 --scale 1 >/dev/null || exit 1; \
	done

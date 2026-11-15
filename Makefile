-include local.mk

export DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer
RONEOGRAPH_DEVELOPMENT_TEAM ?=
RONEOGRAPH_BUNDLE_ID ?= org.roneograph.app
IPHONE ?=
PROJECT := Roneograph.xcodeproj
DEVICE_BUILD := build/device
APP_BUILD := build/app
SCANS_DIR ?= build/scans

.PHONY: test test-kit test-app project install scans-pull

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

-include local.mk

export DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer
PDFSCANNER_DEVELOPMENT_TEAM ?=
PDFSCANNER_BUNDLE_ID ?= org.fabpot.pdfscanner
IPHONE ?=
PROJECT := PDFScanner.xcodeproj
DEVICE_BUILD := build/device
APP_BUILD := build/app
SCANS_DIR ?= build/scans

.PHONY: test test-kit test-app project install scans-pull

test: test-kit test-app

test-kit:
	cd ScannerKit && swift test

project:
	PDFSCANNER_DEVELOPMENT_TEAM="$(PDFSCANNER_DEVELOPMENT_TEAM)" PDFSCANNER_BUNDLE_ID="$(PDFSCANNER_BUNDLE_ID)" xcodegen generate --quiet

test-app: project
	xcodebuild -quiet -project $(PROJECT) -scheme PDFScanner -destination 'generic/platform=iOS' \
		-derivedDataPath $(APP_BUILD) CODE_SIGNING_ALLOWED=NO build

install: project
	sh tools/ios-install.sh $(PROJECT) $(DEVICE_BUILD) "$(IPHONE)"

scans-pull:
	sh tools/scans-pull.sh "$(PDFSCANNER_BUNDLE_ID)" "$(SCANS_DIR)" "$(IPHONE)"

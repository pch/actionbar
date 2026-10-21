APP_NAME = ActionBar
PROJECT = $(APP_NAME).xcodeproj
SCHEME = $(APP_NAME)
BUILD_DIR = $(shell xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -showBuildSettings 2>/dev/null | grep -m1 '^\s*BUILT_PRODUCTS_DIR' | sed 's/.*= //')
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app

KEYCHAIN_PROFILE ?= notary

.PHONY: build notarize run clean

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release build

notarize: build
	ditto -c -k --keepParent "$(APP_BUNDLE)" $(APP_NAME).zip
	xcrun notarytool submit $(APP_NAME).zip --keychain-profile $(KEYCHAIN_PROFILE) --wait
	xcrun stapler staple "$(APP_BUNDLE)"
	rm $(APP_NAME).zip

run: build
	-pkill -x $(APP_NAME)
	sleep 0.5
	open "$(APP_BUNDLE)"

clean:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean
	rm -rf ~/Library/Developer/Xcode/DerivedData/$(APP_NAME)-*

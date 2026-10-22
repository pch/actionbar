APP_NAME = ActionBar
PROJECT = $(APP_NAME).xcodeproj
SCHEME = $(APP_NAME)
BUILD_DIR = $(shell xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -showBuildSettings 2>/dev/null | grep -m1 '^\s*BUILT_PRODUCTS_DIR' | sed 's/.*= //')
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app

.PHONY: build run test clean

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release build

run: build
	-pkill -x $(APP_NAME)
	sleep 0.5
	open "$(APP_BUNDLE)"

# The tests don't launch the app, so they never touch the Keychain.
test:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test

clean:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean
	rm -rf ~/Library/Developer/Xcode/DerivedData/$(APP_NAME)-*

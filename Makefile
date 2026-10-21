APP_NAME = ActionBar
PROJECT = $(APP_NAME).xcodeproj
SCHEME = $(APP_NAME)
BUILD_DIR = $(shell xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -showBuildSettings 2>/dev/null | grep -m1 '^\s*BUILT_PRODUCTS_DIR' | sed 's/.*= //')
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app

.PHONY: build run clean

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release build

run: build
	-pkill -x $(APP_NAME)
	sleep 0.5
	open "$(APP_BUNDLE)"

clean:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean
	rm -rf ~/Library/Developer/Xcode/DerivedData/$(APP_NAME)-*

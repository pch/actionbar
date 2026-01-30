APP_NAME = GitHubActionsMenu
BUILD_DIR = .build/release
APP_BUNDLE = $(APP_NAME).app

.PHONY: build bundle run clean

build:
	swift build -c release

bundle: build
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	cp Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/AppIcon.icns
	codesign --force --sign - $(APP_BUNDLE)

run: bundle
	-pkill -x $(APP_NAME)
	sleep 0.5
	open $(APP_BUNDLE)

clean:
	rm -rf .build $(APP_BUNDLE)

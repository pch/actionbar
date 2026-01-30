APP_NAME = GitHubActionsMenu
BUILD_DIR = .build/apple/Products/Release
APP_BUNDLE = $(APP_NAME).app

.PHONY: build bundle run clean

build:
	swift build -c release --arch arm64 --arch x86_64

bundle: build
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	cp Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/AppIcon.icns
	codesign --force --options runtime --sign "Developer ID Application: Piotr Chmolowski (ZX8SV23YKJ)" $(APP_BUNDLE)

run: bundle
	-pkill -x $(APP_NAME)
	sleep 0.5
	open $(APP_BUNDLE)

clean:
	rm -rf .build $(APP_BUNDLE)

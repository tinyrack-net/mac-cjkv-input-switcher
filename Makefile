SHELL := /bin/zsh
APP_NAME := MacCJKVInputSwitcher
PACKAGE_ROOT := $(CURDIR)
BUILD_BIN := $(PACKAGE_ROOT)/.build/release/$(APP_NAME)
APP_DIR := $(PACKAGE_ROOT)/dist/$(APP_NAME).app
APP_BIN := $(APP_DIR)/Contents/MacOS/$(APP_NAME)
VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
PLIST_LABEL := com.winetree.MacCJKVInputSwitcher
PLIST_DIR := $(HOME)/Library/LaunchAgents
PLIST := $(PLIST_DIR)/$(PLIST_LABEL).plist
UID := $(shell id -u)
.PHONY: build app universal dmg install uninstall restart status logs clean release-prepare release-finalize
build:
	@swift build -c release
app: build
	@mkdir -p dist
	@Scripts/build-app.sh "$(BUILD_BIN)" "$(APP_DIR)"
universal:
	@Scripts/build-universal.sh "$(APP_DIR)"
dmg: universal
	@Scripts/package-dmg.sh "$(APP_DIR)" "$(VERSION)"
install: app
	@mkdir -p "$(HOME)/.local/bin" "$(PLIST_DIR)" "$(HOME)/Library/Logs"
	@cp "$(APP_BIN)" "$(HOME)/.local/bin/$(APP_NAME)"
	@sed -e 's#__INSTALL_PATH__#$(HOME)/.local/bin#' -e 's#__HOME__#$(HOME)#' LaunchAgents/$(PLIST_LABEL).plist > "$(PLIST)"
	@-launchctl bootout gui/$(UID) "$(PLIST)" 2>/dev/null
	@launchctl bootstrap gui/$(UID) "$(PLIST)"
uninstall:
	@-launchctl bootout gui/$(UID) "$(PLIST)" 2>/dev/null
	@rm -f "$(PLIST)" "$(HOME)/.local/bin/$(APP_NAME)"
restart: install
status:
	@launchctl print gui/$(UID)/$(PLIST_LABEL)
logs:
	@tail -f "$(HOME)/Library/Logs/$(APP_NAME).log"
clean:
	@swift package clean
release-prepare:
	@Scripts/release-prepare.sh $(BUMP)
release-finalize:
	@Scripts/release-finalize.sh

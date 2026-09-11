SHELL := /bin/zsh

APP_NAME := MacCJKVInputSwitcher
PACKAGE_ROOT := $(CURDIR)
BUILD_BIN := $(PACKAGE_ROOT)/.build/release/$(APP_NAME)
INSTALL_DIR := $(HOME)/.local/bin
INSTALL_BIN := $(INSTALL_DIR)/$(APP_NAME)
PLIST_LABEL := com.winetree.MacCJKVInputSwitcher
PLIST_TEMPLATE := $(PACKAGE_ROOT)/LaunchAgents/$(PLIST_LABEL).plist
PLIST_DIR := $(HOME)/Library/LaunchAgents
PLIST := $(PLIST_DIR)/$(PLIST_LABEL).plist
LOG_DIR := $(HOME)/Library/Logs
UID := $(shell id -u)

.PHONY: build install uninstall restart status logs clean

build:
	@set -o pipefail; \
	log=$$(mktemp); \
	if swift build -c release 2>&1 | tee "$$log"; then \
		rm -f "$$log"; \
	else \
		if rg -q 'precompiled file .*\.build|missing required module .SwiftShims.' "$$log"; then \
			echo "Stale SwiftPM module cache detected; cleaning and retrying..." >&2; \
			rm -f "$$log"; \
			swift package clean; \
			swift build -c release; \
		else \
			status=$$?; rm -f "$$log"; exit $$status; \
		fi; \
	fi

install: build
	@mkdir -p "$(INSTALL_DIR)" "$(PLIST_DIR)" "$(LOG_DIR)"
	cp "$(BUILD_BIN)" "$(INSTALL_BIN)"
	sed -e 's#__INSTALL_PATH__#$(INSTALL_DIR)#' -e 's#__HOME__#$(HOME)#' \
		"$(PLIST_TEMPLATE)" > "$(PLIST)"
	-launchctl bootout gui/$(UID) "$(PLIST)" 2>/dev/null
	launchctl bootstrap gui/$(UID) "$(PLIST)"
	@echo "Installed: Ctrl+Option+Shift+Space toggles configured input sources"

uninstall:
	-launchctl bootout gui/$(UID) "$(PLIST)" 2>/dev/null
	rm -f "$(PLIST)" "$(INSTALL_BIN)"
	@echo "Uninstalled $(APP_NAME)"

restart: install

status:
	launchctl print gui/$(UID)/$(PLIST_LABEL)

logs:
	tail -f "$(LOG_DIR)/$(APP_NAME).log"

clean:
	swift package clean

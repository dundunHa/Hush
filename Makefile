SHELL := /bin/bash

PROJECT ?= Hush.xcodeproj
SCHEME ?= Hush
DERIVED_DATA ?= .build/DerivedData
SPM_DIR ?= .build/SourcePackages
APP_PATH ?= $(DERIVED_DATA)/Build/Products/Debug/Hush.app
RELEASE_APP_PATH ?= $(DERIVED_DATA)/Build/Products/Release/Hush.app
RELEASE_DIR ?= build/release
SRC_DIRS ?= Hush HushTests
WATCH_DIRS ?= $(CURDIR)/Hush $(CURDIR)/HushTests
WATCH_SCRIPT ?= scripts/dev-watch.sh
XCODEBUILD ?= xcodebuild
HOST_ARCH ?= $(shell uname -m)
XCODE_DESTINATION ?= platform=macOS,arch=$(HOST_ARCH)
TEST_RESULTS_DIR ?= .build/TestResults
XCCOV ?= xcrun xccov
XCTRACE_ARGS ?=

.PHONY: help setup check-tools resolve build check-xcode release test test-cov run fmt xctrace-memory clean

help: ## Show available targets
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  %-12s %s\n", $$1, $$2}'

check-tools: ## Verify required local tools are installed
	@for tool in swiftformat swiftlint fswatch $(XCODEBUILD); do \
		if ! command -v $$tool >/dev/null 2>&1; then \
			echo "Missing required tool: $$tool"; \
			echo "Run 'make setup' to install dependencies."; \
			exit 1; \
		fi; \
	done
	@echo "All required tools are available."

resolve: ## Resolve Swift Package dependencies
	@mkdir -p "$(DERIVED_DATA)" "$(SPM_DIR)"
	@$(XCODEBUILD) -resolvePackageDependencies \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-destination "$(XCODE_DESTINATION)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-clonedSourcePackagesDirPath "$(SPM_DIR)"

setup: ## Install formatter/lint/watch tools and resolve SPM dependencies
	@if ! command -v brew >/dev/null 2>&1; then \
		echo "Homebrew is required. Install from https://brew.sh"; \
		exit 1; \
	fi
	@brew bundle --file Brewfile
	@$(MAKE) resolve

build: ## Build Debug app for scheme $(SCHEME)
	@mkdir -p "$(DERIVED_DATA)" "$(SPM_DIR)"
	@xattr -cr "$(DERIVED_DATA)" 2>/dev/null || true
	@$(XCODEBUILD) \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-destination "$(XCODE_DESTINATION)" \
		-parallel-testing-enabled NO \
		-configuration Debug \
		-derivedDataPath "$(DERIVED_DATA)" \
		-clonedSourcePackagesDirPath "$(SPM_DIR)" \
		build

check-xcode: ## Run Xcode diagnostics build with strict concurrency
	@mkdir -p "$(DERIVED_DATA)" "$(SPM_DIR)"
	@xattr -cr "$(DERIVED_DATA)" 2>/dev/null || true
	@$(XCODEBUILD) \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-destination "$(XCODE_DESTINATION)" \
		-configuration Debug \
		-derivedDataPath "$(DERIVED_DATA)" \
		-clonedSourcePackagesDirPath "$(SPM_DIR)" \
		build \
		SWIFT_STRICT_CONCURRENCY=complete

release: ## Build Release app and package into a DMG installer
	@mkdir -p "$(DERIVED_DATA)" "$(SPM_DIR)" "$(RELEASE_DIR)"
	@xattr -cr "$(DERIVED_DATA)" 2>/dev/null || true
	@echo "==> Building Release configuration..."
	@$(XCODEBUILD) \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-destination "$(XCODE_DESTINATION)" \
		-configuration Release \
		-derivedDataPath "$(DERIVED_DATA)" \
		-clonedSourcePackagesDirPath "$(SPM_DIR)" \
		build
	@echo "==> Packaging DMG..."
	@VERSION=$$(defaults read "$$(pwd)/$(RELEASE_APP_PATH)/Contents/Info" CFBundleShortVersionString); \
	BUILD=$$(defaults read "$$(pwd)/$(RELEASE_APP_PATH)/Contents/Info" CFBundleVersion); \
	DMG_NAME="Hush-$${VERSION}-$${BUILD}.dmg"; \
	DMG_PATH="$(RELEASE_DIR)/$$DMG_NAME"; \
	STAGING=$$(mktemp -d); \
	cp -R "$(RELEASE_APP_PATH)" "$$STAGING/Hush.app"; \
	ln -s /Applications "$$STAGING/Applications"; \
	rm -f "$$DMG_PATH"; \
	hdiutil create -volname "Hush" \
		-srcfolder "$$STAGING" \
		-ov -format UDZO \
		-imagekey zlib-level=9 \
		"$$DMG_PATH"; \
	rm -rf "$$STAGING"; \
	echo "==> DMG created: $$DMG_PATH"

test: ## Run all unit tests for scheme $(SCHEME)
	@mkdir -p "$(DERIVED_DATA)" "$(SPM_DIR)"
	@xattr -cr "$(DERIVED_DATA)" 2>/dev/null || true
	@$(XCODEBUILD) \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-destination "$(XCODE_DESTINATION)" \
		-parallel-testing-enabled NO \
		-configuration Debug \
		-derivedDataPath "$(DERIVED_DATA)" \
		-clonedSourcePackagesDirPath "$(SPM_DIR)" \
		-enableCodeCoverage NO \
		test \
		CODE_SIGNING_ALLOWED=NO \
		CLANG_ENABLE_CODE_COVERAGE=NO \
		GCC_GENERATE_TEST_COVERAGE_FILES=NO \
		GCC_INSTRUMENT_PROGRAM_FLOW_ARCS=NO

test-cov: ## Run all unit tests with code coverage report
	@mkdir -p "$(DERIVED_DATA)" "$(SPM_DIR)" "$(TEST_RESULTS_DIR)"
	@xattr -cr "$(DERIVED_DATA)" 2>/dev/null || true
	@RESULT_BUNDLE="$(TEST_RESULTS_DIR)/$(SCHEME)-$$(date +%Y%m%d%H%M%S).xcresult"; \
	$(XCODEBUILD) \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-destination "$(XCODE_DESTINATION)" \
		-parallel-testing-enabled NO \
		-configuration Debug \
		-derivedDataPath "$(DERIVED_DATA)" \
		-clonedSourcePackagesDirPath "$(SPM_DIR)" \
		-enableCodeCoverage YES \
		-resultBundlePath "$$RESULT_BUNDLE" \
		test \
		CODE_SIGNING_ALLOWED=NO \
		'OTHER_LDFLAGS=$$(inherited) -fprofile-instr-generate' && \
	$(XCCOV) view --report --only-targets "$$RESULT_BUNDLE"

run: clean build ## Clean, rebuild, launch app and stream rendering logs
	@echo "Launching $(APP_PATH) and streaming app logs (HUSH_RENDER_DEBUG=$${HUSH_RENDER_DEBUG:-0}, HUSH_SWITCH_DEBUG=$${HUSH_SWITCH_DEBUG:-0}, HUSH_CONTENT_DEBUG=$${HUSH_CONTENT_DEBUG:-0})"
	@HUSH_RENDER_VALUE="$${HUSH_RENDER_DEBUG:-0}"; \
	HUSH_SWITCH_VALUE="$${HUSH_SWITCH_DEBUG:-0}"; \
	HUSH_CONTENT_VALUE="$${HUSH_CONTENT_DEBUG:-0}"; \
	launchctl setenv HUSH_RENDER_DEBUG "$$HUSH_RENDER_VALUE"; \
	launchctl setenv HUSH_SWITCH_DEBUG "$$HUSH_SWITCH_VALUE"; \
	launchctl setenv HUSH_CONTENT_DEBUG "$$HUSH_CONTENT_VALUE"; \
	trap 'launchctl unsetenv HUSH_RENDER_DEBUG >/dev/null 2>&1 || true; launchctl unsetenv HUSH_SWITCH_DEBUG >/dev/null 2>&1 || true; launchctl unsetenv HUSH_CONTENT_DEBUG >/dev/null 2>&1 || true' EXIT INT TERM; \
	open -n "$(APP_PATH)"; \
	log stream --style compact --level debug --predicate 'subsystem == "com.hush.app" && (category == "Rendering" || category == "PerfTrace" || category == "SwitchRender" || category == "SwitchScroll" || category == "SwitchRenderScheduler" || category == "SwitchBubble")'

fmt: ## Format Swift code and run SwiftLint checks
	@swiftformat $(SRC_DIRS) --config .swiftformat
	@swiftlint lint --config .swiftlint.yml

xctrace-memory: build ## Record Activity Monitor trace and estimate memory delta
	@python3 scripts/xctrace-hot-scene-memory.py $(XCTRACE_ARGS)

clean: ## Remove build artifacts and local caches
	@rm -rf build .build
	@echo "Cleaned build artifacts and caches."

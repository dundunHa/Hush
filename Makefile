# Hush — Development Makefile
# macOS 14+ · Swift 6.0 · SwiftPM

SHELL := /bin/bash

# SwiftPM sandbox-safe cache paths
export CLANG_MODULE_CACHE_PATH := $(CURDIR)/.cache/clang
export SWIFTPM_CUSTOM_LIBCACHE_PATH := $(CURDIR)/.cache/swiftpm

APP_NAME     := HushApp
BUILD_DIR    := .build
RELEASE_BIN  := $(BUILD_DIR)/release/$(APP_NAME)
DEBUG_BIN    := $(BUILD_DIR)/debug/$(APP_NAME)
SOURCES      := Sources Tests Package.swift

# ──────────────────────────────────────────────
# Build
# ──────────────────────────────────────────────

.PHONY: build build-release run clean

build: | .cache  ## Build debug target
	swift build

build-release: | .cache  ## Build release target
	swift build -c release

run: build  ## Build and run the app
	$(DEBUG_BIN)

# ──────────────────────────────────────────────
# Test
# ──────────────────────────────────────────────

.PHONY: test test-filter

test: | .cache  ## Run full test suite
	swift test

# Usage: make test-filter FILTER=HushCoreTests.SettingsStoreTests
test-filter: | .cache  ## Run filtered tests (FILTER=<pattern>)
	swift test --filter $(FILTER)

# ──────────────────────────────────────────────
# Format
# ──────────────────────────────────────────────

.PHONY: fmt fmt-check fmt-install

fmt: _ensure-swift-format  ## Format all Swift sources in-place
	find Sources Tests -name '*.swift' | xargs swift-format format -i

fmt-check: _ensure-swift-format  ## Check formatting (no changes, exit 1 on diff)
	find Sources Tests -name '*.swift' | xargs swift-format lint

fmt-install:  ## Install swift-format via Homebrew
	@if ! command -v swift-format &>/dev/null; then \
		echo "Installing swift-format via Homebrew..."; \
		brew install swift-format; \
	else \
		echo "swift-format already installed: $$(swift-format --version)"; \
	fi

_ensure-swift-format:
	@command -v swift-format &>/dev/null || { \
		echo "Error: swift-format not found. Run 'make fmt-install' first."; \
		exit 1; \
	}

# ──────────────────────────────────────────────
# Dev — file-watch hot reload
# ──────────────────────────────────────────────

.PHONY: dev dev-install

dev: _ensure-fswatch build  ## Watch sources, auto-rebuild & relaunch on change
	@echo "👀 Watching $(SOURCES) — press Ctrl-C to stop"
	@# Initial launch
	@$(DEBUG_BIN) & APP_PID=$$!; \
	trap 'kill $$APP_PID 2>/dev/null; exit 0' INT TERM; \
	fswatch -o -r --exclude '$(BUILD_DIR)' --exclude '.cache' --exclude '.git' $(SOURCES) | while read -r _; do \
		echo ""; \
		echo "── Change detected, rebuilding... ──"; \
		kill $$APP_PID 2>/dev/null; \
		wait $$APP_PID 2>/dev/null; \
		if swift build 2>&1; then \
			echo "── Build OK, relaunching ──"; \
			$(DEBUG_BIN) & APP_PID=$$!; \
		else \
			echo "── Build FAILED, waiting for next change... ──"; \
		fi; \
	done

dev-install:  ## Install dev dependencies (fswatch)
	@if ! command -v fswatch &>/dev/null; then \
		echo "Installing fswatch via Homebrew..."; \
		brew install fswatch; \
	else \
		echo "fswatch already installed: $$(fswatch --version 2>&1 | head -1)"; \
	fi

_ensure-fswatch:
	@command -v fswatch &>/dev/null || { \
		echo "Error: fswatch not found. Run 'make dev-install' first."; \
		exit 1; \
	}

# ──────────────────────────────────────────────
# Setup & Housekeeping
# ──────────────────────────────────────────────

.PHONY: setup help

setup: fmt-install dev-install  ## Install all dev tooling (swift-format, fswatch)
	@echo "✅ Dev environment ready. Run 'make dev' to start."

clean:  ## Remove build artifacts and caches
	swift package clean
	rm -rf $(BUILD_DIR) .cache

.cache:
	@mkdir -p .cache/clang .cache/swiftpm

# ──────────────────────────────────────────────
# Help
# ──────────────────────────────────────────────

help:  ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help

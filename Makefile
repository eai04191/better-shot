# BetterShot Makefile
# Usage:
#   make build        — Debug build
#   make release      — Release build
#   make run          — Build and launch (debug)
#   make dmg          — Create unsigned DMG for local testing
#   make clean        — Remove build artifacts
#   make lint         — Swift compiler warnings check
#   make test-build   — Full clean + release build to verify everything compiles
#   make version      — Print current version
#   make ship         — Signed release: build, sign, notarize, DMG (both architectures)

SCHEME       = BetterShot
PROJECT      = BetterShot.xcodeproj
CONFIG_DEBUG = Debug
CONFIG_REL   = Release
DERIVED_DIR  = .build
TEST_DIR     = .build-test
APP_DEBUG    = $(DERIVED_DIR)/Build/Products/$(CONFIG_DEBUG)/$(SCHEME).app
APP_RELEASE  = $(DERIVED_DIR)/Build/Products/$(CONFIG_REL)/$(SCHEME).app
VERSION     := $(shell python3 -c "import json; print(json.load(open('version.json'))['version'])")
DMG_NAME     = BetterShot-$(VERSION).dmg
DMG_DIR      = release

# Optional fixed local code-signing identity. When empty (default), the Debug
# build stays ad-hoc signed. Set it to keep a stable designated requirement so
# macOS keeps Screen Recording / Accessibility grants across rebuilds:
#   make run BS_SIGN_ID="BetterShot Local"
# Hardened runtime is disabled for the signed Debug build: ad-hoc builds get it
# auto-disabled, but a self-signed identity (no Team ID) would otherwise trip
# Library Validation and fail to load the Xcode debug dylib at launch.
BS_SIGN_ID  ?=
SIGN_FLAGS  :=
ifneq ($(strip $(BS_SIGN_ID)),)
SIGN_FLAGS  := CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$(BS_SIGN_ID)" ENABLE_HARDENED_RUNTIME=NO
endif

.PHONY: build release run dmg clean lint test test-build version ship help

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

build: ## Debug build
	@echo "==> Building $(SCHEME) (Debug)..."
	@xcodebuild -project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIG_DEBUG) \
		-derivedDataPath $(DERIVED_DIR) \
		$(SIGN_FLAGS) \
		build 2>&1 | tail -3
	@echo "==> $(APP_DEBUG)"

release: ## Release build (unsigned)
	@echo "==> Building $(SCHEME) (Release)..."
	@xcodebuild -project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIG_REL) \
		-derivedDataPath $(DERIVED_DIR) \
		CODE_SIGN_IDENTITY="" \
		CODE_SIGNING_REQUIRED=NO \
		build 2>&1 | tail -3
	@echo "==> $(APP_RELEASE)"

run: build ## Build and launch (debug)
	@echo "==> Launching BetterShot..."
	@open "$(APP_DEBUG)"

dmg: release ## Create unsigned DMG for local testing
	@echo "==> Creating DMG..."
	@mkdir -p $(DMG_DIR)/staging
	@cp -R "$(APP_RELEASE)" $(DMG_DIR)/staging/
	@ln -sf /Applications $(DMG_DIR)/staging/Applications
	@hdiutil create -volname "BetterShot" \
		-srcfolder $(DMG_DIR)/staging \
		-ov -format UDZO \
		"$(DMG_DIR)/$(DMG_NAME)" 2>/dev/null
	@rm -rf $(DMG_DIR)/staging
	@echo "==> $(DMG_DIR)/$(DMG_NAME)"

clean: ## Remove build artifacts
	@echo "==> Cleaning..."
	@rm -rf $(DERIVED_DIR)
	@rm -rf $(DMG_DIR)/staging
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean 2>/dev/null || true
	@echo "==> Clean."

lint: ## Check for compiler warnings
	@echo "==> Checking for warnings..."
	@xcodebuild -project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIG_DEBUG) \
		-derivedDataPath $(DERIVED_DIR) \
		build 2>&1 | grep -E "warning:|error:" || echo "No warnings."

test: ## Run unit tests (isolated derived data; keeps the run/build app intact)
	@echo "==> Running tests..."
	@xcodebuild test -project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIG_DEBUG) \
		-derivedDataPath $(TEST_DIR) \
		-destination 'platform=macOS' 2>&1 | tail -5

test-build: clean release ## Full clean + release build
	@echo "==> Test build passed."

ship: ## Signed release: build, sign, notarize, DMG (both architectures)
	@bash scripts/release.sh

version: ## Print current version
	@echo "$(VERSION)"

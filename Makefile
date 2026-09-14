# Flykeeper — offline fly driven by a connectome simulation.
# Team id lives in Makefile.local (gitignored); see Makefile.local.example.
-include Makefile.local

# Recipes pipe xcodebuild into tail; without pipefail the recipe's status is tail's and a
# compile error passes `make verify` (found by review, 2026-09-14). GNU make 3.81 has no
# .SHELLFLAGS, so the flag is set per recipe line through SHELL.
SHELL := /bin/bash -o pipefail

SCHEME  := Flykeeper
PROJECT := Flykeeper.xcodeproj
BUNDLE  := co.superduperai.flykeeper
SIM_NAME := iPhone 17 Pro
# First available simulator with that name. By id, because two runtimes can share a name and
# `simctl … booted` then picks whichever booted first — a build lands on the wrong one silently.
SIM_UDID  = $(shell xcrun simctl list devices available | awk -F'[()]' -v n='$(SIM_NAME)' '$$1 == "    " n " " {print $$2; exit}')
# Physical device, by name as devicectl prints it. Override: make device DEVICE="My iPhone"
DEVICE  ?= Rust’s iPhone
DSP     := $(HOME)/Music/1music/superduper-dsp
# DerivedData inside the repo so `make clean` really cleans and app-path is deterministic.
XCB     := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -derivedDataPath $(CURDIR)/build

# $(call app-path,<sdk>) — where xcodebuild put the .app for that SDK.
app-path = $$($(XCB) -sdk $(1) -showBuildSettings 2>/dev/null \
	| awk -F' = ' '/^ *BUILT_PRODUCTS_DIR = /{d=$$2} /^ *FULL_PRODUCT_NAME = /{n=$$2} END{print d"/"n}')

.PHONY: help generate engine build test run clean probe verify device device-ps archive export upload

help: ## Show this help
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | sed 's/:.*##/\t/' | expand -t22

engine: ## Rebuild the Rust connectome engine into Vendor/FlyBrain.xcframework
	@$(DSP)/mobile/fly-ios/build-xcframework.sh $(CURDIR)/Vendor

generate: ## Regenerate the Xcode project from project.yml (TEAM from Makefile.local)
	@TEAM="$(TEAM)" xcodegen generate

build: ## Build for the simulator
	@$(XCB) -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build | tail -3

test: ## Swift domain tests (FlyKit) — no simulator needed
	@swift test

probe: ## Run the simulation headless and print its receipt (the CLI-first check)
	@cd $(DSP) && cargo run -q -p connectome-core --example probe

verify: ## Everything that must be green before a commit: Rust (core + FFI), engine rebuild, Swift, app
	@cd $(DSP) && cargo test -p connectome-core -p fly-ios
	@$(MAKE) engine
	@$(MAKE) test
	@$(MAKE) build

# Starting tier for `make run`: eco (default), standard or full.
TIER ?= eco

run: ## Build, install and launch on the simulator (TIER=full, FEED=1 drops food, COLONY=n opens with n flies)
	@test -n "$(SIM_UDID)" || { echo "no simulator named '$(SIM_NAME)' — xcrun simctl list devices"; exit 1; }
	@xcrun simctl boot $(SIM_UDID) 2>/dev/null || true
	@open -a Simulator
	@$(XCB) -sdk iphonesimulator -destination 'platform=iOS Simulator,id=$(SIM_UDID)' build | tail -2
	@app="$(call app-path,iphonesimulator)"; \
		test -d "$$app" || { echo "no app bundle at $$app — build settings did not resolve"; exit 1; }; \
		xcrun simctl install $(SIM_UDID) "$$app"
	@xcrun simctl terminate $(SIM_UDID) $(BUNDLE) 2>/dev/null || true
	@SIMCTL_CHILD_FLY_TIER=$(TIER) $(if $(FEED),SIMCTL_CHILD_FLY_FEED=1,) $(if $(LIGHTS),SIMCTL_CHILD_FLY_LIGHTS=$(LIGHTS),) $(if $(COLONY),SIMCTL_CHILD_FLY_COLONY=$(COLONY),) xcrun simctl launch $(SIM_UDID) $(BUNDLE)

device: ## Build, install and launch on the iPhone (needs TEAM in Makefile.local, phone unlocked)
	@test -n "$(TEAM)" || { echo "TEAM is empty — copy Makefile.local.example to Makefile.local"; exit 1; }
	@$(XCB) -sdk iphoneos -destination "platform=iOS,name=$(DEVICE)" -allowProvisioningUpdates \
		DEVELOPMENT_TEAM=$(TEAM) build | tail -2
	@app="$(call app-path,iphoneos)"; \
		test -d "$$app" || { echo "no app bundle at $$app"; exit 1; }; \
		xcrun devicectl device install app --device "$(DEVICE)" "$$app" | tail -1
	@xcrun devicectl device process launch --device "$(DEVICE)" $(BUNDLE) | tail -1

device-ps: ## Is Flykeeper running on the iPhone? (devicectl cannot stream its log; use Console.app for receipts)
	@xcrun devicectl device info processes --device "$(DEVICE)" 2>/dev/null | grep -i flykeeper || echo "flykeeper not running"

archive: ## Release archive for the App Store (needs TEAM in Makefile.local)
	@test -n "$(TEAM)" || { echo "TEAM is empty — copy Makefile.local.example to Makefile.local"; exit 1; }
	@$(MAKE) generate
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-derivedDataPath $(CURDIR)/build -sdk iphoneos -destination 'generic/platform=iOS' \
		-archivePath $(CURDIR)/build/$(SCHEME).xcarchive \
		-allowProvisioningUpdates DEVELOPMENT_TEAM=$(TEAM) archive | tail -3

export: ## Export a signed App Store .ipa from the archive
	@test -d $(CURDIR)/build/$(SCHEME).xcarchive || { echo "no archive — run make archive"; exit 1; }
	@printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict>\n<key>method</key><string>app-store-connect</string>\n<key>teamID</key><string>$(TEAM)</string>\n<key>destination</key><string>export</string>\n<key>uploadSymbols</key><true/>\n<key>signingStyle</key><string>manual</string>\n<key>signingCertificate</key><string>Apple Distribution</string>\n<key>provisioningProfiles</key><dict><key>$(BUNDLE)</key><string>Flykeeper App Store</string></dict>\n</dict></plist>\n' > $(CURDIR)/build/ExportOptions.plist
	@rm -rf $(CURDIR)/build/export
	# Xcode's export step shells out to `rsync`, and Homebrew's 3.5.0 makes it fail with
	# "Copy failed" / "rsync error: syntax or usage error (code 1)". Apple's own comes first.
	@PATH=/usr/bin:/bin:/usr/sbin:/sbin:$$PATH xcodebuild -exportArchive \
		-archivePath $(CURDIR)/build/$(SCHEME).xcarchive \
		-exportPath $(CURDIR)/build/export -exportOptionsPlist $(CURDIR)/build/ExportOptions.plist \
		-allowProvisioningUpdates | tail -3
	@ls -la $(CURDIR)/build/export/*.ipa

# App Store Connect API key for uploads. The .p8 must sit in ~/.appstoreconnect/private_keys/.
ASC_KEY_ID    ?= 6DC4HY7SA3
ASC_ISSUER_ID ?= 81f54c7f-cbfd-466e-96a0-eef8f99be045

upload: ## Upload the exported .ipa to App Store Connect (the app record must exist first)
	@test -f $(CURDIR)/build/export/$(SCHEME).ipa || { echo "no ipa — run make export"; exit 1; }
	@xcrun altool --upload-app -f $(CURDIR)/build/export/$(SCHEME).ipa -t ios \
		--apiKey $(ASC_KEY_ID) --apiIssuer $(ASC_ISSUER_ID) 2>&1 | tail -6

clean: ## Remove build artefacts
	@rm -rf .build build DerivedData

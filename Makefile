# Default: list the public targets below. Bare `make` does no build or
# secret-generation work; it only prints help.
.DEFAULT_GOAL := help

SCRIPTS := $(CURDIR)/scripts

# Modules/Secrets generates SecretKey.swift from a .gyb template, and the
# generated file is gitignored — so a fresh checkout cannot compile until it
# exists. CI runs buildscripts/updateSecrets.sh for the same reason. Make it a
# real file target so it is generated once, and again whenever the template
# changes.
SECRET_KEY_SWIFT := Modules/Secrets/Sources/Secrets/SecretKey.swift

$(SECRET_KEY_SWIFT): Modules/Secrets/Sources/Secrets/SecretKey.swift.gyb
	@"$(CURDIR)/buildscripts/updateSecrets.sh"

.PHONY: health build run test lint package dmg notarize identities version build-ios test-ios build-all help

health: $(SECRET_KEY_SWIFT) ## Non-interactive gate: resolve packages, unsigned Debug build, tests, lint
	@"$(SCRIPTS)/health.sh"

build: $(SECRET_KEY_SWIFT) ## Interactive build (Debug/Release); ARGS='--no-interactive --configuration Debug' skips prompts
	@"$(SCRIPTS)/build.sh" $(ARGS)

run: $(SECRET_KEY_SWIFT) ## Debug build, then open the app
	@"$(SCRIPTS)/build.sh" --no-interactive --configuration Debug $(ARGS)

test: $(SECRET_KEY_SWIFT) ## Run the configured test scheme
	@"$(SCRIPTS)/test.sh" $(ARGS)

lint: ## Run SwiftLint
	@"$(SCRIPTS)/lint.sh"

package: $(SECRET_KEY_SWIFT) ## Build the Release app into dist/
	@"$(SCRIPTS)/package.sh" $(ARGS)

dmg: $(SECRET_KEY_SWIFT) ## Create a DMG in dist/
	@"$(SCRIPTS)/create-dmg.sh" $(ARGS)

notarize: ## Notarize and staple the DMG (needs SWIFT_NOTARY_PROFILE)
	@"$(SCRIPTS)/notarize.sh" $(ARGS)

identities: ## List Keychain signing identities
	@"$(SCRIPTS)/identities.sh" $(ARGS)

version: ## Show, set, or bump MARKETING_VERSION / CURRENT_PROJECT_VERSION (in xcconfig/)
	@"$(SCRIPTS)/version.sh" $(ARGS)

# --- Project-specific -------------------------------------------------------
# This surface drives the macOS app. iOS gets its own target because it needs a
# toolchain whose CoreSimulator matches the installed simulator runtime; set
# IOS_DEVELOPER_DIR to that Xcode. This replaces upstream's
# buildscripts/quiet_build_and_test.sh, which uses the default toolchain and so
# cannot build iOS here.
build-ios: $(SECRET_KEY_SWIFT) ## Build the iOS scheme (set IOS_DEVELOPER_DIR to a matching toolchain)
	@"$(SCRIPTS)/ios.sh" $(ARGS)

test-ios: $(SECRET_KEY_SWIFT) ## Test the iOS scheme
	@"$(SCRIPTS)/ios.sh" --test $(ARGS)

# Both platforms: the macOS gate (resolve, build, test, lint), then iOS.
build-all: health build-ios ## Run the macOS health gate, then build the iOS scheme

# Help: descriptions live in the `## ...` comments on the target lines above,
# and this listing is derived from them, so it stays in sync with the Makefile.
help: ## Show this help
	@echo ""
	@echo "Usage: make <target> [ARGS='...']"
	@echo "Example: make build ARGS='--no-interactive --configuration Debug'"
	@echo ""
	@echo "Targets:"
	@awk 'BEGIN { FS = "## " } /^[A-Za-z0-9_-]+:.*## / { target = $$1; sub(/:.*/, "", target); printf "  %-12s %s\n", target, $$2 }' $(MAKEFILE_LIST)

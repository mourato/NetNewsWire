SCRIPTS := $(CURDIR)/scripts

# Modules/Secrets generates SecretKey.swift from a .gyb template, and the
# generated file is gitignored — so a fresh checkout cannot compile until it
# exists. CI runs buildscripts/updateSecrets.sh for the same reason. Make it a
# real file target so it is generated once, and again whenever the template
# changes.
SECRET_KEY_SWIFT := Modules/Secrets/Sources/Secrets/SecretKey.swift

$(SECRET_KEY_SWIFT): Modules/Secrets/Sources/Secrets/SecretKey.swift.gyb
	@"$(CURDIR)/buildscripts/updateSecrets.sh"

.PHONY: health build run test lint package dmg notarize identities version build-ios test-ios build-all

health: $(SECRET_KEY_SWIFT)
	@"$(SCRIPTS)/health.sh"

build: $(SECRET_KEY_SWIFT)
	@"$(SCRIPTS)/build.sh" $(ARGS)

run: $(SECRET_KEY_SWIFT)
	@"$(SCRIPTS)/build.sh" --no-interactive --configuration Debug $(ARGS)

test: $(SECRET_KEY_SWIFT)
	@"$(SCRIPTS)/test.sh" $(ARGS)

lint:
	@"$(SCRIPTS)/lint.sh"

package: $(SECRET_KEY_SWIFT)
	@"$(SCRIPTS)/package.sh" $(ARGS)

dmg: $(SECRET_KEY_SWIFT)
	@"$(SCRIPTS)/create-dmg.sh" $(ARGS)

notarize:
	@"$(SCRIPTS)/notarize.sh" $(ARGS)

identities:
	@"$(SCRIPTS)/identities.sh" $(ARGS)

version:
	@"$(SCRIPTS)/version.sh" $(ARGS)

# --- Project-specific -------------------------------------------------------
# This surface drives the macOS app. iOS gets its own target because it needs a
# toolchain whose CoreSimulator matches the installed simulator runtime; set
# IOS_DEVELOPER_DIR to that Xcode. This replaces upstream's
# buildscripts/quiet_build_and_test.sh, which uses the default toolchain and so
# cannot build iOS here.
build-ios: $(SECRET_KEY_SWIFT)
	@"$(SCRIPTS)/ios.sh" $(ARGS)

test-ios: $(SECRET_KEY_SWIFT)
	@"$(SCRIPTS)/ios.sh" --test $(ARGS)

# Both platforms: the macOS gate (resolve, build, test, lint), then iOS.
build-all: health build-ios

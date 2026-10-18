# AGENTS.md

This file provides guidance to coding agents — Claude Code, Codex, OpenCode,
Cursor and others — when working with code in this repository.

## Build and Development Commands

### Building and Testing
- **Full build and test**: `./buildscripts/build_and_test.sh` - Builds both macOS and iOS targets and runs all tests
- **Quiet build and test**: `./buildscripts/quiet_build_and_test.sh` - Same as above with less verbose output
- **Manual Xcode builds**:
  - macOS: `xcodebuild -project NetNewsWire.xcodeproj -scheme NetNewsWire -destination "platform=macOS,arch=arm64" build`
  - iOS: `xcodebuild -project NetNewsWire.xcodeproj -scheme NetNewsWire-iOS -destination "platform=iOS Simulator,name=iPhone 17" build`

The two upstream scripts always use the default toolchain, so their iOS half
fails while the default Xcode needs a newer CoreSimulator than this Mac
provides. Prefer `make build-all`, setting `IOS_DEVELOPER_DIR` as described
below.

### Make command surface

`make` wraps the scripts in `scripts/` (project facts live in
`scripts/config/project.env`). It drives the macOS scheme; iOS has its own
targets.

- **`make health`** — non-interactive: resolve packages, unsigned Debug build, tests, lint
- **`make build`** — interactive Debug/Release build (`ARGS='--no-interactive --configuration Debug'` to skip prompts)
- **`make run`** — Debug build, then open the app
- **`make install-app`** — build certificate-signed Release with automatic signing, then install in `/Applications`; `ARGS='--yes --skip-open'` runs unattended without launching
- **`make test-install-app`** — isolated installer safety tests (no app launch)
- **`make test`** — run the configured test scheme
- **`make test-account`** — run Account Swift package tests (`ARGS='--filter Miniflux'` for focused Miniflux tests)
- **`make lint`** — run SwiftLint (only the linters the project declares)
- **`make package`** — Release app into `dist/`
- **`make dmg`** — DMG in `dist/`
- **`make notarize`** — notarize and staple the DMG (needs `SWIFT_NOTARY_PROFILE`)
- **`make identities`** — list Keychain signing identities
- **`make version`** — show, set, or bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` (stored in `xcconfig/`)
- **`make build-ios`** / **`make test-ios`** — build or test the iOS scheme
- **`make build-all`** — both platforms: `health`, then `build-ios`

#### Signing

`--identity` takes a Keychain SHA-1 hash or certificate name, `-` for ad-hoc, or
`automatic`. Prefer `automatic` here: the app embeds a Share Extension and a
Safari extension, and those need provisioning profiles, which only automatic
signing creates.

```sh
make run     ARGS='--identity automatic'
make package ARGS='--identity automatic'
```

A free Apple ID is enough. Put `SharedXcodeSettings/DeveloperSettings.xcconfig`
next to the repo (it is not committed) with your own team, and let
`DEVELOPER_ENTITLEMENTS = -dev` drop the push and iCloud/CloudKit entitlements a
personal team cannot use:

```
CODE_SIGN_STYLE = Automatic
CODE_SIGN_IDENTITY[sdk=macosx*] = Apple Development
DEVELOPMENT_TEAM = <your team id>
ORGANIZATION_IDENTIFIER = <your org id>
DEVELOPER_ENTITLEMENTS = -dev
```

Ad-hoc signing cannot build this app, because the extensions need a profile.
Notarizing a DMG also needs a paid Developer ID Application identity, so
`make notarize` is unavailable without Apple Developer Program membership.

`SWIFT_CODE_SIGN_IDENTITY` and `SWIFT_DEVELOPMENT_TEAM` still work as
environment variables; no machine-local signing values are committed.

For worktree builds, set `XCODE_XCCONFIG_FILE` to the absolute path of your
local `DeveloperSettings.xcconfig` when the relative include cannot find it.
Do not copy that machine-local file into the worktree.

#### iOS toolchain

iOS builds need a toolchain whose CoreSimulator matches the installed simulator
runtime. Point `IOS_DEVELOPER_DIR` at that Xcode; unset means the default one.

```sh
IOS_DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer make build-ios
```

This is why `make build-all` does not use the upstream
`buildscripts/quiet_build_and_test.sh`: that script always uses the default
toolchain, so its iOS half fails when the default Xcode needs a newer
CoreSimulator than the Mac provides.

### Testing
- Run all tests: Use the `NetNewsWire.xctestplan` which includes tests from all modules
- Individual test runs follow same xcodebuild pattern with `test` action instead of `build`

### Setup
- First-time setup: Run `./setup.sh` to configure development environment and code signing
- Manual setup: Create `SharedXcodeSettings/DeveloperSettings.xcconfig` in parent directory

## Project Architecture

### High-Level Structure
NetNewsWire is a multi-platform RSS reader with separate targets for macOS and iOS, organized as a modular architecture with shared business logic.

### Key Modules (in /Modules)
- **RSCore**: Core utilities, extensions, and shared infrastructure
- **RSParser**: Feed parsing (RSS, Atom, JSON Feed, RSS-in-JSON)
- **RSWeb**: HTTP networking, downloading, caching, and web services
- **RSDatabase**: SQLite database abstraction layer using FMDB
- **Account**: Account management (Local, Feedbin, Feedly, NewsBlur, Reader API, CloudKit)
- **Articles**: Article and author data models
- **ArticlesDatabase**: Article storage and search functionality
- **SyncDatabase**: Cross-device synchronization state management
- **Secrets**: Secure credential and API key management

### Platform-Specific Code
- **Mac/**: macOS-specific UI (AppKit), preferences, main window management
- **iOS/**: iOS-specific UI (UIKit), settings, navigation
- **Shared/**: Cross-platform business logic, article rendering, smart feeds

### Key Architectural Patterns
- **Account System**: Pluggable account delegates for different sync services
- **Feed Management**: Hierarchical folder/feed organization with OPML import/export
- **Article Rendering**: Template-based HTML rendering with custom CSS themes
- **Smart Feeds**: Virtual feeds (Today, All Unread, Starred) implemented as PseudoFeed protocol
- **Timeline/Detail**: Classic three-pane interface (sidebar, timeline, detail)

### Extension Points
- Share extensions for both platforms
- Safari extension for feed subscription
- Widget support for iOS
- AppleScript support on macOS
- Intent extensions for Siri shortcuts

### Development Notes
- Uses Xcode project with Swift Package Manager for module dependencies
- Requires `xcbeautify` for formatted build output in scripts
- API keys are managed through buildscripts/updateSecrets.sh (runs during builds)
- Some features disabled in development builds due to private API keys
- Code signing configured through SharedXcodeSettings for development
- Documentation and technical notes are located in the `Technotes/` folder

### Miniflux implementation note

`MinifluxAccountDelegate.swift` remains above the usual Swift file-size target because sync lifecycle, version fallback, status reconciliation, and feed-tree ownership must stay together for this initial provider integration. Split into focused delegate extensions in a follow-up after behavior stabilizes; keep `Account.storeMinifluxCredentials` as the shared credential and identity transaction boundary.


Prefer idiomatic modern Swift.

Prefer `if let x` and `guard let x` over `if let x = x` and `guard let x = x`.

Don’t use `...` or `…` in Logger messages.

Guard statements should always put the return in a separate line.

Don’t do force unwrapping of optionals.

## Things to Know

Just because unit tests pass doesn’t mean a given bug is fixed. It may not have a test. It may not even be testable — it may require manual testing.

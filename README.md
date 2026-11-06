# Hermes Agent Widget

One tap to Hermes, wherever you use it. Independent companion project; not an official Nous Research product.

## Development preview

Implemented:
- SwiftUI companion apps for macOS and iOS.
- Named Discord, Telegram, and HTTPS dashboard destinations: add, test link, delete.
- iOS widget destination selection using AppEntity.
- macOS Automatic/Desktop/CLI widget preference.
- Desktop launch via Launch Services.
- Small and medium WidgetKit layouts with an interactive action button and separate settings background.
- Shared routing/validation package with unit tests.

**Not release-ready:** CLI discovery and Terminal handoff are implemented, but signed sandbox behavior is not verified because no code-signing identity is installed. Signed App Group/device checks and physical-device messaging-link verification remain outstanding. Do not treat unsigned builds as proof of release behavior.

## Build

Requirements: full Xcode, XcodeGen, macOS 15+; iOS target 18+.

```sh
swift test
xcodegen generate
open HermesAgentWidget.xcodeproj
```

Unsigned build checks:

```sh
xcodebuild -project HermesAgentWidget.xcodeproj -scheme HermesMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project HermesAgentWidget.xcodeproj -scheme HermesIOS -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Generated Xcode project and Config plists/entitlements are regenerated from project.yml, not committed.

### Test the latest macOS widget build

Do not remove and re-add the widget to test source changes. That does not replace a cached widget extension. Use:

```sh
./scripts/install-latest-macos.sh
```

The script uses fresh Derived Data, gives every build a timestamp build number, replaces the installed development app, ad-hoc signs the app and sandboxed extension, verifies PlugInKit registration, restarts the widget service, and launches the new app. Debug widgets and the companion app show `vVERSION (build)`; match that value to the script's final output.

For device installation, configure a development team and provision `group.com.mlarrosa.HermesAgentWidget` for each app/extension pair. No valid code-signing identities were available on the initial development machine, so signed launch gate remains blocked. Choose macOS distribution approach before finalizing CLI handoff; do not disable sandbox silently.

## Privacy

No server monitoring, bot tokens, message reading, analytics, or background polling. Destination links are saved locally in App Group defaults; this is not cross-device sync. Existing browser/messaging app handles authentication.

See docs/design.md for approved product design and CONTRIBUTING.md for commit format.

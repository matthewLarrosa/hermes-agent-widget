# Hermes Agent Widget

One tap to Hermes, wherever you use it. Independent companion project; not an official Nous Research product.

## Development preview

Implemented:
- SwiftUI companion apps for macOS and iOS.
- Named Discord, Telegram, and HTTPS dashboard destinations: add, test link, delete.
- iOS widget destination selection using AppEntity.
- macOS Automatic/Desktop/CLI widget preference.
- Desktop launch via Launch Services.
- Small and medium WidgetKit layouts using native appearance.
- Shared routing/validation package with unit tests.

**Not release-ready:** CLI discovery/interactive Terminal launch is not implemented; CLI selection currently displays recovery instructions. Automatic only detects Desktop in this preview. Editing existing destinations, installation-summary rendering, signed App Group/device checks, and physical-device link verification remain outstanding. Do not treat this preview as fulfillment of the full design.

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

For device installation, configure a development team and provision `group.com.mlarrosa.HermesAgentWidget` for each app/extension pair. No valid code-signing identities were available on the initial development machine, so signed launch gate remains blocked. Choose macOS distribution approach before finalizing CLI handoff; do not disable sandbox silently.

## Privacy

No server monitoring, bot tokens, message reading, analytics, or background polling. Destination links are saved locally in App Group defaults; this is not cross-device sync. Existing browser/messaging app handles authentication.

See docs/design.md for approved product design and CONTRIBUTING.md for commit format.

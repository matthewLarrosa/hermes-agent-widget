# Hermes Agent Widget — Product and Implementation Design

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** One tap to Hermes, wherever the user already uses it.

**Architecture:** Native SwiftUI companion apps configure WidgetKit launcher widgets on macOS and iOS. macOS discovers Hermes Desktop and CLI, then opens the chosen surface through its companion app. iOS opens a named Discord, Telegram, or web dashboard destination. No server health integration or background monitoring.

**Tech Stack:** Swift 6, SwiftUI, WidgetKit, AppIntents, App Groups, NSWorkspace, XCTest, XcodeGen. Proposed minimum versions: macOS 15 and iOS 18, subject to API/build verification.

---

## Authority and repository

This document supersedes the previous macOS-only, Apple-platform, and launch-and-messaging plans. Older plans are historical context, not implementation requirements.

Repository: https://github.com/matthewLarrosa/hermes-agent-widget.git

Intended implementation root: `/Users/mlarrosa/hermes-agent-widget`.

This document currently lives in the existing planning workspace `/Users/mlarrosa/hermes-macos-widget/.hermes/plans/`. Move/copy the approved design into the new repository when implementation starts. Do not silently rename or overwrite existing directories.

Product name: **Hermes Agent Widget**.

No code implementation or repository migration is authorized by this documentation update.

## Product principles

1. One tap opens the user's selected Hermes surface.
2. Configuration lives in companion app and native Edit Widget, not custom widget settings screens.
3. Keep widget quiet: identity, destination, primary action.
4. No status dashboard, setup nags, polling, or background server.
5. Never interpret installation discovery as agent readiness or health.
6. Never silently change an explicitly selected destination.
7. Native Apple appearance, including system-controlled macOS dimming and tinting.

## Confirmed first-release scope

### macOS

- Detect Hermes Desktop and Hermes CLI independently.
- Each widget chooses Automatic, Desktop, or CLI through Edit Widget.
- Automatic prefers installed Desktop, otherwise CLI.
- Desktop action opens installed Hermes application directly.
- CLI action opens an interactive Hermes session in Terminal, subject to signed launch feasibility gate below.
- Neither detected: offer official Hermes installation guide.
- Permission errors are not reported as missing installation.
- Small and medium widget families.

### iOS

- Save named Discord, Telegram, and web dashboard destinations.
- Each widget chooses one saved destination through Edit Widget.
- Tap opens selected link through system URL handling.
- No Hermes server address required for Discord or Telegram.
- Small and medium widget families.
- User can test a destination before placing widget.

### Explicitly out of scope

- Server/gateway/platform health.
- `/api/status` integration and `hermes serve` setup.
- Polling, status refresh buttons, online indicators, last-check timestamps.
- Bot tokens, server credentials, OAuth implementation, provider keys.
- Reading or sending messages directly.
- Session lists, recent responses, quick prompts, clipboard ingestion.
- Push notifications, Live Activities, Lock Screen widgets.
- Cross-device configuration sync.
- Alternate terminal applications in first release.
- Automatic Hermes installation, upgrades, or Desktop builds.

Remote monitoring is not a planned milestone. Reconsider only if user explicitly requests it.

## macOS behavior

### Discovery

Desktop:

1. Resolve bundle ID `com.nousresearch.hermes` using Launch Services.
2. Check `/Applications/Hermes.app` and user Applications directory if accessible.
3. Allow user to select app when automatic discovery fails.
4. Validate application bundle identity; do not trust filename alone.
5. Exclude development-build scanning from first release.

CLI:

1. Check user-selected executable using security-scoped access where required.
2. Check known locations when permitted: user's `.local/bin/hermes`, `/opt/homebrew/bin/hermes`, `/usr/local/bin/hermes`.
3. Validate regular executable file and symlink target access; a directory with executable permissions is not a CLI executable.
4. Never load shell startup files or execute a candidate just to discover it.
5. Do not assume sandbox home directory equals real user home.

Discovery outcomes must distinguish `found`, `notFound`, and `accessRequired`. Record diagnostics only in companion app.

Store bookmarks and executable paths in companion-owned storage where possible. Widget needs only safe discovery summary, not authority to execute paths.

### Per-widget preference

Use `AppIntentConfiguration` and an `AppEnum`:

- Automatic
- Hermes Desktop
- Hermes CLI

Automatic resolution:

- Desktop found: open Desktop.
- Otherwise CLI found: open CLI.
- No target found, no permission ambiguity: open install guidance.
- Access unresolved: open companion recovery screen, not a claim that Hermes is absent.

Explicit missing target:

- Show companion recovery for selected target.
- Offer available alternative as a user action.
- Do not change saved widget preference automatically.

### Desktop launch

Open validated application URL using `NSWorkspace`.

Do not call `hermes desktop` automatically. That command may install/build dependencies, which is outside a predictable launcher action.

If user selects Desktop but only CLI is available, show `Hermes Desktop not found`, offer installation guide and explicit `Open CLI instead`.

### CLI launch — mandatory feasibility gate

Before polishing widgets, prove interactive launch from signed companion app on real Mac.

Candidate: a companion-owned `.command` launcher opened explicitly with Terminal. Generated script must contain only safely quoted validated executable path and fixed startup logic. No URL-supplied commands, prompt text, or arbitrary shell arguments.

Must verify:

- Sandbox access to executable and symlink target.
- Terminal can access and execute launcher.
- Paths with spaces and quotes.
- Executable interpreter and required environment are available.
- Working directory is deliberate and usable, not app container by accident.
- First launch, relaunch, and rapid duplicate activation.
- Terminal missing/unavailable and permission refusal.
- Signed build behavior, not only unsigned development execution.

If candidate fails, stop and choose launch/distribution approach explicitly. `Copy command` plus `Open Terminal` is recovery, not successful delivery of one-tap CLI feature. Do not silently disable sandbox or claim one-tap launch is complete.

Default terminal: Apple's Terminal. Other terminals deferred.

### Missing installation

Primary action: `Get Hermes`.

Destination: https://hermes-agent.nousresearch.com/docs/getting-started/installation

Do not perform downloads or installation on user's behalf.

### Activation UX

Widget opens companion via a narrowly validated internal action route. Companion resolves current target and launches it without opening an unnecessary settings window on successful handoff.

If first-use permissions or errors require UI, show clear recovery. Never hide an error behind an invisible window.

Revalidate target on tap. Widget discovery summary can be stale after user installs/uninstalls Hermes.

## iOS behavior

### Destination setup

1. Choose Discord, Telegram, or Web dashboard.
2. Paste destination link explicitly; do not read clipboard automatically.
3. Name destination, e.g. `Personal Hermes` or `Research`.
4. Tap `Test link`.
5. Save and add widget.

Syntactic validation does not prove conversation access. `Test link` is user verification, not a claim of automated connectivity testing. Allow saving valid links without claiming they work.

### Link rules

Discord:

- Start with supported HTTPS `discord.com/channels/...` links.
- Test DM, server channel, thread, and copied message-link behavior on physical iPhone.
- Do not invent private Discord URL schemes.

Telegram:

- Start with supported HTTPS `t.me` bot/chat/topic links.
- Test bot and private topic routing on physical iPhone.
- Do not request bot token.

Dashboard:

- User-provided HTTPS dashboard URL.
- Open in browser; website owns authentication.
- No native backend API calls.
- Plain HTTP local-network URLs deferred unless specifically required.

All destinations:

- Validate exact host rules for messaging platforms, scheme, and URL structure.
- Reject embedded username/password credentials.
- Reject unsupported schemes and malformed links.
- Preserve supported conversation identifiers and safe path/query components.
- Do not log full private conversation links.
- No network requests solely to validate pasted URL.

System link handling may open installed app or browser depending on app support, login, permissions, and user preferences. Do not promise app-only routing on every device.

### Per-widget selection

Use saved destinations with stable IDs, exposed via `AppEntity` and entity query.

A platform enum alone is insufficient: two Discord destinations must be independently selectable.

Editing destination keeps ID stable. Deleting selected destination makes widget show `Choose destination`; never redirect to another destination silently.

Prefer direct external `Link` opening when WidgetKit supports intended behavior. Use companion routing only when needed for recovery or platform restrictions; validate real-device handoff before selecting final implementation.

### No misleading status

Do not show:

- Online/Offline
- Connected/Disconnected
- Status not configured
- Refresh
- Last check

Destination-only mode is the complete product, not a degraded monitoring mode.

## Visual design

### Shared visual language

- Hermes identity at top.
- One clear primary action.
- One short subtitle naming destination or selected surface.
- Semantic foreground/background styles.
- SF Symbols or approved brand assets; do not imply official affiliation.
- No custom gradients, fake live activity, or decorative status lights.

### Small macOS examples

```text
Hermes
Open Desktop

Hermes Desktop
```

```text
Hermes
Open Terminal

Hermes CLI
```

```text
Hermes
Get Hermes

Set up on this Mac
```

### Small iOS example

```text
Hermes
Open Discord

Personal assistant
```

### Medium layout

Same hierarchy with more room for destination name and accessible action label. Do not add server metrics to fill space.

Optional secondary macOS action may open the other detected surface, but only if primary chosen target remains unambiguous. Start with one action unless real usability testing justifies another.

### Native appearance

Use WidgetKit container backgrounds and semantic colors. Transparent background is a candidate, not a mandatory design choice: choose system-compatible background that preserves legibility.

Adopt accented/vibrant rendering and `.widgetAccentable()` where appropriate. macOS owns dimming behavior; do not simulate it with focus tracking or fixed opacity.

Verify light/dark, tinted/monochrome modes supported by each OS, contrasting wallpapers, Increase Contrast, Reduce Transparency, larger text, and VoiceOver.

## Companion apps

macOS screen:

- Detected Desktop and CLI with precise installation/access labels.
- Explicit `Test Desktop` / `Test CLI` actions.
- `Check again` for discovery, only in companion app.
- Choose app/executable recovery.
- Installation guide.
- Short instructions for Edit Widget.

Do not make app's global preference override a widget's explicit configuration.

iOS screen:

- Named destination list.
- Add/edit/delete destination.
- Test link.
- Short widget setup instructions.

Keep settings minimal. No account required by this app.

## Architecture and proposed paths

Paths below relative to `/Users/mlarrosa/hermes-agent-widget`.

```text
Apps/macOS/
  HermesMacApp.swift
  MacSettingsView.swift
  LocalInstallationDetector.swift
  DesktopLauncher.swift
  CLILauncher.swift
  LaunchRouter.swift
Apps/iOS/
  HermesIOSApp.swift
  DestinationListView.swift
  DestinationEditorView.swift
Shared/
  Models/ChatDestination.swift
  Models/InstallationSummary.swift
  Persistence/DestinationStore.swift
  Persistence/InstallationSummaryStore.swift
  Routing/DestinationValidator.swift
  Routing/MacLaunchResolver.swift
Widgets/Shared/
  LauncherWidgetView.swift
Widgets/macOS/
  MacWidgetConfigurationIntent.swift
  HermesMacWidget.swift
Widgets/iOS/
  DestinationEntity.swift
  DestinationQuery.swift
  IOSWidgetConfigurationIntent.swift
  HermesIOSWidget.swift
Tests/SharedTests/
Tests/macOSTests/
Tests/iOSTests/
project.yml
README.md
CONTRIBUTING.md
.github/workflows/build.yml
```

Keep platform-only frameworks and discovery logic out of shared source memberships. Avoid unnecessary service/plugin frameworks.

App Group contains only data widget needs: named destinations and safe local discovery summary. App Groups are device-local, not iCloud sync.

If App Group unavailable, expose configuration error; do not silently fall back to `.standard` defaults and create mismatched app/widget state.

## Privacy and security

- No analytics or telemetry by default.
- No backend probing.
- No bot/user/provider tokens.
- No message content or session scraping.
- No shell commands or paths accepted from external deep links.
- Internal links contain allowlisted action or saved destination ID only.
- External activation must not allow arbitrary execution beyond explicit launcher actions.
- Validate installed target on activation and handle changed/missing paths.
- Store user-selected security-scoped bookmarks in app storage.
- Redact private links and local paths from support logs by default.
- Explain that opening a messaging link uses that app's existing account/session.

## Implementation sequence and release gates

### Gate 1: Real launch experiments

Before large UI implementation:

1. Signed macOS companion opens installed Hermes Desktop.
2. Signed macOS companion opens interactive Hermes CLI in Terminal.
3. iPhone opens user's actual Discord conversation from candidate widget link flow.
4. iPhone opens Telegram test destination and dashboard link.

Record actual results, permissions, limitations, and device/OS used. If CLI gate fails, resolve product/distribution choice with user before promising full release.

### Gate 2: Pure routing and storage tests

Write failing tests, run to confirm failure, implement minimal behavior, rerun to pass.

Targets:

- `Tests/macOSTests/MacLaunchResolverTests.swift`: both/one/neither/access-needed, explicit preference never silently falls back.
- `Tests/macOSTests/LocalInstallationDetectorTests.swift`: regular executable versus directory, missing symlink target, permission errors, bundle identity.
- `Tests/SharedTests/DestinationValidatorTests.swift`: valid links, malicious lookalike hosts, unsupported schemes, embedded credentials, path preservation.
- `Tests/SharedTests/DestinationStoreTests.swift`: stable IDs, edits/deletes, missing/corrupt store, unavailable App Group.
- `Tests/macOSTests/LaunchRouterTests.swift`: reject arbitrary actions/commands, revalidate target, duplicate activation behavior.

### Gate 3: Companion setup and native widget configuration

- Complete minimal setup/recovery screens.
- Implement macOS per-widget AppEnum choice.
- Implement iOS destination AppEntity selection.
- Add small/medium shared presentation.
- Ensure two widgets keep independent selections.

### Gate 4: Signed device validation and CI

Generate project and build/test real schemes created in `project.yml`:

```bash
xcodegen generate
xcodebuild -list -project HermesAgentWidget.xcodeproj
xcodebuild test -project HermesAgentWidget.xcodeproj -scheme HermesMac -destination 'platform=macOS'
xcodebuild build -project HermesAgentWidget.xcodeproj -scheme HermesIOS -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

Run iOS tests on an installed simulator selected from `xcrun simctl list devices available`. Run routing/widget acceptance checks on physical iPhone and signed Mac build; simulator/unsigned builds do not prove permissions or universal-link behavior.

CI should validate both platforms and portable tests. CI green does not replace launch gate.

## Acceptance checklist

- [ ] Desktop-only Mac opens Desktop.
- [ ] CLI-only Mac opens interactive CLI in Terminal.
- [ ] Both installed: Automatic opens Desktop.
- [ ] Explicit Desktop/CLI preference respected independently per widget.
- [ ] No detected installation opens official installation guidance.
- [ ] Access denied is not mislabeled missing.
- [ ] Uninstall/move after setup produces clear recovery.
- [ ] Duplicate callback does not unintentionally launch twice.
- [ ] Discord widget reaches user's intended conversation under documented prerequisites.
- [ ] Telegram and dashboard destinations open through supported link routing.
- [ ] Deleted destination shows setup recovery, not another chat.
- [ ] Two widgets can select different Discord destinations.
- [ ] No server connection, polling, or credentials needed.
- [ ] Mac asleep does not prevent phone from opening configured Discord link; no claim agent will respond while host asleep.
- [ ] Native widget appearance/accessibility verified.
- [ ] Tests and builds pass; actual launch behavior recorded.

## Distribution decision still required

Decide before final CLI implementation:

- macOS direct signed/notarized distribution or Mac App Store.
- iOS TestFlight for testing, then App Store if public distribution desired.

Distribution affects sandbox, entitlements, signing, and launch options. Do not weaken security silently to bypass launch issues. Verify Apple Developer account/provisioning access before promising physical-device deployment or public release.

## Commit convention

Required format:

```text
<type>(<scope>): <imperative summary>
```

Examples:

```text
docs(design): focus widget on one-tap launch
feat(macos): detect Hermes desktop and CLI
feat(widget): add per-widget launch preference
feat(ios): add named chat destinations
fix(routing): reject credential-bearing URLs
test(widget): cover deleted destinations
ci(build): validate Apple platform targets
chore(project): configure widget extensions
```

Use focused commits after verified behavior. No fake test output, speculative completion claims, or generated secrets in repository.

import AppIntents
import OSLog
import SwiftUI
import WidgetKit
import HermesCore
#if os(macOS)
import AppKit
#endif

struct DestinationOptionsProvider: DynamicOptionsProvider {
    func results() async throws -> [String] {
        try SharedStore.load().map(\.name)
    }
}

struct MacOpenOptionsProvider: DynamicOptionsProvider {
    func results() async throws -> [String] {
        ["Automatic", "Hermes Desktop", "Hermes CLI"]
    }
}

struct CornerImageOptionsProvider: DynamicOptionsProvider {
    func results() async throws -> [String] {
        ["Staff", "Agent"]
    }
}

private enum MacChoice: String {
    case automatic, desktop, cli
}

struct LauncherConfigurationV4: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Hermes launcher"
    #if os(macOS)
    @Parameter(title: "Open", optionsProvider: MacOpenOptionsProvider()) var preference: String?
    @Parameter(title: "Saved Destination", optionsProvider: DestinationOptionsProvider()) var destination: String?
    #else
    @Parameter(title: "Destination", optionsProvider: DestinationOptionsProvider()) var destination: String?
    #endif
    @Parameter(title: "Corner Image", optionsProvider: CornerImageOptionsProvider()) var cornerImage: String?
    @Parameter(title: "Action Label", default: "Ask Hermes") var actionLabel: String
}

struct OpenHermesWidgetAction: AppIntent {
    static let title: LocalizedStringResource = "Open Hermes"
    static let description = IntentDescription("Opens the destination selected for this Hermes widget.")
    static let openAppWhenRun = true

    @Parameter(title: "Destination") var urlString: String

    init() {
        urlString = "hermeswidget://setup"
    }

    init(_ url: URL) {
        urlString = url.absoluteString
    }

    func perform() async throws -> some IntentResult {
        let url = URL(string: urlString) ?? URL(string: "hermeswidget://setup")!
        #if os(macOS)
        _ = NSWorkspace.shared.open(url)
        return .result()
        #else
        return .result(opensIntent: OpenURLIntent(url))
        #endif
    }
}

struct OpenAutomaticHermesAction: AppIntent {
    static let title: LocalizedStringResource = "Open Hermes Automatically"
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        #if os(macOS)
        _ = NSWorkspace.shared.open(URL(string: "hermeswidget://launch/automatic")!)
        #endif
        return .result()
    }
}

struct OpenHermesDesktopAction: AppIntent {
    static let title: LocalizedStringResource = "Open Hermes Desktop"
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        #if os(macOS)
        _ = NSWorkspace.shared.open(URL(string: "hermeswidget://launch/desktop")!)
        #endif
        return .result()
    }
}

struct OpenHermesCLIAction: AppIntent {
    static let title: LocalizedStringResource = "Open Hermes CLI"
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        #if os(macOS)
        _ = NSWorkspace.shared.open(URL(string: "hermeswidget://launch/cli")!)
        #endif
        return .result()
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let title: String
    let subtitle: String
    let url: URL
    let imageName: String
    let actionLabel: String
    let buildLabel: String
}

struct Provider: AppIntentTimelineProvider {
    private let logger = Logger(subsystem: "com.mlarrosa.HermesAgentWidget", category: "timeline")

    func placeholder(in context: Context) -> Entry {
        Entry(
            date: .now,
            title: "Open Hermes",
            subtitle: "Your assistant",
            url: URL(string: "hermeswidget://setup")!,
            imageName: "HermesStaff",
            actionLabel: "Ask Hermes",
            buildLabel: BuildIdentity.label
        )
    }

    func snapshot(for configuration: LauncherConfigurationV4, in context: Context) async -> Entry {
        make(configuration)
    }

    func timeline(for configuration: LauncherConfigurationV4, in context: Context) async -> Timeline<Entry> {
        Timeline(entries: [make(configuration)], policy: .after(.now.addingTimeInterval(15 * 60)))
    }

    private func make(_ configuration: LauncherConfigurationV4) -> Entry {
        #if os(macOS)
        logger.info("Widget configuration open=\(configuration.preference ?? "Automatic", privacy: .public) destinationSelected=\(configuration.destination != nil, privacy: .public) image=\(configuration.cornerImage ?? "Staff", privacy: .public)")
        #else
        logger.info("Widget configuration destinationSelected=\(configuration.destination != nil, privacy: .public) image=\(configuration.cornerImage ?? "Staff", privacy: .public)")
        #endif
        let imageName = imageAsset(configuration.cornerImage)
        #if os(macOS)
        if let item = selectedDestination(configuration.destination) {
            return Entry(
                date: .now,
                title: "Open \(item.kind.rawValue.capitalized)",
                subtitle: item.name,
                url: item.url,
                imageName: imageName,
                actionLabel: label(configuration.actionLabel),
                buildLabel: BuildIdentity.label
            )
        }
        let preference = macChoice(configuration.preference)
        let summary = try? SharedStore.loadInstallation()
        let presentation = macPresentation(preference, summary: summary ?? nil)
        return Entry(
            date: .now,
            title: presentation.title,
            subtitle: presentation.subtitle,
            url: URL(string: "hermeswidget://launch/\(preference.rawValue)")!,
            imageName: imageName,
            actionLabel: label(configuration.actionLabel),
            buildLabel: BuildIdentity.label
        )
        #else
        if let item = selectedDestination(configuration.destination) {
            return Entry(
                date: .now,
                title: "Open \(item.kind.rawValue.capitalized)",
                subtitle: item.name,
                url: item.url,
                imageName: imageName,
                actionLabel: label(configuration.actionLabel),
                buildLabel: BuildIdentity.label
            )
        }
        return Entry(
            date: .now,
            title: "Choose destination",
            subtitle: "Set up in Hermes",
            url: URL(string: "hermeswidget://setup")!,
            imageName: imageName,
            actionLabel: label(configuration.actionLabel),
            buildLabel: BuildIdentity.label
        )
        #endif
    }

    private func selectedDestination(_ selection: String?) -> Destination? {
        guard let selection, let items = try? SharedStore.load() else { return nil }
        return items.first { $0.name == selection }
    }

    private func imageAsset(_ selection: String?) -> String {
        selection?.caseInsensitiveCompare("Agent") == .orderedSame ? "HermesAgent" : "HermesStaff"
    }

    private func label(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Ask Hermes" : String(trimmed.prefix(32))
    }

    #if os(macOS)
    private func macChoice(_ selection: String?) -> MacChoice {
        switch selection?.lowercased() {
        case "hermes desktop": .desktop
        case "hermes cli": .cli
        default: .automatic
        }
    }

    private func macPresentation(_ preference: MacChoice, summary: InstallationSummary?) -> (title: String, subtitle: String) {
        guard let summary else {
            switch preference {
            case .automatic: return ("Open Hermes", "Set up in app")
            case .desktop: return ("Open Desktop", "Hermes Desktop")
            case .cli: return ("Open Terminal", "Hermes CLI")
            }
        }
        switch preference {
        case .automatic:
            if summary.desktopFound { return ("Open Desktop", "Hermes Desktop") }
            if summary.cliFound { return ("Open Terminal", "Hermes CLI") }
            return summary.accessRequired ? ("Set up Hermes", "CLI access needed") : ("Get Hermes", "Set up on this Mac")
        case .desktop:
            return summary.desktopFound ? ("Open Desktop", "Hermes Desktop") : ("Set up Desktop", "Hermes Desktop not found")
        case .cli:
            if summary.cliFound { return ("Open Terminal", "Hermes CLI") }
            return summary.accessRequired ? ("Choose CLI", "Access needed") : ("Set up CLI", "Hermes CLI not found")
        }
    }
    #endif
}

struct LauncherView: View {
    let entry: Entry

    private let settingsURL = URL(string: "hermeswidget://setup")!

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(entry.imageName)
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Hermes").font(.headline)
                        #if DEBUG
                        Text(entry.buildLabel)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        #endif
                    }
                }
                Spacer(minLength: 0)
                Text(entry.title).font(.headline)
                Text(entry.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            actionButton.buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(settingsURL)
        .containerBackground(.background.tertiary, for: .widget)
    }

    @ViewBuilder
    private var actionButton: some View {
        if entry.url.host == "launch" {
            switch String(entry.url.path.dropFirst()) {
            case "desktop":
                Button(intent: OpenHermesDesktopAction(), label: actionButtonLabel)
            case "cli":
                Button(intent: OpenHermesCLIAction(), label: actionButtonLabel)
            default:
                Button(intent: OpenAutomaticHermesAction(), label: actionButtonLabel)
            }
        } else {
            Button(intent: OpenHermesWidgetAction(entry.url), label: actionButtonLabel)
        }
    }

    private func actionButtonLabel() -> some View {
        HStack(spacing: 6) {
            Text(entry.actionLabel).lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "arrow.up.right")
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 9))
        .contentShape(RoundedRectangle(cornerRadius: 9))
    }
}

@main
struct HermesWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "HermesLauncherV4", intent: LauncherConfigurationV4.self, provider: Provider()) {
            LauncherView(entry: $0)
        }
        .configurationDisplayName("Hermes")
        .description("One tap to your Hermes.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

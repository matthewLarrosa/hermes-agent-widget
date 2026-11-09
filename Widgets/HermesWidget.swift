import AppIntents
import OSLog
import SwiftUI
import WidgetKit
import HermesCore
#if os(macOS)
import AppKit
#endif

struct DestinationOptionsProvider: DynamicOptionsProvider {
    private let logger = Logger(subsystem: "com.mlarrosa.HermesAgentWidget", category: "destination-options")

    func results() async throws -> [String] {
        do {
            let names = try SharedStore.load().map(\.name)
            logger.info("Provided \(names.count, privacy: .public) saved destination options")
            return names
        } catch {
            logger.error("Could not load saved destination options: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}

struct MacOpenOptionsProvider: DynamicOptionsProvider {
    func results() async throws -> [String] {
        ["Saved Destination", "Hermes Desktop", "Hermes CLI"]
    }

    func defaultResult() async -> String? {
        Self.preferredTarget()
    }

    static func preferredTarget() -> String {
        guard let summary = try? SharedStore.loadInstallation() else {
            return "Saved Destination"
        }
        if summary.desktopFound { return "Hermes Desktop" }
        if summary.cliFound { return "Hermes CLI" }
        return "Saved Destination"
    }
}

struct CornerImageOptionsProvider: DynamicOptionsProvider {
    func results() async throws -> [String] {
        ["Staff", "Agent"]
    }
}

private enum MacChoice: String {
    case savedDestination = "destination"
    case desktop, cli
}

struct LauncherConfigurationV5: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Hermes launcher"
    #if os(macOS)
    @Parameter(title: "Open", optionsProvider: MacOpenOptionsProvider()) var openTarget: String?
    @Parameter(title: "Saved Destination", optionsProvider: DestinationOptionsProvider()) var destinationChoice: String?
    #else
    @Parameter(title: "Destination", optionsProvider: DestinationOptionsProvider()) var destinationChoice: String?
    #endif
    @Parameter(title: "Corner Image", optionsProvider: CornerImageOptionsProvider()) var cornerImage: String?
    @Parameter(title: "Action Label", default: "Ask Hermes") var actionLabel: String

    init() {
        #if os(macOS)
        openTarget = MacOpenOptionsProvider.preferredTarget()
        #endif
    }

    #if os(macOS)
    static var parameterSummary: some ParameterSummary {
        When(\.$openTarget, .equalTo, "Saved Destination") {
            Summary {
                \.$openTarget
                \.$destinationChoice
                \.$cornerImage
                \.$actionLabel
            }
        } otherwise: {
            Summary {
                \.$openTarget
                \.$cornerImage
                \.$actionLabel
            }
        }
    }
    #endif
}

struct OpenHermesWidgetAction: AppIntent {
    static let title: LocalizedStringResource = "Open Hermes"
    static let description = IntentDescription("Opens the destination selected for this Hermes widget.")
    static let openAppWhenRun = false

    @Parameter(title: "Destination") var urlString: String

    init() {
        urlString = "hermeswidget://setup"
    }

    init(_ url: URL) {
        urlString = url.absoluteString
    }

    #if os(macOS)
    func perform() async throws -> some IntentResult {
        let url = URL(string: urlString) ?? URL(string: "hermeswidget://setup")!
        _ = NSWorkspace.shared.open(url)
        return .result()
    }
    #else
    func perform() async throws -> some IntentResult & OpensIntent {
        let url = URL(string: urlString) ?? URL(string: "hermeswidget://setup")!
        return .result(opensIntent: OpenURLIntent(url))
    }
    #endif
}

struct Entry: TimelineEntry {
    let date: Date
    let subtitle: String
    let url: URL
    let imageName: String
    let actionLabel: String
    let hermesStatus: HermesStatus?
}

struct Provider: AppIntentTimelineProvider {
    private let logger = Logger(subsystem: "com.mlarrosa.HermesAgentWidget", category: "timeline")

    func placeholder(in context: Context) -> Entry {
        Entry(
            date: .now,
            subtitle: "Your assistant",
            url: URL(string: "hermeswidget://setup")!,
            imageName: "HermesStaff",
            actionLabel: "Ask Hermes",
            hermesStatus: nil
        )
    }

    func snapshot(for configuration: LauncherConfigurationV5, in context: Context) async -> Entry {
        make(configuration)
    }

    func timeline(for configuration: LauncherConfigurationV5, in context: Context) async -> Timeline<Entry> {
        Timeline(entries: [make(configuration)], policy: .after(.now.addingTimeInterval(60)))
    }

    private func make(_ configuration: LauncherConfigurationV5) -> Entry {
        #if os(macOS)
        let openTarget = configuration.openTarget ?? MacOpenOptionsProvider.preferredTarget()
        logger.info("Widget configuration open=\(openTarget, privacy: .public) destinationSelected=\(configuration.destinationChoice != nil, privacy: .public) image=\(configuration.cornerImage ?? "Staff", privacy: .public)")
        #else
        logger.info("Widget configuration destinationSelected=\(configuration.destinationChoice != nil, privacy: .public) image=\(configuration.cornerImage ?? "Staff", privacy: .public)")
        #endif
        let imageName = imageAsset(configuration.cornerImage)
        #if os(macOS)
        let preference = macChoice(openTarget)
        let status = HermesStatusReader.load()
        if preference == .savedDestination {
            if let item = selectedDestination(configuration.destinationChoice) {
                return Entry(
                    date: .now,
                    subtitle: item.name,
                    url: item.url,
                    imageName: imageName,
                    actionLabel: label(configuration.actionLabel),
                    hermesStatus: status
                )
            }
            return Entry(
                date: .now,
                subtitle: "Set up in Hermes",
                url: URL(string: "hermeswidget://setup")!,
                imageName: imageName,
                actionLabel: label(configuration.actionLabel),
                hermesStatus: status
            )
        }
        let summary = try? SharedStore.loadInstallation()
        let subtitle = macSubtitle(preference, summary: summary ?? nil)
        return Entry(
            date: .now,
            subtitle: subtitle,
            url: URL(string: "hermeswidget://launch/\(preference.rawValue)")!,
            imageName: imageName,
            actionLabel: label(configuration.actionLabel),
            hermesStatus: status
        )
        #else
        if let item = selectedDestination(configuration.destinationChoice) {
            return Entry(
                date: .now,
                subtitle: item.name,
                url: item.url,
                imageName: imageName,
                actionLabel: label(configuration.actionLabel),
                hermesStatus: nil
            )
        }
        return Entry(
            date: .now,
            subtitle: "Set up in Hermes",
            url: URL(string: "hermeswidget://setup")!,
            imageName: imageName,
            actionLabel: label(configuration.actionLabel),
            hermesStatus: nil
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
        default: .savedDestination
        }
    }

    private func macSubtitle(_ preference: MacChoice, summary: InstallationSummary?) -> String {
        guard let summary else {
            switch preference {
            case .savedDestination: return "Set up in Hermes"
            case .desktop: return "Hermes Desktop"
            case .cli: return "Hermes CLI"
            }
        }
        switch preference {
        case .savedDestination:
            return "Set up in Hermes"
        case .desktop:
            return summary.desktopFound ? "Hermes Desktop" : "Hermes Desktop not found"
        case .cli:
            if summary.cliFound { return "Hermes CLI" }
            return summary.accessRequired ? "CLI access needed" : "Hermes CLI not found"
        }
    }
    #endif
}

struct LauncherView: View {
    let entry: Entry

    private let settingsURL = URL(string: "hermeswidget://setup")!

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(entry.imageName)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(.primary)
                    .frame(width: 34, height: 34)
                Text("Hermes").font(.headline)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.subtitle)
                    .font(.headline)
                    .lineLimit(1)
                if let status = entry.hermesStatus {
                    statusLine(status)
                }
            }

            Button(intent: OpenHermesWidgetAction(entry.url), label: actionButtonLabel)
                .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(settingsURL)
        .containerBackground(.background.tertiary, for: .widget)
    }

    private func actionButtonLabel() -> some View {
        HStack(spacing: 6) {
            Text(entry.actionLabel).lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "arrow.up.right")
        }
        .font(.headline)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 46, maxHeight: 46)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    private func statusLine(_ status: HermesStatus) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status.isOnline ? Color.green.opacity(0.8) : Color.secondary.opacity(0.45))
                .frame(width: 7, height: 7)
            Text(status.isOnline ? "Online" : "Offline")
            Text("·")
            Text(status.model.isEmpty ? "—" : status.model)
            Text("·")
            Text(status.activity.rawValue)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
}

@main
struct HermesWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "HermesLauncherV5", intent: LauncherConfigurationV5.self, provider: Provider()) {
            LauncherView(entry: $0)
        }
        .configurationDisplayName("Hermes")
        .description("One tap to your Hermes.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

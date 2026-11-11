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
    let detail: String
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
            detail: "Saved Destination",
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
                    detail: "Saved Destination",
                    url: item.url,
                    imageName: imageName,
                    actionLabel: label(configuration.actionLabel),
                    hermesStatus: status
                )
            }
            return Entry(
                date: .now,
                subtitle: "Set up in Hermes",
                detail: "Saved Destination",
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
            detail: openTarget,
            url: URL(string: "hermeswidget://launch/\(preference.rawValue)")!,
            imageName: imageName,
            actionLabel: localActionLabel(configuration.actionLabel, preference: preference),
            hermesStatus: status
        )
        #else
        if let item = selectedDestination(configuration.destinationChoice) {
            return Entry(
                date: .now,
                subtitle: item.name,
                detail: item.kind.rawValue.capitalized,
                url: item.url,
                imageName: imageName,
                actionLabel: label(configuration.actionLabel),
                hermesStatus: nil
            )
        }
        return Entry(
            date: .now,
            subtitle: "Set up in Hermes",
            detail: "Saved Destination",
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

    private func localActionLabel(_ configured: String, preference: MacChoice) -> String {
        let configured = label(configured)
        guard configured == "Ask Hermes" else { return configured }
        switch preference {
        case .savedDestination: return configured
        case .desktop: return "Open Desktop"
        case .cli: return "Open CLI"
        }
    }
    #endif
}

struct LauncherView: View {
    @Environment(\.widgetFamily) private var family

    let entry: Entry

    private let settingsURL = URL(string: "hermeswidget://setup")!

    var body: some View {
        Group {
            if family == .systemMedium {
                mediumLayout
            } else {
                smallLayout
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(primaryColor)
        .widgetURL(settingsURL)
        .containerBackground(widgetBackground, for: .widget)
        .padding(14)
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            identity
            Spacer(minLength: 10)
            Text(entry.subtitle)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Text(smallDetail)
                .font(.system(size: 8, weight: .regular))
                .foregroundStyle(secondaryColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.top, 3)
            actionButton
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var mediumLayout: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                identity
                Spacer(minLength: 10)
                Text(entry.subtitle)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let status = entry.hermesStatus {
                    statusLine(status)
                        .padding(.top, 4)
                } else {
                    Text(entry.detail)
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(secondaryColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            actionButton
                .frame(width: 120)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var identity: some View {
        HStack(spacing: 1) {
            Image(entry.imageName)
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: 30, height: 30)
            Text("Hermes")
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
        .frame(height: 30)
    }

    private var smallDetail: String {
        guard entry.detail != "Saved Destination", let status = entry.hermesStatus else {
            return "Saved Destination"
        }
        return status.isOnline ? "Online" : "Offline"
    }

    private var actionButton: some View {
        Button(intent: OpenHermesWidgetAction(entry.url)) {
            HStack(spacing: 4) {
                Text(entry.actionLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 10, height: 10)
            }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(primaryColor)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40)
            .background(actionBackground, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.actionLabel)
        .accessibilityHint("Opens the selected Hermes destination")
    }

    private func statusLine(_ status: HermesStatus) -> some View {
        HStack(spacing: 4) {
            Text(status.isOnline ? "Online" : "Offline")
            Text("·")
            Text(status.model.isEmpty ? "—" : status.model)
            Text("·")
            Text(status.activity.rawValue)
        }
        .font(.system(size: 9, weight: .regular))
        .foregroundStyle(secondaryColor)
        .lineLimit(1)
        .truncationMode(.tail)
        .accessibilityElement(children: .combine)
    }

    private var widgetBackground: Color {
        #if os(macOS)
        Color(red: 248 / 255, green: 248 / 255, blue: 247 / 255)
        #else
        Color(.systemBackground)
        #endif
    }

    private var primaryColor: Color {
        #if os(macOS)
        Color(red: 21 / 255, green: 21 / 255, blue: 21 / 255)
        #else
        .primary
        #endif
    }

    private var secondaryColor: Color {
        #if os(macOS)
        Color(red: 118 / 255, green: 118 / 255, blue: 115 / 255)
        #else
        .secondary
        #endif
    }

    private var actionBackground: Color {
        #if os(macOS)
        Color(red: 232 / 255, green: 232 / 255, blue: 230 / 255)
        #else
        Color.secondary.opacity(0.12)
        #endif
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
        .containerBackgroundRemovable(false)
        .contentMarginsDisabled()
    }
}

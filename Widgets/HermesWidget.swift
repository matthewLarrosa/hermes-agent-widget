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
        openTarget = "Saved Destination"
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

    func snapshot(for configuration: LauncherConfigurationV5, in context: Context) async -> Entry {
        make(configuration)
    }

    func timeline(for configuration: LauncherConfigurationV5, in context: Context) async -> Timeline<Entry> {
        Timeline(entries: [make(configuration)], policy: .after(.now.addingTimeInterval(15 * 60)))
    }

    private func make(_ configuration: LauncherConfigurationV5) -> Entry {
        #if os(macOS)
        logger.info("Widget configuration open=\(configuration.openTarget ?? "Saved Destination", privacy: .public) destinationSelected=\(configuration.destinationChoice != nil, privacy: .public) image=\(configuration.cornerImage ?? "Staff", privacy: .public)")
        #else
        logger.info("Widget configuration destinationSelected=\(configuration.destinationChoice != nil, privacy: .public) image=\(configuration.cornerImage ?? "Staff", privacy: .public)")
        #endif
        let imageName = imageAsset(configuration.cornerImage)
        #if os(macOS)
        let preference = macChoice(configuration.openTarget)
        if preference == .savedDestination {
            if let item = selectedDestination(configuration.destinationChoice) {
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
        }
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
        if let item = selectedDestination(configuration.destinationChoice) {
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
        default: .savedDestination
        }
    }

    private func macPresentation(_ preference: MacChoice, summary: InstallationSummary?) -> (title: String, subtitle: String) {
        guard let summary else {
            switch preference {
            case .savedDestination: return ("Choose destination", "Set up in Hermes")
            case .desktop: return ("Open Desktop", "Hermes Desktop")
            case .cli: return ("Open Terminal", "Hermes CLI")
            }
        }
        switch preference {
        case .savedDestination:
            return ("Choose destination", "Set up in Hermes")
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
        AppIntentConfiguration(kind: "HermesLauncherV5", intent: LauncherConfigurationV5.self, provider: Provider()) {
            LauncherView(entry: $0)
        }
        .configurationDisplayName("Hermes")
        .description("One tap to your Hermes.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

import AppIntents
import SwiftUI
import WidgetKit
import HermesCore

struct DestinationEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Destination"
    static var defaultQuery: DestinationQuery { DestinationQuery() }
    var id: String
    var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}
struct DestinationQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [DestinationEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [DestinationEntity] {
        try SharedStore.load().map { DestinationEntity(id: $0.id.uuidString, name: $0.name) }
    }
}
enum MacChoice: String, AppEnum {
    case automatic, desktop, cli
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Launch preference"
    static var caseDisplayRepresentations: [MacChoice: DisplayRepresentation] {
        [.automatic: "Automatic", .desktop: "Hermes Desktop", .cli: "Hermes CLI"]
    }
}
struct Configuration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Hermes launcher"
    #if os(macOS)
    @Parameter(title: "Open", default: .automatic) var preference: MacChoice
    #else
    @Parameter(title: "Destination") var destination: DestinationEntity?
    #endif
}
struct Entry: TimelineEntry {
    let date: Date
    let title: String
    let subtitle: String
    let url: URL
    let imageName: String
}
struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, title: "Open Hermes", subtitle: "Your assistant", url: URL(string: "hermeswidget://setup")!, imageName: "HermesBrand") }
    func snapshot(for configuration: Configuration, in context: Context) async -> Entry { make(configuration) }
    func timeline(for configuration: Configuration, in context: Context) async -> Timeline<Entry> { Timeline(entries: [make(configuration)], policy: .never) }
    private func make(_ configuration: Configuration) -> Entry {
        #if os(macOS)
        let summary = try? SharedStore.loadInstallation()
        let presentation = macPresentation(configuration.preference, summary: summary ?? nil)
        return Entry(date: .now, title: presentation.title, subtitle: presentation.subtitle, url: URL(string: "hermeswidget://launch/\(configuration.preference.rawValue)")!, imageName: presentation.imageName)
        #else
        if let id = configuration.destination?.id, let items = try? SharedStore.load(), let item = items.first(where: { $0.id.uuidString == id }) {
            return Entry(date: .now, title: "Open \(item.kind.rawValue.capitalized)", subtitle: item.name, url: item.url, imageName: "HermesBrand")
        }
        return Entry(date: .now, title: "Choose destination", subtitle: "Set up in Hermes", url: URL(string: "hermeswidget://setup")!, imageName: "HermesBrand")
        #endif
    }

    #if os(macOS)
    private func macPresentation(_ preference: MacChoice, summary: InstallationSummary?) -> (title: String, subtitle: String, imageName: String) {
        guard let summary else { return ("Open Hermes", "Set up in app", "HermesBrand") }
        switch preference {
        case .automatic:
            if summary.desktopFound { return ("Open Desktop", "Hermes Desktop", "HermesStaff") }
            if summary.cliFound { return ("Open Terminal", "Hermes CLI", "HermesCLI") }
            return summary.accessRequired ? ("Set up Hermes", "CLI access needed", "HermesBrand") : ("Get Hermes", "Set up on this Mac", "HermesBrand")
        case .desktop:
            return summary.desktopFound ? ("Open Desktop", "Hermes Desktop", "HermesStaff") : ("Set up Desktop", "Hermes Desktop not found", "HermesStaff")
        case .cli:
            if summary.cliFound { return ("Open Terminal", "Hermes CLI", "HermesCLI") }
            return summary.accessRequired ? ("Choose CLI", "Access needed", "HermesCLI") : ("Set up CLI", "Hermes CLI not found", "HermesCLI")
        }
    }
    #endif
}
struct LauncherView: View {
    let entry: Entry
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(entry.imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text("Hermes").font(.headline)
            }
            Spacer(minLength: 0)
            Text(entry.title).font(.title3.weight(.semibold))
            Text(entry.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.background.tertiary, for: .widget)
        .widgetURL(entry.url)
    }
}
@main
struct HermesWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "HermesLauncher", intent: Configuration.self, provider: Provider()) { LauncherView(entry: $0) }
            .configurationDisplayName("Hermes")
            .description("One tap to your Hermes.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

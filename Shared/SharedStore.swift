import Foundation
import HermesCore
import WidgetKit

enum BuildIdentity {
    static var label: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "v\(version) (\(build))"
    }
}

struct InstallationSummary: Codable, Equatable {
    let desktopFound: Bool
    let cliFound: Bool
    let accessRequired: Bool
}

enum SharedStore {
    static let group = "group.com.mlarrosa.HermesAgentWidget"
    static func load() throws -> [Destination] {
        guard let defaults = UserDefaults(suiteName: group) else { throw StoreError.unavailable }
        // Widget configuration runs out of process and can otherwise keep a stale
        // app-group defaults cache after the setup app saves a destination.
        defaults.synchronize()
        guard let data = defaults.data(forKey: "destinations.v1") else { return [] }
        return try JSONDecoder().decode([Destination].self, from: data)
    }
    static func save(_ items: [Destination]) throws {
        guard let defaults = UserDefaults(suiteName: group) else { throw StoreError.unavailable }
        defaults.set(try JSONEncoder().encode(items), forKey: "destinations.v1")
        defaults.synchronize()
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func loadInstallation() throws -> InstallationSummary? {
        guard let defaults = UserDefaults(suiteName: group) else { throw StoreError.unavailable }
        guard let data = defaults.data(forKey: "installation.v1") else { return nil }
        return try JSONDecoder().decode(InstallationSummary.self, from: data)
    }

    static func saveInstallation(_ summary: InstallationSummary) throws {
        guard let defaults = UserDefaults(suiteName: group) else { throw StoreError.unavailable }
        defaults.set(try JSONEncoder().encode(summary), forKey: "installation.v1")
        WidgetCenter.shared.reloadAllTimelines()
    }
    static func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
    enum StoreError: Error { case unavailable }
}

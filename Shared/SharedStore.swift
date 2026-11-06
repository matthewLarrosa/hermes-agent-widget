import Foundation
import HermesCore
import WidgetKit

struct InstallationSummary: Codable, Equatable {
    let desktopFound: Bool
    let cliFound: Bool
    let accessRequired: Bool
}

enum SharedStore {
    static let group = "group.com.mlarrosa.HermesAgentWidget"
    static func load() throws -> [Destination] {
        guard let defaults = UserDefaults(suiteName: group) else { throw StoreError.unavailable }
        guard let data = defaults.data(forKey: "destinations.v1") else { return [] }
        return try JSONDecoder().decode([Destination].self, from: data)
    }
    static func save(_ items: [Destination]) throws {
        guard let defaults = UserDefaults(suiteName: group) else { throw StoreError.unavailable }
        defaults.set(try JSONEncoder().encode(items), forKey: "destinations.v1")
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
    enum StoreError: Error { case unavailable }
}

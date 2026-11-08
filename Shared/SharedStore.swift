import Foundation
import HermesCore
import OSLog
import WidgetKit
#if os(macOS)
import Darwin
#endif

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
    private static let destinationsKey = "destinations.v1"
    private static let logger = Logger(subsystem: "com.mlarrosa.HermesAgentWidget", category: "shared-store")

    static func load() throws -> [Destination] {
        let fileURL = try destinationsFileURL()
        if let data = try? Data(contentsOf: fileURL) {
            logger.info("Loaded destinations from \(fileURL.path, privacy: .public)")
            return try JSONDecoder().decode([Destination].self, from: data)
        }

        // Migrate existing installs from shared defaults. App Intent option
        // queries can run with kCFPreferencesAnyUser, which macOS refuses for
        // App Group containers; a shared file avoids that execution-context bug.
        guard let defaults = UserDefaults(suiteName: group) else { throw StoreError.unavailable }
        defaults.synchronize()
        guard let data = defaults.data(forKey: destinationsKey) else { return [] }
        try data.write(to: fileURL, options: .atomic)
        logger.info("Migrated destinations to \(fileURL.path, privacy: .public)")
        return try JSONDecoder().decode([Destination].self, from: data)
    }

    static func save(_ items: [Destination]) throws {
        let data = try JSONEncoder().encode(items)
        let fileURL = try destinationsFileURL()
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
        logger.info("Saved \(items.count, privacy: .public) destinations to \(fileURL.path, privacy: .public)")

        // Keep defaults populated for compatibility with pre-file builds.
        guard let defaults = UserDefaults(suiteName: group) else { throw StoreError.unavailable }
        defaults.set(data, forKey: destinationsKey)
        defaults.synchronize()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func destinationsFileURL() throws -> URL {
        #if os(macOS)
        // Ad-hoc development signatures cannot use an App Group container
        // reliably. The widget has a narrow temporary sandbox exception for
        // this one shared development directory.
        guard let passwordEntry = getpwuid(getuid()),
              let homePointer = passwordEntry.pointee.pw_dir else {
            throw StoreError.unavailable
        }
        let userHome = URL(fileURLWithPath: String(cString: homePointer), isDirectory: true)
        let container = userHome
            .appending(path: "Library/Application Support/HermesAgentWidget", directoryHint: .isDirectory)
        #else
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: group
        ) else { throw StoreError.unavailable }
        #endif
        return container.appending(path: "destinations.v1.json")
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

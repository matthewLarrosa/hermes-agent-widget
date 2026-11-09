import Foundation
import HermesCore
import OSLog
import WidgetKit
#if os(macOS)
import Darwin
import SQLite3
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

enum HermesActivity: String, Equatable {
    case idle = "Idle"
    case thinking = "Thinking"
    case executing = "Executing"
    case needsAttention = "Needs Attention"
}

struct HermesStatus: Equatable {
    let isOnline: Bool
    let model: String
    let activity: HermesActivity
    let currentTask: String?
}

#if os(macOS)
enum HermesStatusReader {
    static func load(now: Date = .now) -> HermesStatus? {
        guard let home = realUserHomeURL() else { return nil }
        let databaseURL = home.appending(path: ".hermes/state.db")
        var database: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let database else {
            if database != nil { sqlite3_close(database) }
            return nil
        }
        defer { sqlite3_close(database) }

        let sql = """
            SELECT s.model,
                   COALESCE(s.title, ''),
                   s.ended_at,
                   COALESCE(s.handoff_error, ''),
                   COALESCE(m.role, ''),
                   COALESCE(m.finish_reason, ''),
                   COALESCE(m.timestamp, 0),
                   COALESCE((
                       SELECT content FROM messages
                       WHERE session_id = s.id AND active = 1 AND role = 'user'
                       ORDER BY timestamp DESC LIMIT 1
                   ), '')
            FROM sessions s
            LEFT JOIN messages m ON m.id = (
                SELECT id FROM messages
                WHERE session_id = s.id AND active = 1
                ORDER BY timestamp DESC LIMIT 1
            )
            WHERE s.source = 'cli'
            ORDER BY s.started_at DESC
            LIMIT 1
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }

        let model = text(statement, column: 0)
        let title = text(statement, column: 1)
        let isOnline = sqlite3_column_type(statement, 2) == SQLITE_NULL
        let handoffError = text(statement, column: 3)
        let role = text(statement, column: 4)
        let finishReason = text(statement, column: 5)
        let latestTimestamp = sqlite3_column_double(statement, 6)
        let latestPrompt = text(statement, column: 7)
        let age = max(0, now.timeIntervalSince1970 - latestTimestamp)

        let activity: HermesActivity
        if !isOnline {
            activity = .idle
        } else if !handoffError.isEmpty {
            activity = .needsAttention
        } else if age > 180 {
            activity = .idle
        } else if role == "user" {
            activity = .thinking
        } else if role == "tool" || finishReason == "tool_calls" {
            activity = .executing
        } else {
            activity = .idle
        }

        let taskSource = latestPrompt.isEmpty ? title : latestPrompt
        let currentTask = activity == .idle ? nil : conciseTask(taskSource)
        return HermesStatus(
            isOnline: isOnline,
            model: model,
            activity: activity,
            currentTask: currentTask
        )
    }

    private static func text(_ statement: OpaquePointer, column: Int32) -> String {
        guard let value = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: value)
    }

    private static func conciseTask(_ value: String) -> String? {
        let clean = value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        if clean.count <= 34 { return clean }
        return String(clean.prefix(33)).trimmingCharacters(in: .whitespaces) + "…"
    }

    private static func realUserHomeURL() -> URL? {
        guard let passwordEntry = getpwuid(getuid()),
              let homePointer = passwordEntry.pointee.pw_dir else { return nil }
        return URL(fileURLWithPath: String(cString: homePointer), isDirectory: true)
    }
}
#endif

enum SharedStore {
    static let group = "group.com.mlarrosa.HermesAgentWidget"
    private static let destinationsKey = "destinations.v1"
    private static let installationKey = "installation.v1"
    private static let logger = Logger(subsystem: "com.mlarrosa.HermesAgentWidget", category: "shared-store")

    static func load() throws -> [Destination] {
        let fileURL = try sharedFileURL("destinations.v1.json")
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
        let fileURL = try sharedFileURL("destinations.v1.json")
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

    private static func sharedFileURL(_ filename: String) throws -> URL {
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
        return container.appending(path: filename)
    }

    static func loadInstallation() throws -> InstallationSummary? {
        let fileURL = try sharedFileURL("installation.v1.json")
        if let data = try? Data(contentsOf: fileURL) {
            return try JSONDecoder().decode(InstallationSummary.self, from: data)
        }

        guard let defaults = UserDefaults(suiteName: group),
              let data = defaults.data(forKey: installationKey) else { return nil }
        try data.write(to: fileURL, options: .atomic)
        return try JSONDecoder().decode(InstallationSummary.self, from: data)
    }

    static func saveInstallation(_ summary: InstallationSummary) throws {
        let data = try JSONEncoder().encode(summary)
        let fileURL = try sharedFileURL("installation.v1.json")
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)

        guard let defaults = UserDefaults(suiteName: group) else { throw StoreError.unavailable }
        defaults.set(data, forKey: installationKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
    static func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
    enum StoreError: Error { case unavailable }
}

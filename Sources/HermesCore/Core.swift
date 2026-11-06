import Foundation
public enum LaunchPreference: String, Codable, Sendable, CaseIterable { case automatic, desktop, cli }
public enum LaunchAction: Equatable, Sendable { case desktop, cli, setup }
public enum LaunchResolver {
    public static func resolve(_ preference: LaunchPreference, desktop: Bool, cli: Bool) -> LaunchAction {
        switch preference {
        case .automatic: desktop ? .desktop : (cli ? .cli : .setup)
        case .desktop: desktop ? .desktop : .setup
        case .cli: cli ? .cli : .setup
        }
    }
}

#if os(macOS)
public enum LocalTargetState: Equatable, Sendable {
    case found(URL)
    case notFound
    case accessRequired
}

public struct HermesCLILocator {
    private let fileManager: FileManager
    private let homeDirectory: URL

    public init(
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
    }

    public func candidates(preferredURL: URL? = nil) -> [URL] {
        var values: [URL] = []
        if let preferredURL { values.append(preferredURL) }
        values.append(contentsOf: [
            homeDirectory.appending(path: ".local/bin/hermes"),
            URL(fileURLWithPath: "/opt/homebrew/bin/hermes"),
            URL(fileURLWithPath: "/usr/local/bin/hermes")
        ])
        return values
    }

    public func locate(preferredURL: URL? = nil) -> LocalTargetState {
        locate(in: candidates(preferredURL: preferredURL))
    }

    public func locate(in candidates: [URL]) -> LocalTargetState {
        var accessFailure = false
        for candidate in candidates {
            let hasSecurityScope = candidate.startAccessingSecurityScopedResource()
            defer {
                if hasSecurityScope { candidate.stopAccessingSecurityScopedResource() }
            }
            do {
                let values = try candidate.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .isExecutableKey,
                    .isReadableKey
                ])
                guard values.isRegularFile == true else { continue }
                guard values.isReadable == true, values.isExecutable == true else {
                    accessFailure = true
                    continue
                }
                return .found(candidate.resolvingSymlinksInPath())
            } catch CocoaError.fileReadNoPermission {
                accessFailure = true
            } catch {
                continue
            }
        }
        return accessFailure ? .accessRequired : .notFound
    }
}

public enum HermesCommandScript {
    public static func contents(executableURL: URL) -> String {
        let escapedPath = shellQuote(executableURL.path)
        return """
        #!/bin/zsh
        cd "$HOME"
        exec \(escapedPath) --cli
        """
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
#endif

public enum DestinationKind: String, Codable, CaseIterable, Sendable { case discord, telegram, dashboard }
public struct Destination: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: DestinationKind
    public var url: URL
    public init(id: UUID = UUID(), name: String, kind: DestinationKind, url: URL) {
        self.id = id; self.name = name; self.kind = kind; self.url = url
    }
}
public enum DestinationValidator {
    public enum ValidationError: Error, LocalizedError {
        case invalid
        public var errorDescription: String? { "Use a valid HTTPS conversation link without embedded credentials." }
    }
    public static func validate(_ text: String, kind: DestinationKind) throws -> URL {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme?.lowercased() == "https", let host = url.host?.lowercased(), !host.isEmpty, url.user == nil, url.password == nil else { throw ValidationError.invalid }
        switch kind {
        case .discord:
            guard host == "discord.com", url.pathComponents.count >= 4, url.pathComponents[1] == "channels" else { throw ValidationError.invalid }
        case .telegram:
            guard host == "t.me", url.pathComponents.count >= 2 else { throw ValidationError.invalid }
        case .dashboard: break
        }
        return url
    }
}

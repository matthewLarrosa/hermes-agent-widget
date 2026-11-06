#if os(macOS)
import AppKit
import Foundation
import HermesCore

struct MacInstallation {
    let desktopURL: URL?
    let cliState: LocalTargetState

    static func detect() -> MacInstallation {
        let desktop = locateDesktop()
        let preferred = PreferredCLIStore.resolveURL()
        let cliState: LocalTargetState
        if let preferred {
            // User explicitly selected this path. Terminal executes it outside the app sandbox.
            cliState = .found(preferred)
        } else if case .notFound = HermesCLILocator().locate() {
            // The sandbox can hide ~/.local even when Hermes exists there.
            cliState = .accessRequired
        } else {
            cliState = HermesCLILocator().locate()
        }
        return MacInstallation(desktopURL: desktop, cliState: cliState)
    }

    private static func locateDesktop() -> URL? {
        if let value = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.nousresearch.hermes"),
           isHermesDesktop(value) {
            return value
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        for candidate in [
            URL(fileURLWithPath: "/Applications/Hermes.app"),
            home.appending(path: "Applications/Hermes.app")
        ] where isHermesDesktop(candidate) {
            return candidate
        }
        return nil
    }

    private static func isHermesDesktop(_ url: URL) -> Bool {
        guard let bundle = Bundle(url: url) else { return false }
        return bundle.bundleIdentifier == "com.nousresearch.hermes"
    }
}

enum PreferredCLIStore {
    private static let key = "preferredCLI.path.v2"

    @MainActor static func chooseExecutable() throws -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose Hermes CLI"
        panel.message = "Select the Hermes executable."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin")
        panel.nameFieldStringValue = "hermes"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        UserDefaults.standard.set(url.path, forKey: key)
        return url
    }

    static func resolveURL() -> URL? {
        guard let path = UserDefaults.standard.string(forKey: key), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }
}

enum MacLauncher {
    enum LaunchError: LocalizedError {
        case desktopFailed
        case cliScriptFailed
        case terminalFailed(String)

        var errorDescription: String? {
            switch self {
            case .desktopFailed: "Could not open Hermes Desktop."
            case .cliScriptFailed: "Could not prepare the Hermes CLI launcher."
            case let .terminalFailed(message): "Could not open Hermes CLI in Terminal: \(message)"
            }
        }
    }

    static func openDesktop(_ url: URL, completion: @escaping @MainActor (Error?) -> Void) {
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
            Task { @MainActor in completion(error) }
        }
    }

    static func openCLI(_ executableURL: URL) throws {
        let fileManager = FileManager.default
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appending(path: "HermesAgentWidget", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        let launcher = support.appending(path: "Open Hermes CLI.command")
        do {
            try HermesCommandScript.contents(executableURL: executableURL).write(to: launcher, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: launcher.path)
        } catch {
            throw LaunchError.cliScriptFailed
        }
        guard NSWorkspace.shared.open(launcher) else {
            throw LaunchError.terminalFailed(launcher.path)
        }
    }
}
#endif

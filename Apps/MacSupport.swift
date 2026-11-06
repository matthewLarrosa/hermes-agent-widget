#if os(macOS)
import AppKit
import Foundation
import HermesCore

struct MacInstallation {
    let desktopURL: URL?
    let cliState: LocalTargetState

    static func detect() -> MacInstallation {
        let desktop = locateDesktop()
        let preferred = PreferredCLIStore.resolveBookmark()
        let cliState = HermesCLILocator().locate(preferredURL: preferred)
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
    private static let key = "preferredCLI.bookmark.v1"

    @MainActor static func chooseExecutable() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose Hermes CLI"
        panel.message = "Select the Hermes executable."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: key)
            return url
        } catch {
            return nil
        }
    }

    static func resolveBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        if stale, let renewed = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(renewed, forKey: key)
        }
        return url
    }
}

enum MacLauncher {
    enum LaunchError: LocalizedError {
        case desktopFailed
        case cliScriptFailed
        case terminalFailed

        var errorDescription: String? {
            switch self {
            case .desktopFailed: "Could not open Hermes Desktop."
            case .cliScriptFailed: "Could not prepare the Hermes CLI launcher."
            case .terminalFailed: "Could not open Hermes CLI in Terminal."
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
        guard NSWorkspace.shared.open(launcher) else { throw LaunchError.terminalFailed }
    }
}
#endif

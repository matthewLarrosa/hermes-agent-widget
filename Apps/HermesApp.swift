import SwiftUI
import HermesCore

@main
struct HermesApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        #if os(macOS)
        // AppKit delegate owns setup windows so launch URLs can hand off to Hermes
        // without SwiftUI creating a companion window first.
        Settings { EmptyView() }
        #else
        WindowGroup { ContentView() }
        #endif
    }
}

struct ContentView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var destinations: [Destination] = []
    @State private var editingID: UUID?
    @State private var name = ""
    @State private var address = ""
    @State private var kind = DestinationKind.discord
    @State private var error: String?
    #if os(macOS)
    @State private var installation = MacInstallation.detect()
    #endif

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image("HermesAgent")
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .foregroundStyle(.primary)
                            .frame(width: 64, height: 64)
                        VStack(alignment: .leading) {
                            Text("Hermes Agent Widget").font(.headline)
                            Text("One tap to your Hermes.").foregroundStyle(.secondary)
                            Text(BuildIdentity.label)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                #if os(macOS)
                localHermesSection
                #endif
                destinationsSection
                destinationEditor
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                Section {
                    Text("Add Hermes from the widget gallery. Edit each widget to choose what it opens. No server connection or tokens needed.")
                    Link("Get Hermes", destination: installURL)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Hermes")
            .task {
                loadDestinations()
                SharedStore.reloadWidgets()
                #if os(macOS)
                refreshInstallation()
                #endif
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                loadDestinations()
                SharedStore.reloadWidgets()
            }
            #if !os(macOS)
            .onOpenURL(perform: handleInternalURL)
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 540)
        #endif
    }

    #if os(macOS)
    private var localHermesSection: some View {
        Section("On this Mac") {
            LabeledContent("Hermes Desktop", value: installation.desktopURL == nil ? "Not found" : "Installed")
            LabeledContent("Hermes CLI", value: cliStatusLabel)
            HStack {
                Button("Open Desktop") { _ = launch(.desktop) }
                    .disabled(installation.desktopURL == nil)
                Button("Open CLI") { _ = launch(.cli) }
                    .disabled(cliURL == nil)
                Button("Check again") { refreshInstallation() }
            }
            Button(cliURL == nil ? "Choose Hermes CLI…" : "Change Hermes CLI…") {
                do {
                    guard try PreferredCLIStore.chooseExecutable() != nil else { return }
                    refreshInstallation()
                    if cliURL == nil {
                        error = "Hermes was selected, but access could not be restored. Try choosing it again."
                    }
                } catch {
                    self.error = "Could not save access to Hermes: \(error.localizedDescription)"
                }
            }
            if cliURL == nil {
                Text("macOS may block automatic access to ~/.local/bin. Choose the Hermes executable once to grant access. On this Mac it is usually ~/.local/bin/hermes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Each widget can independently choose a saved destination, Hermes Desktop, or Hermes CLI.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var cliURL: URL? {
        guard case let .found(url) = installation.cliState else { return nil }
        return url
    }

    private var cliStatusLabel: String {
        switch installation.cliState {
        case .found: "Installed"
        case .notFound: "Not found"
        case .accessRequired: "Access needed"
        }
    }
    #endif

    private var destinationsSection: some View {
        Section("Your destinations") {
            if destinations.isEmpty {
                Text("No destinations yet").foregroundStyle(.secondary)
            }
            ForEach(destinations) { item in
                HStack {
                    VStack(alignment: .leading) {
                        Text(item.name)
                        Text(item.kind.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Link("Test", destination: item.url)
                    Button("Edit") { beginEditing(item) }
                    Button("Delete", role: .destructive) {
                        save(destinations.filter { $0.id != item.id })
                        if editingID == item.id { clearEditor() }
                    }
                }
            }
        }
    }

    private var destinationEditor: some View {
        Section(editingID == nil ? "Add destination" : "Edit destination") {
            TextField("Name", text: $name)
            Picker("Open with", selection: $kind) {
                ForEach(DestinationKind.allCases, id: \.self) {
                    Text($0.rawValue.capitalized).tag($0)
                }
            }
            Label("Where to find this link", systemImage: "info.circle")
                .font(.caption.weight(.semibold))
                .help(destinationHelp)
            Text(destinationHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("HTTPS conversation link", text: $address)
            HStack {
                Button("Test link") { validate { openURL($0) } }
                Button(editingID == nil ? "Save destination" : "Save changes") {
                    validate(saveEditor)
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if editingID != nil { Button("Cancel", action: clearEditor) }
            }
        }
    }

    private var destinationHelp: String {
        switch kind {
        case .discord:
            "Open the Discord channel or DM Hermes uses, then copy its link. Expected format: https://discord.com/channels/server-or-@me/channel-id"
        case .telegram:
            "Open the Hermes bot or chat in Telegram and copy its public t.me link. Example: https://t.me/hermes_bot"
        case .dashboard:
            "Paste the full HTTPS URL of your Hermes web dashboard or chat page. Example: https://hermes.example.com/chat"
        }
    }

    private var installURL: URL {
        URL(string: "https://hermes-agent.nousresearch.com/docs/getting-started/installation")!
    }

    private func loadDestinations() {
        do { destinations = try SharedStore.load() }
        catch { self.error = "Could not read saved destinations. Check App Group signing." }
    }

    private func validate(_ action: (URL) -> Void) {
        do {
            let url = try DestinationValidator.validate(address, kind: kind)
            error = nil
            action(url)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func saveEditor(url: URL) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var items = destinations
        if let editingID, let index = items.firstIndex(where: { $0.id == editingID }) {
            items[index] = Destination(id: editingID, name: trimmedName, kind: kind, url: url)
        } else {
            items.append(Destination(name: trimmedName, kind: kind, url: url))
        }
        save(items)
        clearEditor()
    }

    private func beginEditing(_ destination: Destination) {
        editingID = destination.id
        name = destination.name
        kind = destination.kind
        address = destination.url.absoluteString
        error = nil
    }

    private func clearEditor() {
        editingID = nil
        name = ""
        address = ""
        kind = .discord
    }

    private func save(_ items: [Destination]) {
        do {
            try SharedStore.save(items)
            destinations = items
            error = nil
        } catch {
            self.error = "Could not save destinations. Check App Group signing."
        }
    }

    private func handleInternalURL(_ url: URL) {
        guard url.scheme == "hermeswidget" else {
            openURL(url)
            return
        }
    }

    #if os(macOS)
    private func refreshInstallation() {
        installation = .detect()
        let accessRequired: Bool
        if case .accessRequired = installation.cliState { accessRequired = true } else { accessRequired = false }
        do {
            try SharedStore.saveInstallation(.init(
                desktopFound: installation.desktopURL != nil,
                cliFound: cliURL != nil,
                accessRequired: accessRequired
            ))
            error = nil
        } catch {
            self.error = "Could not share installation state with the widget. Check App Group signing."
        }
    }

    @discardableResult
    private func launch(_ preference: LaunchPreference) -> Bool {
        refreshInstallation()
        let action = LaunchResolver.resolve(
            preference,
            desktop: installation.desktopURL != nil,
            cli: cliURL != nil
        )
        switch action {
        case .desktop:
            guard let desktopURL = installation.desktopURL else { return false }
            MacLauncher.openDesktop(desktopURL) { failure in
                if failure != nil { error = "Could not open Hermes Desktop." }
            }
            return true
        case .cli:
            guard let cliURL else { return false }
            do {
                try MacLauncher.openCLI(cliURL)
                error = nil
                return true
            } catch {
                self.error = error.localizedDescription
                return false
            }
        case .setup:
            if preference == .desktop, cliURL != nil {
                error = "Hermes Desktop was not found. Hermes CLI is available; choose it explicitly or install Desktop."
            } else if preference == .cli, installation.desktopURL != nil {
                error = "Hermes CLI was not found. Hermes Desktop is available; choose it explicitly or select a CLI executable."
            } else if case .accessRequired = installation.cliState {
                error = "Hermes CLI access is needed. Choose the executable in this app."
            } else {
                openURL(installURL)
            }
            return false
        }
    }
    #endif
}

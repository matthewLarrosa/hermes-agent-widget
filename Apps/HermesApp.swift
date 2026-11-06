import SwiftUI
import HermesCore

@main
struct HermesApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

struct ContentView: View {
    @Environment(\.openURL) private var openURL
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
                        Image("HermesBrand")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading) {
                            Text("Hermes Agent Widget").font(.headline)
                            Text("One tap to your Hermes.").foregroundStyle(.secondary)
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
                #if os(macOS)
                refreshInstallation()
                #endif
            }
            .onOpenURL(perform: handleInternalURL)
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
                Button("Open Desktop") { launch(.desktop) }
                    .disabled(installation.desktopURL == nil)
                Button("Open CLI") { launch(.cli) }
                    .disabled(cliURL == nil)
                Button("Check again") { refreshInstallation() }
            }
            if cliURL == nil {
                Button("Choose Hermes CLI…") {
                    if PreferredCLIStore.chooseExecutable() == nil {
                        error = "No executable was selected or its access could not be saved."
                    }
                    refreshInstallation()
                }
            }
            Text("Each widget can independently choose Automatic, Desktop, or CLI.")
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
        guard url.scheme == "hermeswidget" else { return }
        #if os(macOS)
        guard url.host == "launch", let preference = LaunchPreference(rawValue: String(url.path.dropFirst())) else { return }
        launch(preference)
        #endif
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

    private func launch(_ preference: LaunchPreference) {
        refreshInstallation()
        let action = LaunchResolver.resolve(
            preference,
            desktop: installation.desktopURL != nil,
            cli: cliURL != nil
        )
        switch action {
        case .desktop:
            guard let desktopURL = installation.desktopURL else { return }
            MacLauncher.openDesktop(desktopURL) { failure in
                if failure != nil { error = "Could not open Hermes Desktop." }
            }
        case .cli:
            guard let cliURL else { return }
            do {
                try MacLauncher.openCLI(cliURL)
                error = nil
            } catch {
                self.error = error.localizedDescription
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
        }
    }
    #endif
}

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
    @State private var showingEditor = false
    #if os(macOS)
    @State private var installation = MacInstallation.detect()
    #endif

    var body: some View {
        setupContent
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

    @ViewBuilder
    private var setupContent: some View {
        #if os(macOS)
        macSetup
        #else
        iosSetup
        #endif
    }

    #if os(macOS)
    private var macSetup: some View {
        ScrollView {
            VStack(spacing: 20) {
                setupHeader
                HStack(alignment: .top, spacing: 20) {
                    VStack(spacing: 20) {
                        macInstallationCard
                        macDestinationEditor
                    }
                    .frame(maxWidth: .infinity, alignment: .top)

                    VStack(spacing: 20) {
                        macDestinationsCard
                        widgetInstructionsCard
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 880, minHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var setupHeader: some View {
        HStack(spacing: 16) {
            Image("HermesAgent")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(.primary)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text("Hermes Agent Widget")
                    .font(.title3.weight(.semibold))
                Text("One tap to your Hermes.")
                    .foregroundStyle(.secondary)
                Text(BuildIdentity.label)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.separator.opacity(0.55), lineWidth: 1)
        }
    }

    private var macInstallationCard: some View {
        setupGroup("On this Mac") {
            LabeledContent("Hermes Desktop", value: installation.desktopURL == nil ? "Not found" : "Installed")
            Divider()
            LabeledContent("Hermes CLI", value: cliStatusLabel)
            HStack {
                Button("Open Desktop") { _ = launch(.desktop) }
                    .disabled(installation.desktopURL == nil)
                Button("Open CLI") { _ = launch(.cli) }
                    .disabled(cliURL == nil)
                Button("Check again") { refreshInstallation() }
            }
            Divider()
            Button(cliURL == nil ? "Choose Hermes CLI…" : "Change Hermes CLI…") {
                chooseCLI()
            }
            Text("Each widget chooses Saved Destination, Hermes Desktop, or Hermes CLI.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var macDestinationEditor: some View {
        setupGroup(editingID == nil ? "Add destination" : "Edit destination") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("Name")
                    TextField("Personal Hermes", text: $name)
                }
                GridRow {
                    Text("Open with")
                    Picker("", selection: $kind) {
                        ForEach(DestinationKind.allCases, id: \.self) {
                            Text($0.rawValue.capitalized).tag($0)
                        }
                    }
                    .labelsHidden()
                }
                GridRow(alignment: .top) {
                    Text("Link")
                    TextField("HTTPS conversation link", text: $address)
                }
            }
            Text(destinationHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Test link") { validate { openURL($0) } }
                Button(editingID == nil ? "Save destination" : "Save changes") {
                    validate { url in
                        saveEditor(url: url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if editingID != nil {
                    Button("Cancel", action: clearEditor)
                }
            }
        }
    }

    private var macDestinationsCard: some View {
        setupGroup("Your destinations") {
            if destinations.isEmpty {
                Text("No destinations yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(destinations) { item in
                HStack(spacing: 12) {
                    Image(systemName: destinationSymbol(item.kind))
                        .frame(width: 28, height: 28)
                        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 7))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).lineLimit(1)
                        Text(item.kind.rawValue.capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Link("Test", destination: item.url)
                    Button("Edit") { beginEditing(item) }
                    Button("Delete", role: .destructive) {
                        delete(item)
                    }
                }
                if item.id != destinations.last?.id { Divider() }
            }
        }
    }

    private var widgetInstructionsCard: some View {
        setupGroup("Add the widget") {
            Text("Add Hermes from the widget gallery. Edit each widget to choose what it opens.")
            Text("No server connection or tokens needed.")
                .foregroundStyle(.secondary)
            Link("Get Hermes", destination: installURL)
        }
    }

    private func setupGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 12, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.separator.opacity(0.55), lineWidth: 1)
                }
        }
    }
    #else
    private var iosSetup: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image("HermesAgent")
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .foregroundStyle(.primary)
                            .frame(width: 48, height: 48)
                        VStack(alignment: .leading) {
                            Text("Hermes Agent Widget").font(.headline)
                            Text("One tap to your Hermes.").foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Saved destinations") {
                    if destinations.isEmpty {
                        Text("No destinations yet").foregroundStyle(.secondary)
                    }
                    ForEach(destinations) { item in
                        Button {
                            beginEditing(item)
                            showingEditor = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: destinationSymbol(item.kind))
                                    .frame(width: 30, height: 30)
                                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 7))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name).foregroundStyle(.primary)
                                    Text(item.kind.rawValue.capitalized)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        save(destinations.enumerated().filter { !offsets.contains($0.offset) }.map(\.element))
                    }
                }
                Section("Add Widget") {
                    Text("Touch and hold the Home Screen, tap Add, then choose Hermes.")
                    Text("Edit the widget to choose one saved destination.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Hermes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add") {
                        clearEditor()
                        showingEditor = true
                    }
                }
            }
            .sheet(isPresented: $showingEditor) {
                iosDestinationEditor
            }
        }
    }

    private var iosDestinationEditor: some View {
        NavigationStack {
            Form {
                Section("Destination") {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $kind) {
                        ForEach(DestinationKind.allCases, id: \.self) {
                            Text($0.rawValue.capitalized).tag($0)
                        }
                    }
                    TextField("HTTPS conversation link", text: $address, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section {
                    Text(destinationHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Button("Test link") { validate { openURL($0) } }
                    Button(editingID == nil ? "Save destination" : "Save changes") {
                        validate { url in
                            saveEditor(url: url)
                            showingEditor = false
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let editingID, let item = destinations.first(where: { $0.id == editingID }) {
                    Section {
                        Button("Delete destination", role: .destructive) {
                            delete(item)
                            showingEditor = false
                        }
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle(editingID == nil ? "Add Destination" : "Edit Destination")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingEditor = false
                        clearEditor()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        validate { url in
                            saveEditor(url: url)
                            showingEditor = false
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    #endif

    #if os(macOS)
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

    private func destinationSymbol(_ kind: DestinationKind) -> String {
        switch kind {
        case .discord: "number"
        case .telegram: "paperplane.fill"
        case .dashboard: "rectangle.3.group"
        }
    }

    private func delete(_ destination: Destination) {
        save(destinations.filter { $0.id != destination.id })
        if editingID == destination.id { clearEditor() }
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
    private func chooseCLI() {
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

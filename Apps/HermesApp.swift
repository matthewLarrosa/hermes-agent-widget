import SwiftUI
import HermesCore

@main
struct HermesApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}
struct ContentView: View {
    @Environment(\.openURL) private var openURL
    @State private var destinations: [Destination] = []
    @State private var name = ""
    @State private var address = ""
    @State private var kind = DestinationKind.discord
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                #if os(macOS)
                Section("On this Mac") {
                    Button("Open Hermes Desktop") { launch(.desktop) }
                    Button("Open Hermes CLI") { launch(.cli) }
                    Text("CLI launch is a setup fallback until signed Terminal handoff is verified.").font(.caption)
                }
                #endif
                Section("Your destinations") {
                    ForEach(destinations) { item in
                        HStack {
                            Link(item.name, destination: item.url)
                            Spacer()
                            Button("Delete", role: .destructive) { save(destinations.filter { $0.id != item.id }) }
                        }
                    }
                }
                Section("Add destination") {
                    TextField("Name", text: $name)
                    Picker("Open with", selection: $kind) {
                        ForEach(DestinationKind.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    TextField("HTTPS conversation link", text: $address)
                    Button("Test link") { validate { openURL($0) } }
                    Button("Save destination") {
                        validate { url in
                            save(destinations + [Destination(name: name.trimmingCharacters(in: .whitespacesAndNewlines), kind: kind, url: url)])
                        }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section {
                    Text("Add Hermes from the widget gallery. Edit each widget to choose its destination. No server connection or tokens needed.")
                    Link("Get Hermes", destination: URL(string: "https://hermes-agent.nousresearch.com/docs/getting-started/installation")!)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Hermes")
            .task { do { destinations = try SharedStore.load() } catch { self.error = "Could not read saved destinations." } }
            .onOpenURL { url in
                #if os(macOS)
                guard url.scheme == "hermeswidget", url.host == "launch", let preference = LaunchPreference(rawValue: String(url.path.dropFirst())) else { return }
                launch(preference)
                #endif
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 480)
        #endif
    }
    private func validate(_ action: (URL) -> Void) {
        do { let url = try DestinationValidator.validate(address, kind: kind); error = nil; action(url) }
        catch { self.error = error.localizedDescription }
    }
    private func save(_ items: [Destination]) {
        do { try SharedStore.save(items); destinations = items; error = nil }
        catch { self.error = "Could not save destinations. Check App Group signing." }
    }
    #if os(macOS)
    private func launch(_ preference: LaunchPreference) {
        let desktop = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.nousresearch.hermes")
        // Sandbox discovery and signed interactive launch require explicit validation.
        switch LaunchResolver.resolve(preference, desktop: desktop != nil, cli: false) {
        case .desktop:
            if let desktop { NSWorkspace.shared.openApplication(at: desktop, configuration: .init()) { _, failure in
                if failure != nil { Task { @MainActor in self.error = "Could not open Hermes Desktop." } }
            } }
        case .cli, .setup:
            error = preference == .cli ? "CLI handoff not yet verified. Open Terminal and run hermes." : "Hermes Desktop not found. Use Get Hermes to install, or open your existing CLI in Terminal."
        }
    }
    #endif
}

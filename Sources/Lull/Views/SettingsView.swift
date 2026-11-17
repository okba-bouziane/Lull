import SwiftUI
import LullCore

struct SettingsView: View {
    @EnvironmentObject var monitor: Monitor
    @Binding var route: Route
    @AppStorage(Prefs.menuBarShows) private var menuBarShows = "icon"
    @AppStorage(Prefs.alertsOn) private var alertsOn = true
    @AppStorage(Prefs.alertThreshold) private var threshold = 100.0
    @AppStorage(Prefs.alertMinutes) private var minutes = 3.0
    @AppStorage(Prefs.backgroundInterval) private var interval = 10.0
    @State private var openAtLogin = LoginItem.isEnabled

    var body: some View {
        VStack(spacing: 0) {
            NavHeader(title: "Settings") { route = .main }
            Divider()
            Form {
                Section {
                    Toggle("Open at login", isOn: Binding(get: { openAtLogin }, set: { on in
                        LoginItem.set(on)
                        openAtLogin = LoginItem.isEnabled
                    }))
                    Picker("Menu bar shows", selection: $menuBarShows) {
                        Text("Icon only").tag("icon")
                        Text("CPU %").tag("cpu")
                        Text("Memory %").tag("memory")
                    }
                }

                Section {
                    Toggle("Warn me about heavy apps", isOn: $alertsOn)
                    Picker("When CPU stays above", selection: $threshold) {
                        Text("50%").tag(50.0)
                        Text("100%").tag(100.0)
                        Text("200%").tag(200.0)
                    }
                    .disabled(!alertsOn)
                    Picker("For at least", selection: $minutes) {
                        Text("2 minutes").tag(2.0)
                        Text("3 minutes").tag(3.0)
                        Text("5 minutes").tag(5.0)
                        Text("10 minutes").tag(10.0)
                    }
                    .disabled(!alertsOn)
                } header: {
                    Text("Alerts")
                } footer: {
                    Text("100% is one full CPU core. The menu bar icon also turns orange.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                }

                Section {
                    Picker("Check every", selection: $interval) {
                        Text("5 seconds").tag(5.0)
                        Text("10 seconds").tag(10.0)
                        Text("30 seconds").tag(30.0)
                        Text("1 minute").tag(60.0)
                    }
                } header: {
                    Text("While closed")
                } footer: {
                    Text("Longer saves more battery. With the panel open, Lull refreshes every 2 seconds.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                }

                Section("Never quit") {
                    if monitor.protected.isEmpty {
                        Text("Right-click any app and choose Never Quit to keep it out of Free Up Memory.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    } else {
                        ForEach(monitor.protected.sorted(), id: \.self) { id in
                            HStack {
                                Text(monitor.protectedName(id))
                                Spacer()
                                Button { monitor.toggleProtected(id) } label: {
                                    Image(systemName: "minus.circle.fill").symbolRenderingMode(.hierarchical)
                                }
                                .buttonStyle(.borderless).help("Allow quitting")
                            }
                        }
                    }
                }

                Section {
                    Button("Manage Login Items…") { SystemLinks.openLoginItems() }
                    Button("Quit Lull") { NSApp.terminate(nil) }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Text("Lull itself is using \(Format.cpu(monitor.selfUsage.cpu)) CPU and \(Format.bytes(monitor.selfUsage.memory)) · v\(version)")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
                .padding(.top, 4).padding(.bottom, 10)
        }
        .onAppear { openAtLogin = LoginItem.isEnabled }
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

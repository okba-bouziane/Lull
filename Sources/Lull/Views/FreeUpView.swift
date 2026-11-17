import SwiftUI
import LullCore

struct FreeUpView: View {
    @EnvironmentObject var monitor: Monitor
    @Binding var route: Route
    @State private var apps: [AppGroup] = []
    @State private var background: [AppGroup] = []
    @State private var selected: Set<String> = []
    @State private var loaded = false
    @State private var result: (count: Int, before: UInt64)?

    var body: some View {
        VStack(spacing: 0) {
            NavHeader(title: "Free Up Memory") { route = .main }
            Divider()
            if let result { done(result) } else { picker }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        // Freeze the list while choosing, so rows don't move under the cursor.
        apps = monitor.freeUpApps
        background = monitor.freeUpBackground
        // Pre-tick only apps with no open window: they are running for nothing.
        selected = Set(apps.filter { $0.windows == 0 }.map(\.id))
    }

    private var picker: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Quit apps you're not using right now. Any app with unsaved work will ask before it closes.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

                    section("Apps not in use", apps, empty: "No other apps are open.")
                    if !background.isEmpty {
                        section("Running in the background", background, empty: "")
                        Text("Some of these may be tools you rely on, like a VPN, cloud sync or a battery manager.")
                            .font(.system(size: 11)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
            }
            Divider()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(selected.isEmpty ? "Nothing selected" : "\(selected.count) selected")
                        .font(.system(size: 12, weight: .medium))
                    Text("Frees about \(Format.bytes(selectedMemory))")
                        .font(.system(size: 11)).foregroundStyle(.secondary).opacity(selected.isEmpty ? 0 : 1)
                }
                Spacer()
                Button(action: quitSelected) {
                    Text(selected.count == 1 ? "Quit 1 App" : "Quit \(selected.count) Apps").padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent).tint(.brand).controlSize(.large)
                .disabled(selected.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
        }
    }

    private var selectedMemory: UInt64 {
        (apps + background).filter { selected.contains($0.id) }.reduce(0) { $0 + $1.memory }
    }

    private func section(_ title: String, _ items: [AppGroup], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                if items.count > 1 {
                    let all = items.allSatisfy { selected.contains($0.id) }
                    Button(all ? "Select None" : "Select All") {
                        if all { items.forEach { selected.remove($0.id) } } else { items.forEach { selected.insert($0.id) } }
                    }
                    .buttonStyle(.link).font(.system(size: 11))
                }
            }
            if items.isEmpty {
                Text(empty).font(.system(size: 12)).foregroundStyle(.tertiary).padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, g in
                        if i > 0 { Divider().padding(.leading, 64) }
                        checkRow(g)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
            }
        }
    }

    private func checkRow(_ g: AppGroup) -> some View {
        let on = Binding(get: { selected.contains(g.id) },
                         set: { if $0 { selected.insert(g.id) } else { selected.remove(g.id) } })
        return HStack(spacing: 10) {
            Toggle("", isOn: on).toggleStyle(.checkbox).labelsHidden()
            AppIconView(group: g, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(g.name).font(.system(size: 13)).lineLimit(1)
                Text(note(g)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(Format.bytes(g.memory)).font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture { on.wrappedValue.toggle() }
    }

    private func note(_ g: AppGroup) -> String {
        if g.kind == .background { return g.restartsItself ? "Restarts itself" : "Background" }
        guard let w = g.windows else { return "" }
        return w == 0 ? "No open windows" : w == 1 ? "1 window open" : "\(w) windows open"
    }

    private func quitSelected() {
        let chosen = (apps + background).filter { selected.contains($0.id) }
        let before = monitor.system.memoryUsed
        chosen.forEach { monitor.quit($0) }
        withAnimation(.easeOut(duration: 0.2)) { result = (chosen.count, before) }
    }

    private func done(_ r: (count: Int, before: UInt64)) -> some View {
        let now = monitor.system.memoryUsed
        let freed = r.before > now ? r.before - now : 0
        return VStack(spacing: 10) {
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.system(size: 40)).foregroundStyle(Color.brand)
            Text(r.count == 1 ? "Asked 1 app to quit" : "Asked \(r.count) apps to quit")
                .font(.system(size: 15, weight: .semibold))
            Text(freed > 50 * 1_048_576 ? "\(Format.bytes(freed)) of memory freed so far."
                                        : "Memory frees up over the next few seconds.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            HStack(spacing: 18) {
                metric("Before", r.before)
                Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                metric("Now", now)
            }
            .padding(.top, 8)
            Spacer()
            Button("Done") { route = .main }
                .buttonStyle(.borderedProminent).tint(.brand).controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity)
    }

    private func metric(_ title: String, _ bytes: UInt64) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(Format.bytes(bytes)).font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
        }
    }
}

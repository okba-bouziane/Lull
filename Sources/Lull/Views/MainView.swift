import SwiftUI
import LullCore

struct MainView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case top = "Top", apps = "Apps", background = "Background"
        var id: String { rawValue }
    }

    @EnvironmentObject var monitor: Monitor
    @Binding var route: Route
    @AppStorage(Prefs.sortBy) private var sortBy = "cpu"
    @State private var tab: Tab = .top

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
            HStack(spacing: 10) { cpuCard; memoryCard }.padding(.horizontal, 14)
            pressureLine.padding(.horizontal, 16).padding(.top, 9)
            if let hog = monitor.hog {
                HogBanner(group: hog).padding(.horizontal, 14).padding(.top, 10)
            }
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { t in Text(label(for: t)).tag(t) }
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding(.horizontal, 14).padding(.top, 12)
            columnHeader.padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 4)
            Divider().padding(.horizontal, 14)
            list
            Divider()
            footer.padding(.horizontal, 14).padding(.vertical, 11)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("Lull").font(.system(size: 15, weight: .semibold))
                Text(statusLine).font(.system(size: 12)).foregroundStyle(statusColor).lineLimit(1)
            }
            Spacer()
            Button { route = .settings } label: {
                Image(systemName: "gearshape").font(.system(size: 14))
            }
            .buttonStyle(.borderless).help("Settings")
        }
    }

    private var statusLine: String {
        let s = monitor.system
        if s.pressure == .critical { return "Memory is almost full" }
        if s.pressure == .warning { return "Memory is under pressure" }
        if let hog = monitor.hog { return "\(hog.name) is working hard" }
        if s.cpu >= 85 { return "Your Mac is very busy" }
        if s.cpu >= 50 { return "Your Mac is busy" }
        return "Running smoothly"
    }

    private var statusColor: Color {
        let s = monitor.system
        if s.pressure != .normal { return s.pressure.color }
        if monitor.hog != nil || s.cpu >= 85 { return .orange }
        return .secondary
    }

    private var cpuCard: some View {
        StatCard(title: "CPU", value: "\(Int(monitor.system.cpu.rounded()))", unit: "%",
                 detail: "\(monitor.system.cores) cores", values: monitor.cpuHistory, maxValue: 100, tint: .brand)
    }

    private var memoryCard: some View {
        let s = monitor.system
        let gb = Double(s.memoryUsed) / 1_073_741_824
        return StatCard(title: "Memory", value: String(format: "%.1f", gb), unit: "GB",
                        detail: "of \(Int((Double(s.memoryTotal) / 1_073_741_824).rounded())) GB",
                        values: monitor.memoryHistory, maxValue: 1, tint: s.pressure.color)
    }

    private var pressureLine: some View {
        HStack(spacing: 6) {
            Circle().fill(monitor.system.pressure.color).frame(width: 7, height: 7)
            Text("Memory pressure \(monitor.system.pressure.label.lowercased())")
            Spacer()
            if monitor.system.swapUsed > 64 * 1_048_576 {
                Text("Swap \(Format.bytes(monitor.system.swapUsed))")
                    .help("Memory moved to disk because RAM was full. High swap makes a Mac feel slow.")
            }
        }
        .font(.system(size: 11)).foregroundStyle(.secondary)
    }

    // MARK: List

    private func label(for t: Tab) -> String {
        switch t {
        case .top: return "Top"
        case .apps: return "Apps \(monitor.groups.filter { $0.kind == .app }.count)"
        case .background: return "Background \(monitor.groups.filter { $0.kind == .background }.count)"
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text(tab == .top ? "Using the most" : "Name").foregroundStyle(.tertiary)
            Spacer()
            sortButton("CPU", key: "cpu").frame(width: 46, alignment: .trailing)
            sortButton("Memory", key: "memory").frame(width: 60, alignment: .trailing)
            Color.clear.frame(width: 26, height: 1)
        }
        .font(.system(size: 11, weight: .medium))
    }

    private func sortButton(_ title: String, key: String) -> some View {
        Button { sortBy = key } label: {
            HStack(spacing: 2) {
                Text(title)
                if sortBy == key { Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)) }
            }
            .foregroundStyle(sortBy == key ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    private var rows: [AppGroup] {
        var g: [AppGroup]
        switch tab {
        case .top: g = monitor.groups
        case .apps: g = monitor.groups.filter { $0.kind == .app }
        case .background: g = monitor.groups.filter { $0.kind == .background }
        }
        g.sort { sortBy == "memory" ? ($0.memory, $0.cpu) > ($1.memory, $1.cpu) : ($0.cpu, $0.memory) > ($1.cpu, $1.memory) }
        return tab == .top ? Array(g.prefix(25)) : g
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                let items = rows
                if items.isEmpty {
                    Text(monitor.groups.isEmpty ? "Reading your apps…" : "Nothing here right now")
                        .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 40)
                }
                ForEach(items) { g in
                    GroupRow(group: g, sortBy: sortBy, isProtected: monitor.protected.contains(g.id),
                             isExpanded: monitor.expandedID == g.id)
                }
                if tab == .background {
                    loginItemsHint.padding(.top, 10).padding(.bottom, 4)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
        }
    }

    private var loginItemsHint: some View {
        VStack(spacing: 6) {
            Text("Most background apps start when you log in.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Button("Stop them from opening at login…") { SystemLinks.openLoginItems() }
                .buttonStyle(.link).font(.system(size: 11, weight: .medium))
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack {
            Button { route = .freeUp } label: {
                Text("Free Up Memory…").font(.system(size: 13, weight: .medium)).padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent).tint(.brand).controlSize(.large)
            Spacer()
            Button("Activity Monitor") { SystemLinks.openActivityMonitor() }
                .buttonStyle(.borderless).font(.system(size: 12))
        }
    }
}

struct HogBanner: View {
    @EnvironmentObject var monitor: Monitor
    let group: AppGroup

    var body: some View {
        HStack(spacing: 10) {
            AppIconView(group: group, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(group.name) is working hard").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text("\(Format.cpu(group.cpu)) CPU for \(Format.duration(group.hotFor ?? 0))")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Quit") { monitor.quit(group) }.controlSize(.small)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.orange.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.orange.opacity(0.25)))
    }
}

struct GroupRow: View {
    @EnvironmentObject var monitor: Monitor
    let group: AppGroup
    let sortBy: String
    let isProtected: Bool
    let isExpanded: Bool
    @State private var hovering = false
    @State private var confirmForce = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                AppIconView(group: group)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(group.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        if isProtected {
                            Image(systemName: "lock.fill").font(.system(size: 8)).foregroundStyle(.tertiary)
                                .help("Never quit")
                        }
                    }
                    Text(detail).font(.system(size: 11)).foregroundStyle(detailColor).lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(Format.cpu(group.cpu))
                    .foregroundStyle(group.cpu >= 80 ? Color.orange : sortBy == "cpu" ? Color.primary : Color.secondary)
                    .frame(width: 46, alignment: .trailing)
                Text(Format.bytes(group.memory))
                    .foregroundStyle(sortBy == "memory" ? Color.primary : Color.secondary)
                    .frame(width: 60, alignment: .trailing)
                quitButton.frame(width: 22)
            }
            .font(.system(size: 12).monospacedDigit())
            .padding(.leading, 8).padding(.trailing, 4).padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.15)) {
                    monitor.expandedID = isExpanded ? nil : group.id
                    confirmForce = false
                }
            }

            if isExpanded {
                Group { confirmForce ? AnyView(forceBar) : AnyView(actionBar) }
                    .padding(.leading, 44).padding(.trailing, 8).padding(.bottom, 8)
                    .transition(.opacity)
            }
        }
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(background))
        .onHover { hovering = $0 }
        .contextMenu { menu }
        .onChange(of: isExpanded) { _, open in if !open { confirmForce = false } }
    }

    private var background: Color {
        if confirmForce { return Color.red.opacity(0.08) }
        if isExpanded { return Color.primary.opacity(0.07) }
        return hovering ? Color.primary.opacity(0.05) : .clear
    }

    @ViewBuilder private var quitButton: some View {
        if group.canQuit && hovering && !isExpanded {
            Button { monitor.quit(group) } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 14))
                    .symbolRenderingMode(.hierarchical).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain).help("Quit \(group.name)")
        } else {
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .opacity(isExpanded || hovering ? 1 : 0)
        }
    }

    @ViewBuilder private var actionBar: some View {
        if group.canQuit {
            HStack(spacing: 8) {
                Button { done(); monitor.quit(group) } label: { Text("Quit").frame(minWidth: 44) }
                    .help("Ask \(group.name) to quit. It can still ask you to save open work.")
                Button { withAnimation(.easeOut(duration: 0.15)) { confirmForce = true } } label: {
                    Text("Force Quit…").frame(minWidth: 70)
                }
                .help("Stop \(group.name) right away, without saving")
                Spacer()
                Button { monitor.toggleProtected(group.id) } label: {
                    Image(systemName: isProtected ? "lock.fill" : "lock.open")
                }
                .buttonStyle(.borderless)
                .help(isProtected ? "Allow quitting from Free Up Memory" : "Never quit (keeps it out of Free Up Memory)")
                revealButton
            }
            .controlSize(.small)
        } else {
            HStack {
                Text(group.isSelf ? "This is Lull" : "Part of macOS. It can't be quit, and macOS restarts it when needed.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                revealButton
            }
            .controlSize(.small)
        }
    }

    @ViewBuilder private var revealButton: some View {
        if let path = revealPath {
            Button { SystemLinks.reveal(path) } label: { Image(systemName: "folder") }
                .buttonStyle(.borderless).help("Show in Finder")
        }
    }

    private var revealPath: String? {
        group.bundlePath ?? (group.executablePath.isEmpty ? nil : group.executablePath)
    }

    private var forceBar: some View {
        HStack(spacing: 8) {
            Text("Force quit? Unsaved changes will be lost.")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            Spacer(minLength: 4)
            Button("Cancel") { withAnimation(.easeOut(duration: 0.15)) { confirmForce = false } }
            Button("Force Quit") { done(); monitor.quit(group, force: true) }
                .buttonStyle(.borderedProminent).tint(.red)
        }
        .controlSize(.small)
    }

    private func done() {
        confirmForce = false
        monitor.expandedID = nil
    }

    @ViewBuilder private var menu: some View {
        if group.canQuit {
            Button("Quit \(group.name)") { monitor.quit(group) }
            Button("Force Quit…") { monitor.expandedID = group.id; confirmForce = true }
            Divider()
            Button(isProtected ? "Allow Quitting" : "Never Quit") { monitor.toggleProtected(group.id) }
        } else {
            Text(group.isSelf ? "This is Lull" : "Part of macOS, can't be quit")
        }
        if let path = revealPath {
            Divider()
            Button("Show in Finder") { SystemLinks.reveal(path) }
        }
    }

    private var detail: String {
        if group.isSelf { return "This app" }
        var parts: [String] = []
        if let hot = group.hotFor, hot >= 60 { parts.append("Busy for \(Format.duration(hot))") }
        switch group.kind {
        case .system: parts.append("macOS")
        case .app:
            if group.isFrontmost { parts.append("In use") }
            else if let w = group.windows { parts.append(w == 0 ? "No open windows" : w == 1 ? "1 window" : "\(w) windows") }
        case .background: parts.append("Background")
        }
        if group.pids.count > 1 { parts.append("\(group.pids.count) processes") }
        if group.restartsItself { parts.append("Restarts itself") }
        if group.ignoredQuit { return "Didn't quit · try Force Quit" }
        return parts.joined(separator: " · ")
    }

    private var detailColor: Color {
        if (group.hotFor ?? 0) >= 60 { return .orange }
        if group.restartsItself || group.ignoredQuit { return .orange }
        return .secondary
    }
}

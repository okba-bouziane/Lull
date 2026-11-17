import AppKit
import Combine
import LullCore

struct AppGroup: Identifiable, Equatable {
    enum Kind { case app, background, system }

    let id: String
    var name: String
    var bundlePath: String?
    var executablePath: String
    var pids: [pid_t]
    var leaderPID: pid_t
    var cpu: Double
    var memory: UInt64
    var kind: Kind
    var appPID: pid_t?
    var windows: Int?
    var isFrontmost: Bool
    var isSelf: Bool
    var hotFor: TimeInterval?
    var restartsItself: Bool
    var ignoredQuit = false

    var canQuit: Bool { kind != .system && !isSelf }
}

struct MenuStatus: Equatable {
    var text: String?
    var alert: Bool
}

@MainActor
final class Monitor: ObservableObject {
    @Published private(set) var system = SystemSnapshot()
    @Published private(set) var groups: [AppGroup] = []
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var memoryHistory: [Double] = []
    @Published private(set) var hog: AppGroup?
    @Published private(set) var protected: Set<String>
    @Published private(set) var selfUsage: (cpu: Double, memory: UInt64) = (0, 0)
    /// The row whose Quit / Force Quit actions are showing.
    @Published var expandedID: String?
    @Published var isVisible = false {
        didSet {
            guard isVisible != oldValue else { return }
            if !isVisible { expandedID = nil }
            if isVisible { tick() }
            reschedule()
        }
    }

    var onStatus: ((MenuStatus) -> Void)?
    var notifier: Notifier?

    private let procSampler = ProcessSampler()
    private let systemSampler = SystemSampler()
    private let hogs = HogTracker()
    private var timer: Timer?
    private var names: [String: String] = [:]
    private var lastStatus: MenuStatus?
    private var lastUserApp: pid_t?
    private var recentlyQuit: [String: (at: Date, pids: Set<pid_t>)] = [:]
    private var respawned: Set<String> = []
    private var stubborn: Set<String> = []
    private var alerted: [String: Date] = [:]
    private var observers: [NSObjectProtocol] = []
    private let historyLength = 60
    private let me = getpid()

    init() {
        protected = Set(Prefs.d.stringArray(forKey: Prefs.protectedIDs) ?? [])
        lastUserApp = NSWorkspace.shared.frontmostApplication?.processIdentifier
        // Remember the last app the user was in, so opening Lull itself never counts as "in use".
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let self, let app, app.processIdentifier != self.me else { return }
                self.lastUserApp = app.processIdentifier
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.prefsChanged() }
        })
    }

    func start() {
        tick()
        reschedule()
    }

    // MARK: Sampling

    private var interval: TimeInterval {
        isVisible ? 2 : max(5, Prefs.d.double(forKey: Prefs.backgroundInterval))
    }

    private var scheduledInterval: TimeInterval = 0

    private func reschedule() {
        let iv = interval
        guard iv != scheduledInterval || timer == nil else { return }
        scheduledInterval = iv
        timer?.invalidate()
        let t = Timer(timeInterval: iv, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = iv * 0.25 // lets macOS batch our wake-ups with others (saves battery)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func prefsChanged() {
        reschedule()
        let p = Set(Prefs.d.stringArray(forKey: Prefs.protectedIDs) ?? [])
        if p != protected { protected = p }
        publishStatus()
    }

    func refreshSoon() {
        for delay in [1.2, 3.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.tick() }
        }
    }

    private var lastTick = Date.distantPast

    func tick() {
        // Two samples a split second apart give noisy CPU numbers; the next regular tick is soon enough.
        guard Date().timeIntervalSince(lastTick) > 0.7 else { return }
        lastTick = Date()
        let snap = systemSampler.sample()
        let stats = procSampler.sample()
        let raw = Grouper.group(stats)

        let threshold = Prefs.d.double(forKey: Prefs.alertThreshold)
        hogs.update(raw.filter { !Grouper.isSystemPath($0.executablePath) }.map { ($0.id, $0.cpu) }, threshold: threshold)

        var appsByPID: [pid_t: NSRunningApplication] = [:]
        for app in NSWorkspace.shared.runningApplications { appsByPID[app.processIdentifier] = app }
        let windowCounts = isVisible ? Self.windowCounts() : [:]
        let front = lastUserApp
        let now = Date()

        var built: [AppGroup] = []
        built.reserveCapacity(raw.count)
        for g in raw {
            let candidates = g.pids.compactMap { appsByPID[$0] }
            let app = candidates.first { $0.activationPolicy == .regular } ?? candidates.first { $0.processIdentifier == g.leaderPID } ?? candidates.first
            let isSelf = g.pids.contains(me)
            let kind: AppGroup.Kind
            if Grouper.isSystemPath(g.executablePath) { kind = .system }
            else if app?.activationPolicy == .regular { kind = .app }
            else { kind = .background }

            // Quit, then back within 30 s with brand-new processes: something (launchd, an updater) restarts it.
            if let quit = recentlyQuit[g.id] {
                if now.timeIntervalSince(quit.at) > 30 { recentlyQuit[g.id] = nil }
                else if quit.pids.isDisjoint(with: g.pids) { respawned.insert(g.id) }
            }

            var windows: Int?
            if isVisible, let app { windows = windowCounts[app.processIdentifier] ?? 0 }
            built.append(AppGroup(
                id: g.id, name: name(for: g, app: app), bundlePath: g.bundlePath, executablePath: g.executablePath,
                pids: g.pids, leaderPID: g.leaderPID, cpu: g.cpu, memory: g.memory, kind: kind, appPID: app?.processIdentifier,
                windows: windows, isFrontmost: front.map { g.pids.contains($0) } ?? false, isSelf: isSelf,
                hotFor: kind == .system ? nil : hogs.hotDuration(g.id, now: now),
                restartsItself: respawned.contains(g.id), ignoredQuit: stubborn.contains(g.id)))
        }

        let present = Set(raw.map(\.id))
        stubborn.formIntersection(present)
        if isVisible, let mine = stats.first(where: { $0.pid == me }) { selfUsage = (mine.cpu, mine.memory) }

        let minutes = Prefs.d.double(forKey: Prefs.alertMinutes)
        let worst = built
            .filter { ($0.hotFor ?? 0) >= minutes * 60 && $0.canQuit && !$0.isFrontmost && !protected.contains($0.id) }
            .max { $0.cpu < $1.cpu }
        if worst?.id != hog?.id || isVisible { hog = worst }
        if let worst { maybeNotify(worst) }

        push(&cpuHistory, snap.cpu)
        push(&memoryHistory, snap.memoryFraction)
        if isVisible || snap != system { system = snap }
        // Hidden: keep the heavy list out of SwiftUI so nothing redraws for nobody.
        if isVisible { groups = built }
        publishStatus()
    }

    private func push(_ history: inout [Double], _ value: Double) {
        history.append(value)
        if history.count > historyLength { history.removeFirst(history.count - historyLength) }
    }

    private func name(for g: ProcessGroupStat, app: NSRunningApplication?) -> String {
        if let app, let n = app.localizedName, !n.isEmpty, app.activationPolicy == .regular { return n }
        if let cached = names[g.id] { return cached }
        var n = g.fallbackName
        if let path = g.bundlePath, let b = Bundle(path: path) {
            let info = b.localizedInfoDictionary ?? [:]
            let plain = b.infoDictionary ?? [:]
            n = (info["CFBundleDisplayName"] ?? plain["CFBundleDisplayName"] ?? info["CFBundleName"] ?? plain["CFBundleName"]) as? String ?? n
        }
        names[g.id] = n
        return n
    }

    /// Normal-size windows each app owns (no window titles are read, so no permission is needed).
    private static func windowCounts() -> [pid_t: Int] {
        guard let list = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [:] }
        var counts: [pid_t: Int] = [:]
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  (b["Width"] ?? 0) >= 120, (b["Height"] ?? 0) >= 120 else { continue }
            counts[pid, default: 0] += 1
        }
        return counts
    }

    // MARK: Status

    private func publishStatus() {
        let mode = Prefs.d.string(forKey: Prefs.menuBarShows) ?? "icon"
        var text: String?
        if mode == "cpu" { text = "\(Int(system.cpu.rounded()))%" }
        if mode == "memory" { text = "\(Int((system.memoryFraction * 100).rounded()))%" }
        let status = MenuStatus(text: text, alert: system.pressure != .normal || hog != nil)
        guard status != lastStatus else { return }
        lastStatus = status
        onStatus?(status)
    }

    private func maybeNotify(_ g: AppGroup) {
        guard Prefs.d.bool(forKey: Prefs.alertsOn) else { return }
        if let last = alerted[g.id], Date().timeIntervalSince(last) < 30 * 60 { return }
        alerted[g.id] = Date()
        notifier?.post(title: "\(g.name) is slowing your Mac",
                       body: "It has used \(Format.cpu(g.cpu)) CPU for \(Format.duration(g.hotFor ?? 0)). Open Lull to quit it.")
    }

    // MARK: Actions

    func quit(_ g: AppGroup, force: Bool = false) {
        guard g.canQuit, !g.pids.contains(me) else { return }
        recentlyQuit[g.id] = (Date(), Set(g.pids))
        respawned.remove(g.id)
        stubborn.remove(g.id)

        // 1. Agents launchd keeps alive come straight back when killed: ask launchd to stop them
        //    (until next login) instead.
        let jobs = Launchd.userJobs()
        for label in Set(g.pids.compactMap { jobs[$0] }) { Launchd.stop(label) }

        // 2. Quit the process that owns the group first (Steam's main process, not one of its helpers),
        //    otherwise it just starts its helpers again.
        let leader = g.leaderPID
        let leaderApp = NSRunningApplication(processIdentifier: leader).flatMap { $0.processIdentifier == leader ? $0 : nil }
        if force {
            leaderApp?.forceTerminate()
            kill(leader, SIGKILL)
            for p in g.pids where p != leader { kill(p, SIGKILL) }
        } else if let leaderApp {
            // A real app: ask it politely so it can offer to save open work. It closes its own helpers.
            leaderApp.terminate()
            if let pid = g.appPID, pid != leader { NSRunningApplication(processIdentifier: pid)?.terminate() }
        } else {
            kill(leader, SIGTERM)
            for p in g.pids where p != leader { kill(p, SIGTERM) }
        }

        hogs.reset()
        if hog?.id == g.id { hog = nil }
        refreshSoon()

        // 3. Some apps ignore a normal quit. Say so, so Force Quit is the obvious next step.
        if !force {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                guard let self else { return }
                if kill(leader, 0) == 0 { self.stubborn.insert(g.id); self.tick() }
            }
        }
    }

    func toggleProtected(_ id: String) {
        var p = protected
        if p.contains(id) { p.remove(id) } else { p.insert(id) }
        protected = p
        Prefs.d.set(Array(p).sorted(), forKey: Prefs.protectedIDs)
    }

    func protectedName(_ id: String) -> String {
        if let n = names[id] { return n }
        if let g = groups.first(where: { $0.id == id }) { return g.name }
        return ((id as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    /// Apps worth quitting to get memory back: not the one in use, not protected, not macOS.
    var freeUpApps: [AppGroup] {
        groups.filter { $0.kind == .app && $0.canQuit && !$0.isFrontmost && !protected.contains($0.id) }
            .sorted { $0.memory > $1.memory }
    }

    var freeUpBackground: [AppGroup] {
        groups.filter { $0.kind == .background && $0.canQuit && !protected.contains($0.id) && $0.memory > 20 * 1_048_576 }
            .sorted { $0.memory > $1.memory }
    }
}

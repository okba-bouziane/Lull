import Darwin
import Foundation

/// All processes that belong to one app (Chrome plus its 20 helpers), or one standalone tool.
public struct ProcessGroupStat: Equatable, Sendable {
    /// Stable across launches: the outermost .app bundle path, or the executable path.
    public var id: String
    public var bundlePath: String?
    public var executablePath: String
    /// Bundle file name without ".app", or the executable name.
    public var fallbackName: String
    public var pids: [pid_t]
    public var leaderPID: pid_t
    public var cpu: Double
    public var memory: UInt64
}

public enum Grouper {
    /// "/Applications/Google Chrome.app/Contents/Frameworks/…/Helper.app/…" → "/Applications/Google Chrome.app"
    public static func outermostBundle(_ path: String) -> String? {
        if let range = path.range(of: ".app/") {
            return String(path[..<range.upperBound].dropLast())
        }
        if path.hasSuffix(".app") { return path }
        // Bundles with unusual names (Steam.AppBundle/Steam, .xpc services) still have Contents/MacOS.
        if let range = path.range(of: "/Contents/MacOS/") {
            return String(path[..<range.lowerBound])
        }
        return nil
    }

    /// Parts of the disk only macOS writes to. Processes from here are shown but never offered for quitting.
    public static func isSystemPath(_ path: String) -> Bool {
        if path.isEmpty { return true }
        let prefixes = ["/System/", "/usr/", "/bin/", "/sbin/", "/Library/Apple/", "/private/", "/Library/Developer/CommandLineTools/"]
        return prefixes.contains { path.hasPrefix($0) }
    }

    public static func group(_ stats: [ProcessStat]) -> [ProcessGroupStat] {
        var byPID: [pid_t: ProcessStat] = [:]
        byPID.reserveCapacity(stats.count)
        for s in stats { byPID[s.pid] = s }

        var groups: [String: ProcessGroupStat] = [:]
        var ownerVotes: [String: [pid_t: Int]] = [:]
        for s in stats {
            // Put a helper under the process macOS holds responsible, when we can read that process.
            let owner = (s.responsiblePID != s.pid ? byPID[s.responsiblePID] : nil) ?? s
            let bundle = outermostBundle(owner.path)
            let id = bundle ?? (owner.path.isEmpty ? "name:\(owner.name)" : owner.path)
            if groups[id] == nil {
                let name = bundle.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension } ?? owner.name
                groups[id] = ProcessGroupStat(id: id, bundlePath: bundle, executablePath: owner.path, fallbackName: name,
                                              pids: [], leaderPID: owner.pid, cpu: 0, memory: 0)
            }
            ownerVotes[id, default: [:]][owner.pid, default: 0] += 1
            groups[id]!.pids.append(s.pid)
            groups[id]!.cpu += s.cpu
            groups[id]!.memory += s.memory
        }
        // Leader: the process most members belong to (Steam's main process, not its ipcserver),
        // ties going to the oldest (lowest) pid.
        return groups.values.map { g in
            var g = g
            let votes = ownerVotes[g.id] ?? [:]
            if let best = votes.filter({ g.pids.contains($0.key) }).max(by: { ($0.value, -$0.key) < ($1.value, -$1.key) }) {
                g.leaderPID = best.key
            } else {
                g.leaderPID = g.pids.min() ?? g.leaderPID
            }
            g.pids.sort()
            return g
        }
    }
}

/// Remembers how long each group has stayed above a CPU threshold.
public final class HogTracker {
    private var hotSince: [String: Date] = [:]

    public init() {}

    public func update(_ usage: [(id: String, cpu: Double)], threshold: Double, now: Date = Date()) {
        var stillHot: [String: Date] = [:]
        for u in usage where u.cpu >= threshold {
            stillHot[u.id] = hotSince[u.id] ?? now
        }
        hotSince = stillHot
    }

    /// Seconds a group has been continuously above the threshold, or nil.
    public func hotDuration(_ id: String, now: Date = Date()) -> TimeInterval? {
        hotSince[id].map { now.timeIntervalSince($0) }
    }

    public func reset() { hotSince.removeAll() }
}

public enum Format {
    public static func bytes(_ b: UInt64) -> String {
        let mb = Double(b) / 1_048_576
        if mb < 1 { return "<1 MB" }
        if mb < 1000 { return "\(Int(mb.rounded())) MB" }
        let gb = mb / 1024
        return gb < 10 ? String(format: "%.1f GB", gb) : "\(Int(gb.rounded())) GB"
    }

    public static func cpu(_ p: Double) -> String {
        if p < 0.05 { return "0%" }
        if p < 10 { return String(format: "%.1f%%", p) }
        return "\(Int(p.rounded()))%"
    }

    public static func duration(_ s: TimeInterval) -> String {
        let m = Int(s / 60)
        if m < 1 { return "\(Int(s)) s" }
        if m < 60 { return "\(m) min" }
        return "\(m / 60) h \(m % 60) min"
    }
}

import Foundation

/// Background agents started by launchd (login items, Homebrew services, updaters).
/// Many are set to KeepAlive, so killing the process just makes launchd start it again.
/// Stopping them has to go through launchd itself.
public enum Launchd {
    private static var domain: String { "gui/\(getuid())" }

    /// pid → job label, for the jobs launchd runs in this login session.
    public static func userJobs() -> [pid_t: String] {
        guard let text = run(["print", domain]) else { return [:] }
        return parseServices(text)
    }

    /// Reads the `services = { pid  status  label }` block of `launchctl print gui/<uid>`.
    /// Only jobs Lull may stop are kept: not Apple's, and not plain apps (launched by Finder/Dock as "application.…").
    public static func parseServices(_ text: String) -> [pid_t: String] {
        var result: [pid_t: String] = [:]
        var inside = false
        for line in text.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t == "services = {" { inside = true; continue }
            guard inside else { continue }
            if t == "}" { break }
            let parts = t.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= 3, let pid = pid_t(parts[0]), pid > 0 else { continue }
            let label = parts[2...].joined(separator: " ")
            if isStoppable(label) { result[pid] = label }
        }
        return result
    }

    public static func isStoppable(_ label: String) -> Bool {
        !label.hasPrefix("application.") && !label.hasPrefix("com.apple.")
    }

    /// Stops the job and unloads it until the next login, so it is not started again.
    @discardableResult
    public static func stop(_ label: String) -> Bool {
        run(["bootout", "\(domain)/\(label)"]) != nil
    }

    public static func isRunning(_ label: String) -> Bool {
        run(["print", "\(domain)/\(label)"]) != nil
    }

    /// Runs launchctl and returns its output, or nil when it fails.
    @discardableResult
    static func run(_ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}

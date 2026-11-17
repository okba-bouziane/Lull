import Darwin
import Foundation

/// One process owned by the current user, measured between two samples.
public struct ProcessStat: Equatable, Sendable {
    public var pid: pid_t
    public var name: String
    public var path: String
    /// The process macOS holds responsible for this one (Chrome for its helpers). Equal to `pid` when none.
    public var responsiblePID: pid_t
    /// CPU use since the previous sample, in percent of one core (like Activity Monitor, can exceed 100).
    public var cpu: Double
    /// Physical footprint in bytes (the "Memory" column in Activity Monitor).
    public var memory: UInt64

    public init(pid: pid_t, name: String, path: String, responsiblePID: pid_t, cpu: Double, memory: UInt64) {
        self.pid = pid; self.name = name; self.path = path
        self.responsiblePID = responsiblePID; self.cpu = cpu; self.memory = memory
    }
}

/// Reads the current user's processes straight from the kernel (libproc). No `ps`, no shell, about 2 ms per pass.
public final class ProcessSampler {
    private struct Identity { var start: UInt64; var path: String; var name: String; var responsible: pid_t }

    private let ticksToNs: Double
    private let uid = getuid()
    private var lastCPU: [pid_t: (start: UInt64, ns: UInt64)] = [:]
    private var lastWall: UInt64 = 0
    private var identities: [pid_t: Identity] = [:]
    private var pidBuffer: [pid_t] = []
    private let responsibleFor: (@convention(c) (pid_t) -> pid_t)?

    public init() {
        var tb = mach_timebase_info()
        mach_timebase_info(&tb)
        ticksToNs = Double(tb.numer) / Double(tb.denom)
        // Same lookup Activity Monitor uses to put helper processes under their app. Optional: we fall back to paths.
        if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") {
            responsibleFor = unsafeBitCast(sym, to: (@convention(c) (pid_t) -> pid_t).self)
        } else {
            responsibleFor = nil
        }
    }

    public func sample() -> [ProcessStat] {
        let wall = UInt64(Double(mach_absolute_time()) * ticksToNs)
        let elapsed = lastWall == 0 ? 0 : Double(wall &- lastWall)
        lastWall = wall

        let pids = listPIDs()
        var result: [ProcessStat] = []
        result.reserveCapacity(pids.count / 2)
        var seen = Set<pid_t>(minimumCapacity: pids.count)

        for pid in pids where pid > 0 {
            var info = rusage_info_v4()
            let ok = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
            }
            guard ok == 0 else { continue } // other users' processes are not readable without root

            let start = info.ri_proc_start_abstime
            guard let id = identity(pid: pid, start: start) else { continue }
            seen.insert(pid)

            let cpuNs = UInt64(Double(info.ri_user_time &+ info.ri_system_time) * ticksToNs)
            var cpu = 0.0
            if elapsed > 0, let prev = lastCPU[pid], prev.start == start, cpuNs >= prev.ns {
                cpu = Double(cpuNs - prev.ns) / elapsed * 100
            }
            lastCPU[pid] = (start, cpuNs)
            result.append(ProcessStat(pid: pid, name: id.name, path: id.path, responsiblePID: id.responsible,
                                      cpu: cpu, memory: info.ri_phys_footprint))
        }

        // Forget processes that exited so the caches never grow.
        if lastCPU.count > seen.count { lastCPU = lastCPU.filter { seen.contains($0.key) } }
        if identities.count > seen.count + 64 { identities = identities.filter { seen.contains($0.key) } }
        return result
    }

    private func listPIDs() -> [pid_t] {
        let needed = Int(proc_listallpids(nil, 0)) + 32
        if pidBuffer.count < needed { pidBuffer = [pid_t](repeating: 0, count: needed * 2) }
        let count = pidBuffer.withUnsafeMutableBufferPointer {
            proc_listallpids($0.baseAddress, Int32($0.count * MemoryLayout<pid_t>.size))
        }
        return Array(pidBuffer.prefix(max(0, Int(count))))
    }

    /// Path, name and responsible process change only when a pid is reused, so they are looked up once.
    private func identity(pid: pid_t, start: UInt64) -> Identity? {
        if let id = identities[pid], id.start == start { return id }
        var bsd = proc_bsdinfo()
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0,
              bsd.pbi_uid == uid else { return nil }

        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let len = proc_pidpath(pid, &buf, UInt32(buf.count))
        let path = len > 0 ? String(cString: buf) : ""
        var name = path.isEmpty ? "" : (path as NSString).lastPathComponent
        if name.isEmpty {
            name = withUnsafeBytes(of: bsd.pbi_name) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
        }
        if name.isEmpty { return nil }
        let responsible = responsibleFor?(pid) ?? pid
        let id = Identity(start: start, path: path, name: name, responsible: responsible > 0 ? responsible : pid)
        identities[pid] = id
        return id
    }
}

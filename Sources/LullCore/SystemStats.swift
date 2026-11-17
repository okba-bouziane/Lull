import Darwin
import Foundation

public enum MemoryPressure: Int, Sendable {
    case normal = 1, warning = 2, critical = 4

    public var label: String {
        switch self {
        case .normal: return "Normal"
        case .warning: return "High"
        case .critical: return "Critical"
        }
    }
}

public struct SystemSnapshot: Equatable, Sendable {
    /// Share of all cores in use, 0...100.
    public var cpu: Double
    public var memoryUsed: UInt64
    public var memoryTotal: UInt64
    public var swapUsed: UInt64
    public var pressure: MemoryPressure
    public var cores: Int

    public var memoryFraction: Double { memoryTotal == 0 ? 0 : Double(memoryUsed) / Double(memoryTotal) }

    public init(cpu: Double = 0, memoryUsed: UInt64 = 0, memoryTotal: UInt64 = 0, swapUsed: UInt64 = 0,
                pressure: MemoryPressure = .normal, cores: Int = 1) {
        self.cpu = cpu; self.memoryUsed = memoryUsed; self.memoryTotal = memoryTotal
        self.swapUsed = swapUsed; self.pressure = pressure; self.cores = cores
    }
}

/// Whole-machine CPU and memory, the same way Activity Monitor counts them.
public final class SystemSampler {
    private var lastTicks: (busy: UInt64, total: UInt64)?
    private let total: UInt64 = ProcessInfo.processInfo.physicalMemory
    private let cores = ProcessInfo.processInfo.activeProcessorCount

    public init() {}

    public func sample() -> SystemSnapshot {
        SystemSnapshot(cpu: cpuPercent(), memoryUsed: memoryUsed(), memoryTotal: total,
                       swapUsed: swapUsed(), pressure: pressure(), cores: cores)
    }

    private func cpuPercent() -> Double {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        let t = load.cpu_ticks
        let user = UInt64(t.0), system = UInt64(t.1), idle = UInt64(t.2), nice = UInt64(t.3)
        let busy = user + system + nice, all = busy + idle
        defer { lastTicks = (busy, all) }
        guard let last = lastTicks, all > last.total else { return 0 }
        return min(100, Double(busy - last.busy) / Double(all - last.total) * 100)
    }

    /// "Memory Used" in Activity Monitor: app memory + wired + compressed.
    private func memoryUsed() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        let page = UInt64(vm_kernel_page_size)
        let app = UInt64(stats.internal_page_count) &- UInt64(stats.purgeable_count)
        let pages = app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return min(total, pages * page)
    }

    private func swapUsed() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        return sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 ? usage.xsu_used : 0
    }

    private func pressure() -> MemoryPressure {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .normal }
        return MemoryPressure(rawValue: Int(level)) ?? .normal
    }
}

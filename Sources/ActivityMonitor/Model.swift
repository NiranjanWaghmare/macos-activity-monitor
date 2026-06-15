import Foundation

/// One row in the process table. Mirrors the columns shown by Activity Monitor.
struct ProcessSample: Identifiable, Hashable {
    let id: pid_t          // PID doubles as the stable identity
    var pid: pid_t { id }
    var name: String
    var user: String
    var cpuPercent: Double      // 0...(ncpu*100), like Activity Monitor
    var cpuTime: TimeInterval   // total CPU time consumed (user + system)
    var threads: Int
    var residentBytes: UInt64   // physical (resident) memory footprint
    var memoryPercent: Double   // share of physical RAM
    var diskReadBytes: UInt64   // cumulative bytes read from disk
    var diskWriteBytes: UInt64  // cumulative bytes written to disk
    var energyImpact: Double    // approximate, CPU-weighted
}

/// Whole-machine CPU load broken into the buckets Activity Monitor charts.
struct CPULoad {
    var system: Double = 0   // 0...1
    var user: Double = 0     // 0...1
    var idle: Double = 1     // 0...1
    var perCore: [Double] = []  // each 0...1 (busy fraction)

    var totalBusy: Double { min(1, system + user) }
}

/// Memory pressure snapshot, in bytes, matching the Memory tab footer.
struct MemoryLoad {
    var total: UInt64 = 0
    var used: UInt64 = 0          // app + wired + compressed
    var appMemory: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var cachedFiles: UInt64 = 0
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0

    /// 0...1 used fraction, drives the colored pressure bar.
    var usedFraction: Double {
        total == 0 ? 0 : Double(used) / Double(total)
    }
}

/// System-wide network throughput, derived from interface byte deltas.
struct NetworkLoad {
    var bytesInPerSec: Double = 0
    var bytesOutPerSec: Double = 0
    var packetsInPerSec: Double = 0
    var packetsOutPerSec: Double = 0
    var totalIn: UInt64 = 0
    var totalOut: UInt64 = 0
}

/// System-wide disk throughput, summed from per-process I/O deltas.
struct DiskLoad {
    var readBytesPerSec: Double = 0
    var writeBytesPerSec: Double = 0
    var totalRead: UInt64 = 0
    var totalWritten: UInt64 = 0
}

/// A ring of recent values used to draw the sparkline-style history graphs.
struct History {
    private(set) var values: [Double]
    let capacity: Int

    init(capacity: Int = 90) {
        self.capacity = capacity
        self.values = Array(repeating: 0, count: capacity)
    }

    mutating func push(_ value: Double) {
        values.append(value)
        if values.count > capacity {
            values.removeFirst(values.count - capacity)
        }
    }

    var latest: Double { values.last ?? 0 }
}

/// Pure, testable search filter shared by the process table.
/// Matches a query against process name, PID, or owning user.
enum ProcessQuery {
    static func filter(_ processes: [ProcessSample], query: String) -> [ProcessSample] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return processes }
        return processes.filter { p in
            if p.name.localizedCaseInsensitiveContains(trimmed) { return true }
            if String(p.pid).contains(trimmed) { return true }
            if p.user.localizedCaseInsensitiveContains(trimmed) { return true }
            return false
        }
    }
}

enum Tab: String, CaseIterable, Identifiable {
    case cpu = "CPU"
    case memory = "Memory"
    case energy = "Energy"
    case disk = "Disk"
    case network = "Network"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .energy: return "bolt.fill"
        case .disk: return "internaldrive"
        case .network: return "network"
        }
    }
}

/// Human-readable byte formatting that matches Activity Monitor's style.
enum ByteFormat {
    static func string(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: Int64(bytes))
    }

    static func rate(_ bytesPerSec: Double) -> String {
        string(UInt64(max(0, bytesPerSec))) + "/s"
    }
}

import Foundation
import Darwin

// MARK: - CPU

/// Reads whole-machine and per-core CPU load by diffing tick counters.
final class CPUSampler {
    private var previousTotal: host_cpu_load_info?
    private var previousCores: [UInt32]?  // flattened [user, system, idle, nice] * nCores

    let coreCount = Int(ProcessInfo.processInfo.activeProcessorCount)

    func sample() -> CPULoad {
        var load = CPULoad()
        load.perCore = Array(repeating: 0, count: coreCount)

        // ---- Aggregate (HOST_CPU_LOAD_INFO) ----
        if let current = Self.hostCPULoad() {
            if let prev = previousTotal {
                let user = Double(current.cpu_ticks.0 &- prev.cpu_ticks.0)
                let system = Double(current.cpu_ticks.1 &- prev.cpu_ticks.1)
                let idle = Double(current.cpu_ticks.2 &- prev.cpu_ticks.2)
                let nice = Double(current.cpu_ticks.3 &- prev.cpu_ticks.3)
                let total = user + system + idle + nice
                if total > 0 {
                    load.user = (user + nice) / total
                    load.system = system / total
                    load.idle = idle / total
                }
            }
            previousTotal = current
        }

        // ---- Per-core (PROCESSOR_CPU_LOAD_INFO) ----
        var cpuCount: natural_t = 0
        var infoArray: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(mach_host_self(),
                                         PROCESSOR_CPU_LOAD_INFO,
                                         &cpuCount,
                                         &infoArray,
                                         &infoCount)
        if result == KERN_SUCCESS, let infoArray {
            let states = Int(CPU_STATE_MAX)
            var flattened = [UInt32](repeating: 0, count: Int(cpuCount) * states)
            for i in 0..<(Int(cpuCount) * states) {
                flattened[i] = UInt32(bitPattern: infoArray[i])
            }
            if let prev = previousCores, prev.count == flattened.count {
                for core in 0..<Int(cpuCount) where core < load.perCore.count {
                    let base = core * states
                    let user = Double(flattened[base + Int(CPU_STATE_USER)] &- prev[base + Int(CPU_STATE_USER)])
                    let sys = Double(flattened[base + Int(CPU_STATE_SYSTEM)] &- prev[base + Int(CPU_STATE_SYSTEM)])
                    let idle = Double(flattened[base + Int(CPU_STATE_IDLE)] &- prev[base + Int(CPU_STATE_IDLE)])
                    let nice = Double(flattened[base + Int(CPU_STATE_NICE)] &- prev[base + Int(CPU_STATE_NICE)])
                    let total = user + sys + idle + nice
                    load.perCore[core] = total > 0 ? (user + sys + nice) / total : 0
                }
            }
            previousCores = flattened
            let size = vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: infoArray), size)
        }

        return load
    }

    private static func hostCPULoad() -> host_cpu_load_info? {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        return result == KERN_SUCCESS ? info : nil
    }
}

// MARK: - Memory

/// Reads VM statistics and swap usage for the Memory tab.
final class MemorySampler {
    private let pageSize: UInt64 = {
        var size: vm_size_t = 0
        host_page_size(mach_host_self(), &size)
        return UInt64(size)
    }()

    func sample() -> MemoryLoad {
        var load = MemoryLoad()
        load.total = ProcessInfo.processInfo.physicalMemory

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            let wired = UInt64(stats.wire_count) * pageSize
            let compressed = UInt64(stats.compressor_page_count) * pageSize
            let purgeable = UInt64(stats.purgeable_count) * pageSize
            let external = UInt64(stats.external_page_count) * pageSize
            let internalPages = UInt64(stats.internal_page_count) * pageSize
            let appMemory = internalPages > purgeable ? internalPages - purgeable : internalPages

            load.wired = wired
            load.compressed = compressed
            load.appMemory = appMemory
            load.cachedFiles = external + purgeable
            load.used = appMemory + wired + compressed
        }

        // Swap usage via sysctl(vm.swapusage)
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.stride
        var mib = [CTL_VM, VM_SWAPUSAGE]
        if sysctl(&mib, 2, &swap, &swapSize, nil, 0) == 0 {
            load.swapUsed = swap.xsu_used
            load.swapTotal = swap.xsu_total
        }

        return load
    }
}

// MARK: - Network

/// Sums interface byte/packet counters across physical interfaces and diffs
/// them to produce a throughput reading.
final class NetworkSampler {
    private var lastIn: UInt64 = 0
    private var lastOut: UInt64 = 0
    private var lastPktIn: UInt64 = 0
    private var lastPktOut: UInt64 = 0
    private var lastTime = Date()
    private var primed = false

    func sample() -> NetworkLoad {
        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var pktIn: UInt64 = 0
        var pktOut: UInt64 = 0

        var addrs: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&addrs) == 0, let first = addrs {
            var ptr: UnsafeMutablePointer<ifaddrs>? = first
            while let cur = ptr {
                let flags = Int32(cur.pointee.ifa_flags)
                let name = String(cString: cur.pointee.ifa_name)
                let isLoopback = (flags & IFF_LOOPBACK) != 0 || name.hasPrefix("lo")
                if let data = cur.pointee.ifa_addr,
                   data.pointee.sa_family == UInt8(AF_LINK),
                   !isLoopback,
                   let dataPtr = cur.pointee.ifa_data {
                    let networkData = dataPtr.assumingMemoryBound(to: if_data.self)
                    totalIn += UInt64(networkData.pointee.ifi_ibytes)
                    totalOut += UInt64(networkData.pointee.ifi_obytes)
                    pktIn += UInt64(networkData.pointee.ifi_ipackets)
                    pktOut += UInt64(networkData.pointee.ifi_opackets)
                }
                ptr = cur.pointee.ifa_next
            }
            freeifaddrs(addrs)
        }

        var load = NetworkLoad()
        load.totalIn = totalIn
        load.totalOut = totalOut

        let now = Date()
        let elapsed = now.timeIntervalSince(lastTime)
        if primed, elapsed > 0 {
            load.bytesInPerSec = Double(totalIn &- lastIn) / elapsed
            load.bytesOutPerSec = Double(totalOut &- lastOut) / elapsed
            load.packetsInPerSec = Double(pktIn &- lastPktIn) / elapsed
            load.packetsOutPerSec = Double(pktOut &- lastPktOut) / elapsed
        }
        lastIn = totalIn
        lastOut = totalOut
        lastPktIn = pktIn
        lastPktOut = pktOut
        lastTime = now
        primed = true

        return load
    }
}

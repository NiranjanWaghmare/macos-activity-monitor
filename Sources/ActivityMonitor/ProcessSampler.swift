import Foundation
import Darwin

/// Enumerates every process and computes the per-row metrics shown in the
/// table. CPU% and disk throughput are derived by diffing successive samples.
final class ProcessSampler {
    /// Cumulative counters retained between samples, keyed by PID.
    private struct Previous {
        var cpuTimeNs: UInt64
        var diskRead: UInt64
        var diskWrite: UInt64
        var timestamp: Double
    }

    private var previous: [pid_t: Previous] = [:]
    private var userNameCache: [uid_t: String] = [:]
    private let coreCount = Double(ProcessInfo.processInfo.activeProcessorCount)
    private let totalRAM = Double(ProcessInfo.processInfo.physicalMemory)

    func sample() -> [ProcessSample] {
        let now = ProcessInfo.processInfo.systemUptime
        let pids = listPIDs()
        var results: [ProcessSample] = []
        results.reserveCapacity(pids.count)
        var seen = Set<pid_t>()

        for pid in pids where pid > 0 {
            guard let info = taskInfo(for: pid) else { continue }
            seen.insert(pid)

            let cpuTimeNs = info.pti_total_user &+ info.pti_total_system
            let resident = info.pti_resident_size
            let threads = Int(info.pti_threadnum)

            let (diskRead, diskWrite) = diskIO(for: pid)

            var cpuPercent = 0.0
            if let prev = previous[pid] {
                let dt = now - prev.timestamp
                if dt > 0 {
                    let deltaNs = Double(cpuTimeNs &- prev.cpuTimeNs)
                    // Nanoseconds of CPU consumed over dt seconds → percentage.
                    cpuPercent = (deltaNs / 1_000_000_000.0) / dt * 100.0
                }
            }
            previous[pid] = Previous(cpuTimeNs: cpuTimeNs,
                                     diskRead: diskRead,
                                     diskWrite: diskWrite,
                                     timestamp: now)

            let sample = ProcessSample(
                id: pid,
                name: name(for: pid),
                user: user(for: pid),
                cpuPercent: max(0, cpuPercent),
                cpuTime: Double(cpuTimeNs) / 1_000_000_000.0,
                threads: threads,
                residentBytes: resident,
                memoryPercent: totalRAM > 0 ? Double(resident) / totalRAM * 100 : 0,
                diskReadBytes: diskRead,
                diskWriteBytes: diskWrite,
                // Activity Monitor's "Energy Impact" is proprietary; approximate
                // it as CPU load scaled by thread fan-out.
                energyImpact: cpuPercent * (1 + log2(Double(max(1, threads)))) / 10
            )
            results.append(sample)
        }

        // Drop bookkeeping for processes that have exited.
        previous = previous.filter { seen.contains($0.key) }
        return results
    }

    // MARK: - libproc helpers

    private func listPIDs() -> [pid_t] {
        let maxCount = proc_listallpids(nil, 0)
        guard maxCount > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(maxCount))
        let byteCount = Int32(Int(maxCount) * MemoryLayout<pid_t>.size)
        let count = proc_listallpids(&pids, byteCount)
        guard count > 0 else { return [] }
        return Array(pids.prefix(Int(count)))
    }

    private func taskInfo(for pid: pid_t) -> proc_taskinfo? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size)
        return result == size ? info : nil
    }

    private func diskIO(for pid: pid_t) -> (read: UInt64, write: UInt64) {
        var usage = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
            }
        }
        guard result == 0 else { return (0, 0) }
        return (usage.ri_diskio_bytesread, usage.ri_diskio_byteswritten)
    }

    private func name(for pid: pid_t) -> String {
        // Prefer the executable's file name (matches Activity Monitor); fall
        // back to the kernel's truncated process name.
        var pathBuf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        if proc_pidpath(pid, &pathBuf, UInt32(MAXPATHLEN)) > 0 {
            let path = String(cString: pathBuf)
            if !path.isEmpty {
                return (path as NSString).lastPathComponent
            }
        }
        var nameBuf = [CChar](repeating: 0, count: 2 * Int(MAXCOMLEN) + 1)
        if proc_name(pid, &nameBuf, UInt32(nameBuf.count)) > 0 {
            return String(cString: nameBuf)
        }
        return "PID \(pid)"
    }

    private func user(for pid: pid_t) -> String {
        var mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return "—" }
        let uid = info.kp_eproc.e_ucred.cr_uid
        if let cached = userNameCache[uid] { return cached }
        let resolved: String
        if let pw = getpwuid(uid) {
            resolved = String(cString: pw.pointee.pw_name)
        } else {
            resolved = String(uid)
        }
        userNameCache[uid] = resolved
        return resolved
    }
}

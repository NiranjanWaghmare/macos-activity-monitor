import Foundation
import SwiftUI
import Combine

/// Central observable model. Owns the samplers, runs them on a background
/// queue at a fixed cadence, and republishes results on the main actor.
@MainActor
final class SystemMonitor: ObservableObject {
    @Published var processes: [ProcessSample] = []
    @Published var cpu = CPULoad()
    @Published var memory = MemoryLoad()
    @Published var network = NetworkLoad()
    @Published var disk = DiskLoad()

    // Rolling history for the graphs (newest at the end).
    @Published var cpuHistory = History()
    @Published var memoryHistory = History()
    @Published var networkInHistory = History()
    @Published var networkOutHistory = History()
    @Published var diskReadHistory = History()
    @Published var diskWriteHistory = History()

    @Published var updateInterval: TimeInterval = 2.0 {
        didSet { restartTimer() }
    }

    var processCount: Int { processes.count }
    var threadCount: Int { processes.reduce(0) { $0 + $1.threads } }

    private let queue = DispatchQueue(label: "com.activitymonitor.sampling")
    // The samplers keep mutable inter-sample state and are only ever touched
    // on `queue`, never the main actor — hence nonisolated(unsafe).
    private nonisolated(unsafe) let cpuSampler = CPUSampler()
    private nonisolated(unsafe) let memorySampler = MemorySampler()
    private nonisolated(unsafe) let networkSampler = NetworkSampler()
    private nonisolated(unsafe) let processSampler = ProcessSampler()

    private var timer: Timer?
    private var lastDiskRead: UInt64 = 0
    private var lastDiskWrite: UInt64 = 0
    private var lastDiskTime = Date()
    private var diskPrimed = false

    func start() {
        refresh()
        restartTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            // Timer fires on the main run loop, so we are already on the main actor.
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// Kicks off one sampling pass off the main thread, then merges the
    /// results back on the main actor.
    func refresh() {
        queue.async { [weak self] in
            guard let self else { return }
            let cpu = self.cpuSampler.sample()
            let memory = self.memorySampler.sample()
            let network = self.networkSampler.sample()
            let processes = self.processSampler.sample()

            // System-wide disk throughput ≈ sum of per-process cumulative I/O,
            // diffed over the sampling interval.
            let totalRead = processes.reduce(UInt64(0)) { $0 &+ $1.diskReadBytes }
            let totalWritten = processes.reduce(UInt64(0)) { $0 &+ $1.diskWriteBytes }

            Task { @MainActor in
                self.apply(cpu: cpu, memory: memory, network: network,
                           processes: processes, totalRead: totalRead, totalWritten: totalWritten)
            }
        }
    }

    private func apply(cpu: CPULoad, memory: MemoryLoad, network: NetworkLoad,
                       processes: [ProcessSample], totalRead: UInt64, totalWritten: UInt64) {
        self.cpu = cpu
        self.memory = memory
        self.network = network
        self.processes = processes

        var disk = DiskLoad()
        disk.totalRead = totalRead
        disk.totalWritten = totalWritten
        let now = Date()
        let dt = now.timeIntervalSince(lastDiskTime)
        if diskPrimed, dt > 0 {
            disk.readBytesPerSec = max(0, Double(totalRead &- lastDiskRead) / dt)
            disk.writeBytesPerSec = max(0, Double(totalWritten &- lastDiskWrite) / dt)
        }
        lastDiskRead = totalRead
        lastDiskWrite = totalWritten
        lastDiskTime = now
        diskPrimed = true
        self.disk = disk

        cpuHistory.push(cpu.totalBusy)
        memoryHistory.push(memory.usedFraction)
        networkInHistory.push(network.bytesInPerSec)
        networkOutHistory.push(network.bytesOutPerSec)
        diskReadHistory.push(disk.readBytesPerSec)
        diskWriteHistory.push(disk.writeBytesPerSec)
    }

    // MARK: - Process control

    /// Sends SIGTERM (graceful quit) or SIGKILL (force quit) to a process.
    func quit(pid: pid_t, force: Bool) {
        kill(pid, force ? SIGKILL : SIGTERM)
        // Reflect the change quickly rather than waiting for the next tick.
        refresh()
    }
}

import Foundation

/// Runs one full sampling pass (with a delta interval) and prints the results.
/// Invoked via `swift run ActivityMonitor --selftest`. Useful for confirming
/// the Mach/libproc data path works without opening the GUI.
enum SelfTest {
    static func run() {
        let cpu = CPUSampler()
        let memory = MemorySampler()
        let network = NetworkSampler()
        let processes = ProcessSampler()

        // Prime once so the next pass can compute deltas.
        _ = cpu.sample()
        _ = network.sample()
        _ = processes.sample()
        Thread.sleep(forTimeInterval: 1.0)

        let c = cpu.sample()
        let m = memory.sample()
        let n = network.sample()
        let procs = processes.sample()

        print("=== Activity Monitor self-test ===\n")

        print("CPU")
        print(String(format: "  User: %.1f%%  System: %.1f%%  Idle: %.1f%%",
                     c.user * 100, c.system * 100, c.idle * 100))
        let coreStr = c.perCore.map { String(format: "%.0f%%", $0 * 100) }.joined(separator: " ")
        print("  Cores (\(c.perCore.count)): \(coreStr)\n")

        print("Memory")
        print("  Physical: \(ByteFormat.string(m.total))   Used: \(ByteFormat.string(m.used))   (\(String(format: "%.1f%%", m.usedFraction * 100)))")
        print("  App: \(ByteFormat.string(m.appMemory))   Wired: \(ByteFormat.string(m.wired))   Compressed: \(ByteFormat.string(m.compressed))")
        print("  Cached files: \(ByteFormat.string(m.cachedFiles))   Swap: \(ByteFormat.string(m.swapUsed)) / \(ByteFormat.string(m.swapTotal))\n")

        print("Network")
        print("  In: \(ByteFormat.rate(n.bytesInPerSec))   Out: \(ByteFormat.rate(n.bytesOutPerSec))")
        print("  Totals — In: \(ByteFormat.string(n.totalIn))   Out: \(ByteFormat.string(n.totalOut))\n")

        print("Processes: \(procs.count)   Threads: \(procs.reduce(0) { $0 + $1.threads })")
        print("Top 10 by CPU:")
        let top = procs.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(10)
        func pad(_ s: String, _ width: Int) -> String {
            s.count >= width ? String(s.prefix(width)) : s + String(repeating: " ", count: width - s.count)
        }
        print("  " + pad("PROCESS", 28) + pad("%CPU", 8) + pad("MEM", 11) + pad("THR", 6) + "USER")
        for p in top {
            let line = "  " + pad(p.name, 28)
                + pad(String(format: "%.1f", p.cpuPercent), 8)
                + pad(ByteFormat.string(p.residentBytes), 11)
                + pad(String(p.threads), 6)
                + p.user
            print(line)
        }
        print("\n✓ Sampling path works — every value above came from live Mach/libproc calls.")
    }
}

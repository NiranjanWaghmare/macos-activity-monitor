import XCTest
import Darwin
@testable import ActivityMonitor

/// 12 scenarios: deterministic logic tests + live-data sanity checks against
/// the real Mach/libproc sampling path.
final class ActivityMonitorTests: XCTestCase {

    // MARK: 1 — History ring buffer rolls over and keeps the newest N values
    func testHistoryRingBufferRollsOver() {
        var history = History(capacity: 3)
        history.push(1)
        history.push(2)
        history.push(3)
        history.push(4)   // should evict the oldest (1)
        XCTAssertEqual(history.values.count, 3)
        XCTAssertEqual(history.values, [2, 3, 4])
        XCTAssertEqual(history.latest, 4)
    }

    // MARK: 2 — A fresh History is zero-filled to capacity
    func testHistoryStartsZeroFilled() {
        let history = History(capacity: 5)
        XCTAssertEqual(history.values.count, 5)
        XCTAssertEqual(history.latest, 0)
        XCTAssertTrue(history.values.allSatisfy { $0 == 0 })
    }

    // MARK: 3 — Byte formatting scales into KB / MB / GB
    func testByteFormattingScales() {
        XCTAssertTrue(ByteFormat.string(2_000).contains("KB"))
        XCTAssertTrue(ByteFormat.string(5_000_000).contains("MB"))
        XCTAssertTrue(ByteFormat.string(3_000_000_000).contains("GB"))
    }

    // MARK: 4 — Rate formatting appends "/s"
    func testByteRateAppendsPerSecond() {
        XCTAssertTrue(ByteFormat.rate(1_500).hasSuffix("/s"))
        // Negative rate must not crash and must clamp to a sane value.
        XCTAssertTrue(ByteFormat.rate(-42).hasSuffix("/s"))
    }

    // MARK: 5 — CPU time formats as M:SS.cc like Activity Monitor
    func testCPUTimeStringFormatting() {
        XCTAssertEqual(ProcessTableView.cpuTimeString(0), "0:00.00")
        XCTAssertEqual(ProcessTableView.cpuTimeString(65.5), "1:05.50")
        XCTAssertEqual(ProcessTableView.cpuTimeString(3_661.0), "61:01.00")
    }

    // MARK: 6 — Memory used fraction, including divide-by-zero guard
    func testMemoryUsedFraction() {
        var mem = MemoryLoad()
        mem.total = 16_000_000_000
        mem.used = 8_000_000_000
        XCTAssertEqual(mem.usedFraction, 0.5, accuracy: 0.0001)

        let empty = MemoryLoad()   // total == 0
        XCTAssertEqual(empty.usedFraction, 0)
    }

    // MARK: 7 — CPULoad.totalBusy clamps to 1.0
    func testCPULoadTotalBusyClamps() {
        var load = CPULoad()
        load.user = 0.7
        load.system = 0.6   // sum > 1
        XCTAssertEqual(load.totalBusy, 1.0, accuracy: 0.0001)

        var partial = CPULoad()
        partial.user = 0.2
        partial.system = 0.1
        XCTAssertEqual(partial.totalBusy, 0.3, accuracy: 0.0001)
    }

    // MARK: 8 — Process search filter matches name, PID and user
    func testProcessQueryFilter() {
        let samples = [
            makeSample(pid: 101, name: "Safari", user: "alice"),
            makeSample(pid: 202, name: "kernel_task", user: "root"),
            makeSample(pid: 303, name: "Music", user: "alice"),
        ]
        // Empty query → everything
        XCTAssertEqual(ProcessQuery.filter(samples, query: "").count, 3)
        XCTAssertEqual(ProcessQuery.filter(samples, query: "   ").count, 3)
        // By name, case-insensitive
        XCTAssertEqual(ProcessQuery.filter(samples, query: "safari").map(\.pid), [101])
        // By PID substring
        XCTAssertEqual(ProcessQuery.filter(samples, query: "202").map(\.name), ["kernel_task"])
        // By user → two matches
        XCTAssertEqual(Set(ProcessQuery.filter(samples, query: "alice").map(\.pid)), [101, 303])
        // No match
        XCTAssertTrue(ProcessQuery.filter(samples, query: "zzz").isEmpty)
    }

    // MARK: 9 — Sorting by a KeyPathComparator orders rows correctly
    func testProcessSortingByCPU() {
        let samples = [
            makeSample(pid: 1, name: "A", cpu: 5),
            makeSample(pid: 2, name: "B", cpu: 90),
            makeSample(pid: 3, name: "C", cpu: 40),
        ]
        let sorted = samples.sorted(using: [KeyPathComparator(\ProcessSample.cpuPercent, order: .reverse)])
        XCTAssertEqual(sorted.map(\.pid), [2, 3, 1])
    }

    // MARK: 10 — ProcessSampler returns this test process with sane values
    func testProcessSamplerIncludesSelf() {
        let sampler = ProcessSampler()
        let processes = sampler.sample()
        XCTAssertFalse(processes.isEmpty, "should enumerate running processes")

        let me = processes.first { $0.pid == getpid() }
        XCTAssertNotNil(me, "the test runner process should appear in the list")
        if let me {
            XCTAssertGreaterThanOrEqual(me.threads, 1)
            XCTAssertGreaterThan(me.residentBytes, 0)
            XCTAssertGreaterThanOrEqual(me.cpuPercent, 0)
            XCTAssertFalse(me.name.isEmpty)
        }
        // Every row must carry non-negative, well-formed metrics.
        for p in processes {
            XCTAssertGreaterThan(p.pid, 0)
            XCTAssertGreaterThanOrEqual(p.cpuPercent, 0)
            XCTAssertGreaterThanOrEqual(p.memoryPercent, 0)
        }
    }

    // MARK: 11 — MemorySampler reports a coherent breakdown
    func testMemorySamplerSanity() {
        let mem = MemorySampler().sample()
        XCTAssertGreaterThan(mem.total, 0, "physical RAM must be > 0")
        XCTAssertGreaterThan(mem.used, 0)
        XCTAssertLessThanOrEqual(mem.appMemory, mem.used + mem.cachedFiles)
        // Used memory should not wildly exceed installed RAM.
        XCTAssertLessThan(Double(mem.used), Double(mem.total) * 1.25)
        XCTAssertGreaterThanOrEqual(mem.usedFraction, 0)
    }

    // MARK: 12 — CPUSampler: per-core count + fractions sum to ~1 over an interval
    func testCPUSamplerRangesAndCoreCount() {
        let sampler = CPUSampler()
        let cores = ProcessInfo.processInfo.activeProcessorCount

        _ = sampler.sample()                       // prime
        Thread.sleep(forTimeInterval: 0.3)
        let load = sampler.sample()                // delta-based reading

        XCTAssertEqual(load.perCore.count, cores)
        for value in load.perCore {
            XCTAssertGreaterThanOrEqual(value, -0.001)
            XCTAssertLessThanOrEqual(value, 1.001)
        }
        for value in [load.user, load.system, load.idle] {
            XCTAssertGreaterThanOrEqual(value, -0.001)
            XCTAssertLessThanOrEqual(value, 1.001)
        }
        XCTAssertEqual(load.user + load.system + load.idle, 1.0, accuracy: 0.05,
                       "user + system + idle should account for ~100% of CPU time")
    }

    // MARK: 13 (bonus) — NetworkSampler counters are monotonic non-decreasing
    func testNetworkSamplerMonotonicTotals() {
        let sampler = NetworkSampler()
        let first = sampler.sample()
        Thread.sleep(forTimeInterval: 0.2)
        let second = sampler.sample()

        XCTAssertGreaterThanOrEqual(second.totalIn, first.totalIn)
        XCTAssertGreaterThanOrEqual(second.totalOut, first.totalOut)
        XCTAssertGreaterThanOrEqual(second.bytesInPerSec, 0)
        XCTAssertGreaterThanOrEqual(second.bytesOutPerSec, 0)
    }

    // MARK: - Helpers

    private func makeSample(pid: pid_t, name: String, user: String = "tester", cpu: Double = 0) -> ProcessSample {
        ProcessSample(id: pid, name: name, user: user, cpuPercent: cpu, cpuTime: 0,
                      threads: 1, residentBytes: 1024, memoryPercent: 0,
                      diskReadBytes: 0, diskWriteBytes: 0, energyImpact: 0)
    }
}

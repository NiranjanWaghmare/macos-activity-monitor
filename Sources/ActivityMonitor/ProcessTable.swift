import SwiftUI

/// The sortable, searchable process list. Columns change with the active tab,
/// just like Activity Monitor.
struct ProcessTableView: View {
    @EnvironmentObject var monitor: SystemMonitor
    let tab: Tab
    let searchText: String
    @Binding var selection: pid_t?
    @Binding var sortOrder: [KeyPathComparator<ProcessSample>]

    private var rows: [ProcessSample] {
        ProcessQuery.filter(monitor.processes, query: searchText).sorted(using: sortOrder)
    }

    var body: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            nameColumn
            metricColumns
            commonColumns
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }

    // MARK: - Column groups (split out to keep the type-checker happy)

    private typealias Col = KeyPathComparator<ProcessSample>

    @TableColumnBuilder<ProcessSample, Col>
    private var nameColumn: some TableColumnContent<ProcessSample, Col> {
        TableColumn("Process Name", value: \.name) { p in
            Text(p.name).lineLimit(1).truncationMode(.middle)
        }
        .width(min: 160, ideal: 240)
    }

    @TableColumnBuilder<ProcessSample, Col>
    private var metricColumns: some TableColumnContent<ProcessSample, Col> {
        switch tab {
        case .cpu:
            TableColumn("% CPU", value: \.cpuPercent) { p in
                Text(String(format: "%.1f", p.cpuPercent)).monospacedDigit()
            }
            .width(min: 60, ideal: 70)
            TableColumn("CPU Time", value: \.cpuTime) { p in
                Text(Self.cpuTimeString(p.cpuTime)).monospacedDigit()
            }
            .width(min: 70, ideal: 90)
            TableColumn("Threads", value: \.threads) { p in
                Text(String(p.threads)).monospacedDigit()
            }
            .width(min: 50, ideal: 60)
        case .memory:
            TableColumn("Memory", value: \.residentBytes) { p in
                Text(ByteFormat.string(p.residentBytes)).monospacedDigit()
            }
            .width(min: 80, ideal: 100)
            TableColumn("% Mem", value: \.memoryPercent) { p in
                Text(String(format: "%.1f", p.memoryPercent)).monospacedDigit()
            }
            .width(min: 55, ideal: 65)
            TableColumn("Threads", value: \.threads) { p in
                Text(String(p.threads)).monospacedDigit()
            }
            .width(min: 50, ideal: 60)
        case .energy:
            TableColumn("Energy Impact", value: \.energyImpact) { p in
                Text(String(format: "%.1f", p.energyImpact)).monospacedDigit()
            }
            .width(min: 90, ideal: 110)
            TableColumn("% CPU", value: \.cpuPercent) { p in
                Text(String(format: "%.1f", p.cpuPercent)).monospacedDigit()
            }
            .width(min: 60, ideal: 70)
        case .disk:
            TableColumn("Bytes Read", value: \.diskReadBytes) { p in
                Text(ByteFormat.string(p.diskReadBytes)).monospacedDigit()
            }
            .width(min: 80, ideal: 100)
            TableColumn("Bytes Written", value: \.diskWriteBytes) { p in
                Text(ByteFormat.string(p.diskWriteBytes)).monospacedDigit()
            }
            .width(min: 90, ideal: 110)
        case .network:
            TableColumn("% CPU", value: \.cpuPercent) { p in
                Text(String(format: "%.1f", p.cpuPercent)).monospacedDigit()
            }
            .width(min: 60, ideal: 70)
            TableColumn("Threads", value: \.threads) { p in
                Text(String(p.threads)).monospacedDigit()
            }
            .width(min: 50, ideal: 60)
        }
    }

    @TableColumnBuilder<ProcessSample, Col>
    private var commonColumns: some TableColumnContent<ProcessSample, Col> {
        TableColumn("PID", value: \.pid) { p in
            Text(String(p.pid)).monospacedDigit().foregroundStyle(.secondary)
        }
        .width(min: 50, ideal: 60)
        TableColumn("User", value: \.user) { p in
            Text(p.user).foregroundStyle(.secondary).lineLimit(1)
        }
        .width(min: 70, ideal: 100)
    }

    /// Formats CPU seconds as M:SS.cc, matching Activity Monitor.
    static func cpuTimeString(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        let centis = Int((seconds - Double(totalSeconds)) * 100)
        return String(format: "%d:%02d.%02d", minutes, secs, centis)
    }
}

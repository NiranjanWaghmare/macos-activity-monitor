import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @State private var tab: Tab = .cpu
    @State private var searchText = ""
    @State private var selection: pid_t?
    @State private var sortOrder = [KeyPathComparator(\ProcessSample.cpuPercent, order: .reverse)]
    @State private var confirmForceQuit = false

    var body: some View {
        VStack(spacing: 0) {
            ProcessTableView(tab: tab,
                             searchText: searchText,
                             selection: $selection,
                             sortOrder: $sortOrder)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(height: 150)
                .background(.background)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    confirmForceQuit = true
                } label: {
                    Image(systemName: "xmark.octagon")
                        .foregroundStyle(selection == nil ? Color.secondary : Color.red)
                }
                .help("Quit the selected process")
                .disabled(selection == nil)
            }

            ToolbarItem(placement: .principal) {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .onChange(of: tab) { _, newTab in applyDefaultSort(for: newTab) }
            }

            ToolbarItem(placement: .automatic) {
                TextField("Search", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }
        }
        .confirmationDialog("Quit Process", isPresented: $confirmForceQuit, presenting: selectedProcess) { proc in
            Button("Quit") { monitor.quit(pid: proc.pid, force: false) }
            Button("Force Quit", role: .destructive) { monitor.quit(pid: proc.pid, force: true) }
            Button("Cancel", role: .cancel) {}
        } message: { proc in
            Text("Are you sure you want to quit “\(proc.name)” (PID \(proc.pid))?")
        }
    }

    private var selectedProcess: ProcessSample? {
        guard let selection else { return nil }
        return monitor.processes.first { $0.pid == selection }
    }

    private func applyDefaultSort(for tab: Tab) {
        switch tab {
        case .cpu, .network:
            sortOrder = [KeyPathComparator(\ProcessSample.cpuPercent, order: .reverse)]
        case .memory:
            sortOrder = [KeyPathComparator(\ProcessSample.residentBytes, order: .reverse)]
        case .energy:
            sortOrder = [KeyPathComparator(\ProcessSample.energyImpact, order: .reverse)]
        case .disk:
            sortOrder = [KeyPathComparator(\ProcessSample.diskWriteBytes, order: .reverse)]
        }
    }

    // MARK: - Footer (per-tab summary, like Activity Monitor's bottom panel)

    @ViewBuilder
    private var footer: some View {
        switch tab {
        case .cpu: cpuFooter
        case .memory: memoryFooter
        case .energy: energyFooter
        case .disk: diskFooter
        case .network: networkFooter
        }
    }

    private var cpuFooter: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                StatBlock(label: "System", value: percent(monitor.cpu.system), color: .red)
                StatBlock(label: "User", value: percent(monitor.cpu.user), color: .blue)
                StatBlock(label: "Idle", value: percent(monitor.cpu.idle))
            }
            VStack(alignment: .leading, spacing: 8) {
                StatBlock(label: "Processes", value: String(monitor.processCount))
                StatBlock(label: "Threads", value: String(monitor.threadCount))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("CPU Load").font(.system(size: 10)).foregroundStyle(.secondary)
                CoreBars(cores: monitor.cpu.perCore)
                    .frame(height: 70)
            }
            .frame(maxWidth: 220)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("History").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    LegendDot(color: .accentColor, text: "% Used")
                }
                AreaGraph(values: monitor.cpuHistory.values, color: .accentColor, maxValue: 1)
            }
        }
    }

    private var memoryFooter: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                StatBlock(label: "Physical Memory", value: ByteFormat.string(monitor.memory.total))
                StatBlock(label: "Memory Used", value: ByteFormat.string(monitor.memory.used), color: .blue)
                StatBlock(label: "Cached Files", value: ByteFormat.string(monitor.memory.cachedFiles))
            }
            VStack(alignment: .leading, spacing: 8) {
                StatBlock(label: "App Memory", value: ByteFormat.string(monitor.memory.appMemory))
                StatBlock(label: "Wired Memory", value: ByteFormat.string(monitor.memory.wired))
                StatBlock(label: "Compressed", value: ByteFormat.string(monitor.memory.compressed))
            }
            VStack(alignment: .leading, spacing: 8) {
                StatBlock(label: "Swap Used", value: ByteFormat.string(monitor.memory.swapUsed))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Memory Pressure").font(.system(size: 10)).foregroundStyle(.secondary)
                    PressureBar(fraction: monitor.memory.usedFraction)
                        .frame(width: 180)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("History").font(.system(size: 10)).foregroundStyle(.secondary)
                AreaGraph(values: monitor.memoryHistory.values, color: .green, maxValue: 1)
            }
        }
    }

    private var energyFooter: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                StatBlock(label: "Total Energy Impact",
                          value: String(format: "%.1f", monitor.processes.reduce(0) { $0 + $1.energyImpact }),
                          color: .orange)
                StatBlock(label: "Processes", value: String(monitor.processCount))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Note").font(.system(size: 10)).foregroundStyle(.secondary)
                Text("Energy Impact is an approximation derived from CPU usage and thread count. macOS's real energy model relies on private power-metering APIs.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var diskFooter: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                StatBlock(label: "Reads/sec", value: ByteFormat.rate(monitor.disk.readBytesPerSec), color: .blue)
                StatBlock(label: "Writes/sec", value: ByteFormat.rate(monitor.disk.writeBytesPerSec), color: .red)
            }
            VStack(alignment: .leading, spacing: 8) {
                StatBlock(label: "Data Read", value: ByteFormat.string(monitor.disk.totalRead))
                StatBlock(label: "Data Written", value: ByteFormat.string(monitor.disk.totalWritten))
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("History").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    LegendDot(color: .blue, text: "Reads")
                    LegendDot(color: .red, text: "Writes")
                }
                ZStack {
                    AreaGraph(values: monitor.diskReadHistory.values, color: .blue, maxValue: nil)
                    AreaGraph(values: monitor.diskWriteHistory.values, color: .red, maxValue: nil)
                        .opacity(0.7)
                }
            }
        }
    }

    private var networkFooter: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                StatBlock(label: "Data received/sec", value: ByteFormat.rate(monitor.network.bytesInPerSec), color: .blue)
                StatBlock(label: "Data sent/sec", value: ByteFormat.rate(monitor.network.bytesOutPerSec), color: .red)
            }
            VStack(alignment: .leading, spacing: 8) {
                StatBlock(label: "Data received", value: ByteFormat.string(monitor.network.totalIn))
                StatBlock(label: "Data sent", value: ByteFormat.string(monitor.network.totalOut))
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("History").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    LegendDot(color: .blue, text: "In")
                    LegendDot(color: .red, text: "Out")
                }
                ZStack {
                    AreaGraph(values: monitor.networkInHistory.values, color: .blue, maxValue: nil)
                    AreaGraph(values: monitor.networkOutHistory.values, color: .red, maxValue: nil)
                        .opacity(0.7)
                }
            }
        }
    }

    private func percent(_ fraction: Double) -> String {
        String(format: "%.1f%%", fraction * 100)
    }
}

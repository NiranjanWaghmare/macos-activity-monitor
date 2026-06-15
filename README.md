# Activity Monitor (macOS)

A native SwiftUI re-creation of macOS **Activity Monitor**, with a global
**Ctrl + Shift + Esc** hotkey to summon it — the same combo that opens Task
Manager on Windows.

All data is read live from the kernel via Mach and `libproc`; no shell-outs.

## Features

| Tab | What it shows |
| --- | --- |
| **CPU** | Per-process %CPU, CPU time, threads; System/User/Idle split, per-core load bars, and a live history graph. |
| **Memory** | Resident memory & %RAM per process; Physical/Used/Cached/Swap breakdown, App/Wired/Compressed, and a Memory Pressure bar. |
| **Energy** | Approximate per-process energy impact (CPU- and thread-weighted). |
| **Disk** | Per-process bytes read/written; system reads/writes per second with a history graph. |
| **Network** | System data sent/received per second and totals, with a history graph. |

Plus, like the real thing:

- **Sortable columns** — click any header (columns change per tab).
- **Search** — filter by process name, PID, or user.
- **Quit / Force Quit** — select a row and hit the ✕ in the toolbar (`SIGTERM` / `SIGKILL`).
- **Update frequency** — 1s / 2s / 5s (View-style picker in the menu bar).
- **Global hotkey** — **Ctrl+Shift+Esc** brings the window to the front from anywhere. The app keeps running in the background when you close the window so the hotkey stays live.

## Run it

```bash
# Quick dev run
swift run

# Build a double-clickable .app bundle
./build-app.sh
open ./ActivityMonitor.app
```

Then press **Ctrl+Shift+Esc** to summon the window.

## How the stats are gathered

- **CPU** — `host_statistics(HOST_CPU_LOAD_INFO)` and `host_processor_info(PROCESSOR_CPU_LOAD_INFO)`, diffing tick counters between samples.
- **Memory** — `host_statistics64(HOST_VM_INFO64)` for the VM page breakdown; `sysctl(vm.swapusage)` for swap.
- **Processes** — `proc_listallpids` → `proc_pidinfo(PROC_PIDTASKINFO)` for CPU time / memory / threads; `proc_pid_rusage` for disk I/O; `sysctl(KERN_PROC_PID)` + `getpwuid` for the owner. %CPU is the change in consumed CPU time over the sampling interval.
- **Network** — `getifaddrs` interface byte/packet counters, diffed over time.

## Caveats

- **Energy Impact** is an approximation. Apple's real metric uses private power-metering APIs (`IOReport`), which aren't available to third-party apps.
- **Per-process network** isn't shown — there's no public API for it (Activity Monitor itself uses the private `nettop`/NetworkStatistics framework). The Network tab reports system-wide throughput instead.
- Some system processes owned by other users may report partial data unless the app is run with elevated privileges.

## Project layout

```
Sources/ActivityMonitor/
  App.swift            @main app, AppDelegate, activation policy
  HotKey.swift         Carbon RegisterEventHotKey wrapper (no Accessibility prompt)
  Model.swift          Data types + byte formatting
  Samplers.swift       CPU / Memory / Network low-level sampling
  ProcessSampler.swift Per-process enumeration & delta-based %CPU
  SystemMonitor.swift  ObservableObject orchestrator (timer + @Published state)
  ContentView.swift    Main layout, toolbar tabs, per-tab footers
  ProcessTable.swift   The sortable/searchable table
  Graphs.swift         AreaGraph, CoreBars, PressureBar, StatBlock
```

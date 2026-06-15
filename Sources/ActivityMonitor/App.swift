import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Custom entry point so `--selftest` can exercise the sampling code from the
/// command line without launching the GUI.
@main
enum EntryPoint {
    static func main() {
        if CommandLine.arguments.contains("--selftest") {
            SelfTest.run()
            return
        }
        ActivityMonitorApp.main()
    }
}

struct ActivityMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitor = SystemMonitor()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(monitor)
                .frame(minWidth: 760, minHeight: 460)
                .onAppear { monitor.start() }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}  // no "New Window"
            CommandGroup(after: .toolbar) {
                Picker("Update Frequency", selection: $monitor.updateInterval) {
                    Text("Very Often (1s)").tag(1.0)
                    Text("Often (2s)").tag(2.0)
                    Text("Normally (5s)").tag(5.0)
                }
            }
        }
    }
}

/// Owns app-level concerns: activation policy and the global summon hotkey.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotKey = HotKey()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        // Ctrl+Shift+Esc — the Windows Task Manager combo — summons the window.
        hotKey.onPress = { [weak self] in self?.summon() }
        hotKey.register(keyCode: UInt32(kVK_Escape),
                        modifiers: UInt32(controlKey | shiftKey))

        summon()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false  // keep running in the background so the hotkey stays live
    }

    /// Bring the app to the foreground, reopening the window if it was closed.
    private func summon() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
            window.deminiaturize(nil)
        } else {
            // Window was closed entirely — ask AppKit to recreate the scene.
            NSApp.sendAction(#selector(NSApplication.unhide(_:)), to: nil, from: nil)
        }
    }
}

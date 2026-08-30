import AppKit
import SwiftUI

@main
@MainActor
struct CopisteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings: AppSettings
    @StateObject private var runner: ActionRunner
    private let hotkeys: HotkeyManager

    init() {
        let settings = AppSettings()
        let runner = ActionRunner()
        self.hotkeys = HotkeyManager(settings: settings, runner: runner)
        _settings = StateObject(wrappedValue: settings)
        _runner = StateObject(wrappedValue: runner)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(runner: self.runner)
        } label: {
            StatusLabel(runner: self.runner)
                .background(SettingsOpener())
        }

        Settings {
            SettingsView(settings: self.settings)
        }
        .windowResizability(.contentSize)
    }
}

/// The icon reports the outcome of the last action for a moment, so a shortcut pressed with
/// the menu closed is never silent.
@MainActor
private struct StatusLabel: View {
    @ObservedObject var runner: ActionRunner

    var body: some View {
        Image(nsImage: self.runner.flash?.isFailure == true ? MenuIcon.failure : MenuIcon.normal)
            .opacity(self.runner.flash != nil ? 0.45 : 1)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    /// An accessory app has no windows to restore, so reopening it from Finder or the Dock
    /// would otherwise do nothing at all.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NotificationCenter.default.post(name: .copisteOpenSettings, object: nil)
        return false
    }
}

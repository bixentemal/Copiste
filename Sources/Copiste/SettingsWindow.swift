import AppKit
import SwiftUI

extension Notification.Name {
    /// Posted to open Settings from anywhere: the menu, or reopening the app in Finder.
    static let copisteOpenSettings = Notification.Name("copisteOpenSettings")
}

/// Opens the Settings window and puts it in front.
///
/// Copiste runs as an `.accessory` app, so it is never the active application. Opening a
/// window from that state does not activate the app, and macOS leaves the new window behind
/// whatever the user was working in — the window is there, just not visible. Activating and
/// raising it explicitly is the only way to get it in front.
///
/// The `openSettings` environment action exists only inside a `View`, and a `MenuBarExtra`'s
/// menu content is torn down as the menu closes, so the request is posted as a notification
/// and serviced by `SettingsOpener`, which lives in the always-present status item label.
@MainActor
struct SettingsOpener: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        EmptyView()
            .onReceive(NotificationCenter.default.publisher(for: .copisteOpenSettings)) { _ in
                self.openSettings()
                NSApp.activate()
                self.raiseSettingsWindow()
            }
    }

    /// SwiftUI creates the window asynchronously, so it may not exist yet when the action
    /// returns. Poll briefly rather than guess at a delay.
    private func raiseSettingsWindow() {
        Task { @MainActor in
            for _ in 0..<20 {
                if let window = NSApp.windows.first(where: {
                    $0.identifier?.rawValue.contains("Settings") == true
                }) {
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                    return
                }
                try? await Task.sleep(for: .milliseconds(25))
            }
        }
    }
}

import AppKit

/// Brings Copiste and one of its windows to the front.
///
/// Copiste runs as an `.accessory` app, so it is never the active application and a window it
/// opens stays behind whatever the user was working in. The cooperative `NSApp.activate()`
/// is not enough from a status-menu click — macOS declines the request and the window opens
/// invisibly — so this uses the forceful variant, which is what an explicit user action on
/// the menu warrants.
@MainActor
enum WindowRaiser {
    /// Runs `open`, then raises whichever window it produced. The window is identified as the
    /// one that was not there beforehand, rather than by a private class or localized title,
    /// and is polled for because SwiftUI and AppKit both create windows asynchronously.
    static func present(_ open: () -> Void) {
        let existing = Set(NSApp.windows.map(ObjectIdentifier.init))
        open()
        Task { @MainActor in
            for _ in 0..<20 {
                if let window = NSApp.windows.first(where: { !existing.contains(ObjectIdentifier($0)) }) {
                    self.activate()
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                    return
                }
                try? await Task.sleep(for: .milliseconds(25))
            }
        }
    }

    /// Raises Copiste above the app the user is in.
    ///
    /// `activate(ignoringOtherApps:)` is deprecated, and its replacements were both tried:
    /// `NSApp.activate()` and `NSRunningApplication.current.activate(options:)` leave the
    /// window behind the frontmost app when called from a status-menu click, deferred or
    /// not — macOS declines cooperative activation for an app that is never active. The
    /// deprecated call is the only one that works, and a menu click is an explicit request
    /// from the user, which is what it is for.
    static func activate() {
        NSApp.activate(ignoringOtherApps: true)
    }
}

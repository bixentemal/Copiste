import AppKit
import ApplicationServices

/// The permission gate, injectable so tests can exercise the paste path without granting
/// Accessibility to the test runner — and without triggering a system prompt.
@MainActor
protocol AccessibilityGate {
    var isTrusted: Bool { get }
    func requestPermission()
}

struct SystemAccessibility: AccessibilityGate {
    var isTrusted: Bool {
        Accessibility.isTrusted
    }

    func requestPermission() {
        Accessibility.requestPermission()
    }
}

/// Accessibility permission is needed only to synthesize the paste keystroke, so it is
/// checked when a paste is attempted rather than polled in the background.
@MainActor
enum Accessibility {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt, then opens the settings pane in case the prompt was
    /// suppressed because the user dismissed it in an earlier build.
    static func requestPermission() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as NSDictionary)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            self.openSystemSettings()
        }
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }
}

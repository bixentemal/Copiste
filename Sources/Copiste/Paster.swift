import AppKit
import Carbon.HIToolbox

/// Sends a paste to whatever app is frontmost. Injectable so tests never fire real keystrokes.
@MainActor
protocol Pasting {
    func paste()
}

/// Synthesizes ⌘V. Requires Accessibility permission; without it the events are discarded
/// silently by the system, which is why the permission is checked before this runs.
struct KeystrokePaster: Pasting {
    func paste() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let keyCode = CGKeyCode(kVK_ANSI_V)

        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        down?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)

        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        up?.flags = .maskCommand
        up?.post(tap: .cghidEventTap)
    }
}

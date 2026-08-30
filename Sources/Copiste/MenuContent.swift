import SwiftUI

@MainActor
struct MenuContent: View {
    @ObservedObject var runner: ActionRunner

    var body: some View {
        Button("Paste Text from Image") {
            Task { await self.runner.run(.paste) }
        }
        .keyboardShortcut("o", modifiers: [.command, .option])
        .disabled(!self.runner.hasImage)

        Button("Copy Text from Image") {
            Task { await self.runner.run(.copy) }
        }
        .keyboardShortcut("o", modifiers: [.command, .option, .shift])
        .disabled(!self.runner.hasImage)

        Divider()

        Text(self.runner.displayStatus.message)

        Divider()

        Button("Settings…") {
            NotificationCenter.default.post(name: .copisteOpenSettings, object: nil)
        }
        .keyboardShortcut(",", modifiers: .command)
        Button("Quit Copiste") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}

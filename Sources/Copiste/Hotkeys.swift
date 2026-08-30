import KeyboardShortcuts

@MainActor
extension KeyboardShortcuts.Name {
    static let pasteTextFromImage = Self("pasteTextFromImage")
    static let copyTextFromImage = Self("copyTextFromImage")
}

/// Registers the two global shortcuts and keeps them in step with the settings toggles.
@MainActor
final class HotkeyManager {
    private let settings: AppSettings
    private let runner: ActionRunner

    init(settings: AppSettings, runner: ActionRunner) {
        self.settings = settings
        self.runner = runner
        self.settings.hotkeyEnablementChanged = { [weak self] in self?.refresh() }
        self.installDefaultsIfUnset()
        self.registerHandlers()
        self.refresh()
    }

    private func installDefaultsIfUnset() {
        if KeyboardShortcuts.getShortcut(for: .pasteTextFromImage) == nil {
            KeyboardShortcuts.setShortcut(.init(.o, modifiers: [.command, .option]), for: .pasteTextFromImage)
        }
        if KeyboardShortcuts.getShortcut(for: .copyTextFromImage) == nil {
            KeyboardShortcuts.setShortcut(
                .init(.o, modifiers: [.command, .option, .shift]),
                for: .copyTextFromImage)
        }
    }

    private func registerHandlers() {
        KeyboardShortcuts.onKeyUp(for: .pasteTextFromImage) { [weak self] in
            guard let self else { return }
            Task { await self.runner.run(.paste) }
        }
        KeyboardShortcuts.onKeyUp(for: .copyTextFromImage) { [weak self] in
            guard let self else { return }
            Task { await self.runner.run(.copy) }
        }
    }

    private func refresh() {
        if self.settings.pasteTextHotkeyEnabled {
            KeyboardShortcuts.enable(.pasteTextFromImage)
        } else {
            KeyboardShortcuts.disable(.pasteTextFromImage)
        }
        if self.settings.copyTextHotkeyEnabled {
            KeyboardShortcuts.enable(.copyTextFromImage)
        } else {
            KeyboardShortcuts.disable(.copyTextFromImage)
        }
    }
}

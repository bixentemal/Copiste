import KeyboardShortcuts
import ServiceManagement
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("pasteTextHotkeyEnabled") var pasteTextHotkeyEnabled: Bool = true {
        didSet { self.hotkeyEnablementChanged?() }
    }

    @AppStorage("copyTextHotkeyEnabled") var copyTextHotkeyEnabled: Bool = true {
        didSet { self.hotkeyEnablementChanged?() }
    }

    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false {
        didSet { Self.setLaunchAtLogin(self.launchAtLogin) }
    }

    var hotkeyEnablementChanged: (() -> Void)?

    private static func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Copiste: could not update launch at login: \(error.localizedDescription)")
        }
    }
}

@MainActor
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var isTrusted = Accessibility.isTrusted

    var body: some View {
        Form {
            Section {
                ShortcutRow(
                    title: "Paste Text from Image",
                    subtitle: "Recognize the clipboard image and type the text into the frontmost app.",
                    isEnabled: self.$settings.pasteTextHotkeyEnabled,
                    shortcut: .pasteTextFromImage)
                ShortcutRow(
                    title: "Copy Text from Image",
                    subtitle: "Recognize the clipboard image and leave the text on the clipboard.",
                    isEnabled: self.$settings.copyTextHotkeyEnabled,
                    shortcut: .copyTextFromImage)
            } header: {
                Text("Global shortcuts")
            }

            Section {
                Toggle("Launch Copiste at login", isOn: self.$settings.launchAtLogin)
            }

            Section {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: self.isTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(self.isTrusted ? Color.green : Color.orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(self.isTrusted ? "Accessibility permission granted" : "Accessibility permission needed")
                        Text("Only pasting needs it. Copying text to the clipboard works without.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open System Settings…") { Accessibility.openSystemSettings() }
                }
            } header: {
                Text("Permissions")
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .onAppear { self.isTrusted = Accessibility.isTrusted }
    }
}

@MainActor
private struct ShortcutRow: View {
    let title: String
    let subtitle: String
    @Binding var isEnabled: Bool
    let shortcut: KeyboardShortcuts.Name

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle(self.title, isOn: self.$isEnabled)
                    .toggleStyle(.checkbox)
                Spacer()
                KeyboardShortcuts.Recorder("", name: self.shortcut)
                    .labelsHidden()
                    .opacity(self.isEnabled ? 1 : 0.4)
                    .disabled(!self.isEnabled)
            }
            Text(self.subtitle)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}

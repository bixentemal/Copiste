import AppKit
import SwiftUI

/// What the last action did. Shown in the menu, and drives the icon flash.
enum ActionStatus: Equatable {
    case ready
    case recognized(lines: Int)
    case noImage
    case noText
    case unreadableImage
    case unreadableFile
    case needsAccessibility

    var message: String {
        switch self {
        case .ready: "Ready"
        case let .recognized(lines): "Recognized \(lines) line\(lines == 1 ? "" : "s")"
        case .noImage: "No image on the clipboard"
        case .noText: "No text found in the image"
        case .unreadableImage: "Could not read the image"
        case .unreadableFile: "Could not open the copied file"
        case .needsAccessibility: "Accessibility permission needed to paste"
        }
    }

    var isFailure: Bool {
        switch self {
        case .ready, .recognized: false
        default: true
        }
    }
}

enum Delivery {
    /// Type the text into the frontmost app, then put the image back on the clipboard.
    case paste
    /// Leave the text on the clipboard for the user to paste themselves.
    case copy
}

/// Runs the one pipeline both shortcuts share: read an image, recognize it, deliver the text.
@MainActor
final class ActionRunner: ObservableObject {
    /// Long enough for the frontmost app to service the synthetic ⌘V before the clipboard
    /// changes under it.
    static let restoreDelay = Duration.milliseconds(200)
    /// How long the menu-bar icon signals the outcome of an action.
    static let flashDuration = Duration.seconds(1)

    @Published private(set) var status: ActionStatus = .ready
    @Published private(set) var flash: ActionStatus?

    private let pasteboard: NSPasteboard
    private let paster: any Pasting
    private let accessibility: any AccessibilityGate
    /// Injected so delivery can be tested without running text recognition.
    private let recognize: @Sendable (Data) async throws -> String
    private var isRunning = false
    private var flashTask: Task<Void, Never>?

    init(
        pasteboard: NSPasteboard = .general,
        paster: any Pasting = KeystrokePaster(),
        accessibility: any AccessibilityGate = SystemAccessibility(),
        recognize: @escaping @Sendable (Data) async throws -> String = TextRecognizer.recognize)
    {
        self.pasteboard = pasteboard
        self.paster = paster
        self.accessibility = accessibility
        self.recognize = recognize
    }

    var hasImage: Bool {
        ClipboardImageSource.hasImage(on: self.pasteboard)
    }

    /// The status to show right now.
    ///
    /// A permission complaint goes stale the moment the user grants the permission, and the
    /// menu would otherwise keep reporting a problem that no longer exists — there is no
    /// further action to overwrite it until the user tries again. Recomputed per render, the
    /// same way `hasImage` is.
    var displayStatus: ActionStatus {
        if self.status == .needsAccessibility, self.accessibility.isTrusted {
            return .ready
        }
        return self.status
    }

    func run(_ delivery: Delivery) async {
        // A second invocation while one is in flight would race the clipboard restore.
        guard !self.isRunning else { return }
        self.isRunning = true
        defer { self.isRunning = false }

        if delivery == .paste, !self.accessibility.isTrusted {
            self.finish(.needsAccessibility)
            self.accessibility.requestPermission()
            return
        }

        let image: ClipboardImageSource.Image
        switch ClipboardImageSource.read(from: self.pasteboard) {
        case let .image(found): image = found
        case .none: return self.finish(.noImage)
        case .unreadableFile: return self.finish(.unreadableFile)
        }

        let text: String
        do {
            text = try await self.recognize(image.data)
        } catch {
            return self.finish(.unreadableImage)
        }
        guard !text.isEmpty else { return self.finish(.noText) }

        self.write(text)
        if delivery == .paste {
            self.paster.paste()
            try? await Task.sleep(for: Self.restoreDelay)
            self.restore(image)
        }
        self.finish(.recognized(lines: text.components(separatedBy: "\n").count))
    }

    private func write(_ text: String) {
        self.pasteboard.clearContents()
        self.pasteboard.setString(text, forType: .string)
    }

    private func restore(_ image: ClipboardImageSource.Image) {
        self.pasteboard.clearContents()
        self.pasteboard.setData(image.restoreData, forType: image.restoreType)
    }

    private func finish(_ status: ActionStatus) {
        self.status = status
        self.flash = status
        self.flashTask?.cancel()
        self.flashTask = Task { [weak self] in
            try? await Task.sleep(for: Self.flashDuration)
            guard !Task.isCancelled else { return }
            self?.flash = nil
        }
    }
}

import AppKit
import Testing
@testable import Copiste

/// A private pasteboard, so tests never disturb the user's clipboard.
@MainActor
private func makePasteboard() -> NSPasteboard {
    let board = NSPasteboard(name: .init("com.bixentemal.copiste.tests-\(UUID().uuidString)"))
    board.clearContents()
    return board
}

/// A 2×2 PNG, enough to be non-empty image data.
private let pngBytes: Data = {
    let image = NSImage(size: NSSize(width: 2, height: 2))
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 2, height: 2).fill()
    image.unlockFocus()
    let tiff = image.tiffRepresentation!
    return NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
}()

@Suite("Clipboard image source")
@MainActor
struct ClipboardImageSourceTests {
    @Test("Image data on the pasteboard is read and reported as available")
    func readsImageData() {
        let board = makePasteboard()
        board.setData(pngBytes, forType: .png)

        #expect(ClipboardImageSource.hasImage(on: board))
        guard case let .image(image) = ClipboardImageSource.read(from: board) else {
            Issue.record("expected an image")
            return
        }
        #expect(image.data == pngBytes)
        #expect(image.restoreType == .png)
        #expect(image.restoreData == pngBytes)
    }

    @Test("PNG is preferred over TIFF when both are present")
    func prefersPNG() {
        let board = makePasteboard()
        board.declareTypes([.tiff, .png], owner: nil)
        board.setData(Data([0x4D, 0x4D]), forType: .tiff)
        board.setData(pngBytes, forType: .png)

        guard case let .image(image) = ClipboardImageSource.read(from: board) else {
            Issue.record("expected an image")
            return
        }
        #expect(image.restoreType == .png)
    }

    @Test("An image file copied in Finder is read from disk, restoring the file reference")
    func readsFileURL() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("copiste-\(UUID().uuidString).png")
        try pngBytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let board = makePasteboard()
        let urlData = Data(url.absoluteString.utf8)
        board.setData(urlData, forType: .fileURL)

        #expect(ClipboardImageSource.hasImage(on: board))
        guard case let .image(image) = ClipboardImageSource.read(from: board) else {
            Issue.record("expected an image")
            return
        }
        #expect(image.data == pngBytes)
        #expect(image.restoreType == .fileURL)
        #expect(image.restoreData == urlData, "the user's file reference must be what goes back")
    }

    @Test("A non-image file is ignored")
    func ignoresNonImageFile() {
        let board = makePasteboard()
        board.setData(Data("file:///tmp/notes.txt".utf8), forType: .fileURL)

        #expect(!ClipboardImageSource.hasImage(on: board))
        guard case .none = ClipboardImageSource.read(from: board) else {
            Issue.record("expected no image")
            return
        }
    }

    @Test("An image file that cannot be opened is reported distinctly")
    func reportsUnreadableFile() {
        let board = makePasteboard()
        board.setData(Data("file:///tmp/copiste-does-not-exist.png".utf8), forType: .fileURL)

        guard case .unreadableFile = ClipboardImageSource.read(from: board) else {
            Issue.record("expected unreadableFile")
            return
        }
    }

    @Test("Text on the clipboard is not an image")
    func ignoresText() {
        let board = makePasteboard()
        board.setString("just some text", forType: .string)
        #expect(!ClipboardImageSource.hasImage(on: board))
    }
}

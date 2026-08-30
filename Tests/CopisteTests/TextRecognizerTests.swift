import AppKit
import Testing
@testable import Copiste

/// Renders lines of text into a PNG, so recognition can be exercised for real.
@MainActor
private func renderPNG(_ lines: [(text: String, indent: Int)], size: NSSize = NSSize(width: 640, height: 320))
    -> Data
{
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: size).fill()
    let font = NSFont.monospacedSystemFont(ofSize: 26, weight: .regular)
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
    let advance = " ".size(withAttributes: attributes).width
    for (index, line) in lines.enumerated() {
        let origin = NSPoint(
            x: 40 + advance * Double(line.indent),
            y: size.height - 60 - Double(index) * 44)
        line.text.draw(at: origin, withAttributes: attributes)
    }
    image.unlockFocus()
    let tiff = image.tiffRepresentation!
    return NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
}

@Suite("Text recognition", .timeLimit(.minutes(1)))
@MainActor
struct TextRecognizerTests {
    @Test("Recognizes rendered text")
    func recognizesText() async throws {
        let png = renderPNG([("Deploy checklist", 0), ("Run the tests", 0)])
        let text = try await TextRecognizer.recognize(png)
        #expect(text.contains("Deploy checklist"))
        #expect(text.contains("Run the tests"))
    }

    @Test("Rebuilds indentation from the rendered layout")
    func rebuildsIndentation() async throws {
        let png = renderPNG([
            ("build:", 0),
            ("steps:", 2),
            ("test", 4),
        ])
        let text = try await TextRecognizer.recognize(png)
        let lines = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        try #require(lines.count == 3)
        let indents = lines.map { $0.prefix { $0 == " " }.count }
        #expect(indents[0] == 0)
        #expect(indents[1] > indents[0], "the nested line must be indented")
        #expect(indents[2] > indents[1], "the deepest line must be indented furthest")
    }

    @Test("An image with no text recognizes as empty")
    func blankImage() async throws {
        let png = renderPNG([])
        let text = try await TextRecognizer.recognize(png)
        #expect(text.isEmpty)
    }
}

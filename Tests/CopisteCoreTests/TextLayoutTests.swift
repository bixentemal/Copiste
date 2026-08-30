import CoreGraphics
import Testing
@testable import CopisteCore

/// Builds a fragment with a plausible box: `count` characters of `charWidth` each.
private func line(_ text: String, x: Double, y: Double, charWidth: Double = 12, height: Double = 20)
    -> RecognizedLine
{
    RecognizedLine(
        text: text,
        rect: CGRect(x: x, y: y, width: charWidth * Double(text.count), height: height))
}

@Suite("Reading order")
struct ReadingOrderTests {
    @Test("Fragments sort top to bottom regardless of input order")
    func sortsTopToBottom() {
        let rendered = TextLayout.render([
            line("third", x: 100, y: 100),
            line("first", x: 100, y: 300),
            line("second", x: 100, y: 200),
        ])
        #expect(rendered == "first\nsecond\nthird")
    }

    @Test("Fragments sharing a visual line merge left to right")
    func mergesSameLine() {
        let rendered = TextLayout.render([
            line("suite", x: 315, y: 330),
            line("Run the test", x: 120, y: 330),
        ])
        #expect(rendered == "Run the test suite")
    }

    @Test("A fragment below the previous line is not merged into it")
    func doesNotMergeSeparateLines() {
        let rendered = TextLayout.render([
            line("above", x: 100, y: 330),
            line("below", x: 100, y: 300),
        ])
        #expect(rendered == "above\nbelow")
    }
}

@Suite("Indentation")
struct IndentationTests {
    /// Offsets are in characters, measured from the leftmost line on the page — which is
    /// column zero by construction, so every fixture starts with one.
    private func indents(offsetsInCharacters offsets: [Double]) -> [Int] {
        let charWidth = 12.0
        let lines = ([0.0] + offsets).enumerated().map { index, offset in
            line("x", x: 100 + offset * charWidth, y: 1000 - Double(index) * 30, charWidth: charWidth)
        }
        return Array(TextLayout.indents(for: lines, characterWidth: charWidth).dropFirst())
    }

    @Test("Wobble straddling a rounding boundary renders with one shared indent")
    func straddle() {
        // Rounding each offset alone would give 2 and 3.
        let result = self.indents(offsetsInCharacters: [2.4, 2.6])
        #expect(Set(result).count == 1)
    }

    @Test("Wobble wider than the tolerance still renders as one indent")
    func wideWobble() {
        // Anchoring a level on its leftmost member would split these into 2, 2, 3, 3.
        #expect(self.indents(offsetsInCharacters: [1.9, 2.0, 2.6, 2.7]) == [2, 2, 2, 2])
    }

    @Test("Offsets a full character apart stay distinct levels")
    func doesNotOverGroup() {
        #expect(self.indents(offsetsInCharacters: [1, 2, 3]) == [1, 2, 3])
    }

    @Test("A steadily drifting run splits rather than chaining into one level")
    func drift() throws {
        let result = self.indents(offsetsInCharacters: (1..<12).map { Double($0) * 0.3 })
        #expect(result.first == 0)
        #expect(try #require(result.last) > 0, "a run spanning 3.3 characters must not collapse to one level")
        #expect(Set(result).count > 1)
    }

    @Test("A stray far-right fragment clamps instead of exploding the line")
    func clampsRunawayIndent() {
        #expect(self.indents(offsetsInCharacters: [400]) == [TextLayout.Layout.maximumIndent])
    }

    @Test("The leftmost line is flush even when the whole block sits far right")
    func leftmostIsFlush() {
        let lines = [line("a", x: 5000, y: 200), line("b", x: 5024, y: 170)]
        #expect(TextLayout.indents(for: lines, characterWidth: 12) == [0, 2])
    }
}

@Suite("Paragraph breaks")
struct ParagraphBreakTests {
    private func rendered(pitches: [Double]) -> String {
        var y = 1000.0
        var lines = [line("a", x: 100, y: y)]
        for (index, pitch) in pitches.enumerated() {
            y -= pitch
            lines.append(line("\(index + 1)", x: 100, y: y))
        }
        return TextLayout.render(lines)
    }

    @Test("An ordinary pitch inserts no blank line")
    func evenPitch() {
        #expect(self.rendered(pitches: [30, 30, 30]) == "a\n1\n2\n3")
    }

    @Test("A gap of three pitches inserts blank lines, capped at two")
    func paragraphGap() {
        #expect(self.rendered(pitches: [30, 90, 30]) == "a\n1\n\n\n2\n3")
    }

    @Test("A gap of many pitches stays capped")
    func capsBlankLines() {
        #expect(self.rendered(pitches: [30, 300, 30]) == "a\n1\n\n\n2\n3")
    }
}

@Suite("Degenerate input")
struct DegenerateInputTests {
    @Test("Empty input renders nothing")
    func empty() {
        #expect(TextLayout.render([]) == "")
    }

    @Test("Empty strings are dropped")
    func emptyStrings() {
        #expect(TextLayout.render([line("", x: 0, y: 0), line("", x: 0, y: 50)]) == "")
    }

    @Test("A single line renders flush with no blank lines")
    func singleLine() {
        #expect(TextLayout.render([line("only", x: 500, y: 100)]) == "only")
    }

    @Test("Zero-width boxes do not divide by zero")
    func zeroWidth() {
        let degenerate = RecognizedLine(text: "x", rect: CGRect(x: 0, y: 0, width: 0, height: 0))
        #expect(TextLayout.render([degenerate]) == "x")
    }
}

@Suite("Worked example from the spec")
struct WorkedExampleTests {
    @Test("A deploy checklist screenshot reconstructs its layout")
    func deployChecklist() {
        let fragments = [
            RecognizedLine(text: "• Tag the release", rect: CGRect(x: 120, y: 300, width: 204, height: 20)),
            RecognizedLine(text: "Deploy checklist", rect: CGRect(x: 100, y: 420, width: 192, height: 22)),
            RecognizedLine(text: "- use vMAJOR.MINOR", rect: CGRect(x: 160, y: 270, width: 216, height: 18)),
            RecognizedLine(text: "• Run the test", rect: CGRect(x: 120, y: 330, width: 168, height: 20)),
            RecognizedLine(text: "suite", rect: CGRect(x: 315, y: 330, width: 60, height: 20)),
        ]
        let expected = """
        Deploy checklist


          • Run the test suite
          • Tag the release
             - use vMAJOR.MINOR
        """
        #expect(TextLayout.render(fragments) == expected)
    }
}

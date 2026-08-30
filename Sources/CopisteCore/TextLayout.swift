import CoreGraphics

/// Rebuilds reading order, indentation, and paragraph breaks from recognized geometry.
///
/// Text recognition returns the characters of each fragment and where it sits, but discards
/// every bit of whitespace: no indentation, no blank lines, and no guarantee that the
/// fragments arrive in reading order. Joining them with newlines flattens a screenshot of
/// indented code into a left-flush wall of text. Everything below reconstructs that
/// whitespace from the rectangles alone.
public enum TextLayout {
    public enum Layout {
        /// Fallback character width as a fraction of line height, when no line can be measured.
        public static let characterWidthRatio = 0.5
        /// Offsets within this many characters of a level's centre share that level.
        public static let indentClusterTolerance = 0.75
        /// Ignore runaway indents from stray glyphs far from the text block.
        public static let maximumIndent = 16
        /// A vertical gap this many times the usual line pitch starts a new paragraph.
        public static let paragraphGapRatio = 1.5
        /// Upper bound on blank lines inserted for a single gap.
        public static let maximumBlankLines = 2
    }

    /// Renders fragments into text, restoring reading order, indentation, and blank lines.
    public static func render(_ fragments: [RecognizedLine]) -> String {
        let lines = self.visualLines(from: fragments)
        guard !lines.isEmpty else { return "" }

        let characterWidth = self.characterWidth(of: lines)
        let indents = self.indents(for: lines, characterWidth: characterWidth)
        let blankLines = self.blankLines(before: lines)

        var output: [String] = []
        for (index, line) in lines.enumerated() {
            output.append(contentsOf: Array(repeating: "", count: blankLines[index]))
            output.append(String(repeating: " ", count: indents[index]) + line.text)
        }
        return output.joined(separator: "\n")
    }

    /// Orders fragments top to bottom and merges the ones sharing a visual line.
    ///
    /// A fragment whose vertical centre falls inside the previous line's box belongs to that
    /// line — a second column, a trailing badge, a split code line — and is merged in reading
    /// order rather than stacked below it.
    static func visualLines(from fragments: [RecognizedLine]) -> [RecognizedLine] {
        let sorted = fragments
            .filter { !$0.text.isEmpty }
            .sorted { $0.rect.midY > $1.rect.midY }

        var lines: [RecognizedLine] = []
        for fragment in sorted {
            guard var current = lines.last,
                  fragment.rect.midY >= current.rect.minY,
                  fragment.rect.midY <= current.rect.maxY
            else {
                lines.append(fragment)
                continue
            }
            if fragment.rect.minX < current.rect.minX {
                current.text = "\(fragment.text) \(current.text)"
            } else {
                current.text = "\(current.text) \(fragment.text)"
            }
            current.rect = current.rect.union(fragment.rect)
            lines[lines.count - 1] = current
        }
        return lines
    }

    /// Measures one character from the recognized lines themselves, so indentation holds at
    /// any font size or screen resolution.
    static func characterWidth(of lines: [RecognizedLine]) -> Double {
        let widths = lines
            .filter { !$0.text.isEmpty }
            .map { $0.rect.width / Double($0.text.count) }
            .sorted()
        guard !widths.isEmpty else {
            let heights = lines.map(\.rect.height).sorted()
            guard !heights.isEmpty else { return 0 }
            return heights[heights.count / 2] * Layout.characterWidthRatio
        }
        return widths[widths.count / 2]
    }

    /// Leading spaces per line.
    ///
    /// Rounding each offset on its own staggers visually aligned lines whenever measurement
    /// wobble straddles a `.5` boundary, so offsets are grouped into shared indent levels
    /// first. Each level tracks the running mean of the offsets absorbed into it: anchoring
    /// on the group's leftmost offset instead would push the far side of a wide group out
    /// into a second level, and the snapping below would then stagger the very lines the
    /// grouping exists to align.
    static func indents(for lines: [RecognizedLine], characterWidth: Double) -> [Int] {
        guard characterWidth > 0 else { return Array(repeating: 0, count: lines.count) }
        let baseX = lines.map(\.rect.minX).min() ?? 0
        let offsets = lines.map { ($0.rect.minX - baseX) / characterWidth }

        var levels: [Double] = []
        var counts: [Int] = []
        for offset in offsets.sorted() {
            guard let level = levels.last, offset - level <= Layout.indentClusterTolerance else {
                levels.append(offset)
                counts.append(1)
                continue
            }
            let count = counts[counts.endIndex - 1]
            levels[levels.endIndex - 1] = (level * Double(count) + offset) / Double(count + 1)
            counts[counts.endIndex - 1] = count + 1
        }

        return offsets.map { offset in
            let level = levels.min { abs($0 - offset) < abs($1 - offset) } ?? 0
            return min(max(Int(level.rounded()), 0), Layout.maximumIndent)
        }
    }

    /// Blank lines to emit before each line, from vertical gaps wider than the usual line pitch.
    static func blankLines(before lines: [RecognizedLine]) -> [Int] {
        guard lines.count > 1 else { return Array(repeating: 0, count: lines.count) }
        let pitches = zip(lines, lines.dropFirst()).map { $0.rect.midY - $1.rect.midY }
        let median = pitches.sorted()[pitches.count / 2]
        guard median > 0 else { return Array(repeating: 0, count: lines.count) }

        var counts = [0]
        for pitch in pitches {
            guard pitch >= median * Layout.paragraphGapRatio else {
                counts.append(0)
                continue
            }
            let blanks = Int((pitch / median).rounded()) - 1
            counts.append(min(max(blanks, 0), Layout.maximumBlankLines))
        }
        return counts
    }
}

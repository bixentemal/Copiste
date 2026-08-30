import CopisteCore
import Foundation
import ImageIO
import Vision

/// Runs Vision text recognition and hands the geometry to `CopisteCore` for layout.
enum TextRecognizer {
    static func recognize(_ imageData: Data) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let observations = try await request.perform(on: imageData)

        guard let pixelSize = self.pixelSize(of: imageData) else {
            // Without image dimensions there is no layout to reconstruct; keep the plain lines.
            return observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let fragments = observations.compactMap { observation -> RecognizedLine? in
            guard let text = observation.topCandidates(1).first?.string, !text.isEmpty else { return nil }
            let box = observation.boundingBox.cgRect
            return RecognizedLine(
                text: text,
                rect: CGRect(
                    x: box.minX * pixelSize.width,
                    y: box.minY * pixelSize.height,
                    width: box.width * pixelSize.width,
                    height: box.height * pixelSize.height))
        }
        return TextLayout.render(fragments).trimmingCharacters(in: .newlines)
    }

    /// True pixel dimensions, so recognized geometry can be denormalized into a space where
    /// distances are comparable across resolutions.
    private static func pixelSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double,
              width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }
}

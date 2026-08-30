import CoreGraphics

/// One recognized text fragment and where it sits in the image.
///
/// Coordinates are in pixels with y growing upward, matching Vision's convention after
/// denormalization. Nothing here knows about Vision, AppKit, or pasteboards, so the layout
/// reconstruction can be exercised with hand-built geometry.
public struct RecognizedLine: Equatable, Sendable {
    public var text: String
    public var rect: CGRect

    public init(text: String, rect: CGRect) {
        self.text = text
        self.rect = rect
    }
}

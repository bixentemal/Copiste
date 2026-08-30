import AppKit
import UniformTypeIdentifiers

/// Reads an image from the pasteboard, either as image data or as a file copied in Finder.
enum ClipboardImageSource {
    /// Image types we read directly off the pasteboard, in order of preference.
    static let pasteboardTypes: [NSPasteboard.PasteboardType] = [
        .png,
        .tiff,
        .init("public.jpeg"),
    ]

    /// Extensions accepted when the pasteboard holds a file reference instead of image data.
    static let fileExtensions: Set<String> = ["png", "jpg", "jpeg", "tiff", "tif", "heic", "gif", "bmp"]

    /// The image to recognize, plus what to put back on the pasteboard afterwards.
    ///
    /// Restoring the *original* representation matters: when the user copied a file in
    /// Finder, they should get their file reference back, not raw pixels.
    struct Image {
        let data: Data
        let restoreType: NSPasteboard.PasteboardType
        let restoreData: Data
    }

    enum Outcome {
        case image(Image)
        case none
        case unreadableFile
    }

    static func read(from pasteboard: NSPasteboard) -> Outcome {
        if let type = pasteboard.availableType(from: self.pasteboardTypes),
           let data = pasteboard.data(forType: type),
           !data.isEmpty
        {
            return .image(Image(data: data, restoreType: type, restoreData: data))
        }

        guard let urlData = pasteboard.data(forType: .fileURL),
              let url = self.imageFileURL(from: urlData) else { return .none }

        guard let contents = try? Data(contentsOf: url), !contents.isEmpty else {
            return .unreadableFile
        }
        return .image(Image(data: contents, restoreType: .fileURL, restoreData: urlData))
    }

    /// True when an action would have something to work on. Cheap enough for menu rendering:
    /// it inspects the available types and, for a file, only its extension.
    static func hasImage(on pasteboard: NSPasteboard) -> Bool {
        if pasteboard.availableType(from: self.pasteboardTypes) != nil {
            return true
        }
        guard let urlData = pasteboard.data(forType: .fileURL) else { return false }
        return self.imageFileURL(from: urlData) != nil
    }

    private static func imageFileURL(from data: Data) -> URL? {
        guard let text = String(data: data, encoding: .utf8),
              let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.isFileURL,
              self.fileExtensions.contains(url.pathExtension.lowercased()) else { return nil }
        return url
    }
}

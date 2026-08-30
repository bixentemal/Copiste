import AppKit

/// Loads the menu-bar glyphs.
///
/// `Bundle.module` traps when the SwiftPM resource bundle is not where it expects, which is
/// easy to hit in a hand-assembled `.app`. These lookups degrade to an SF Symbol instead.
enum MenuIcon {
    static let size = NSSize(width: 18, height: 18)

    static var normal: NSImage {
        self.image(named: "MenuIcon") ?? self.fallback("text.viewfinder")
    }

    static var failure: NSImage {
        self.image(named: "MenuIconOff") ?? self.fallback("text.viewfinder")
    }

    private static let bundle: Bundle = {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("Copiste_Copiste.bundle"),
            Bundle.main.bundleURL.appendingPathComponent("Copiste_Copiste.bundle"),
        ]
        for case let url? in candidates {
            if let bundle = Bundle(url: url) {
                return bundle
            }
        }
        return Bundle.main
    }()

    private static func image(named name: String) -> NSImage? {
        guard let url = self.bundle.url(forResource: name, withExtension: "png", subdirectory: "Resources")
            ?? self.bundle.url(forResource: name, withExtension: "png"),
            let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        image.size = self.size
        return image
    }

    private static func fallback(_ symbol: String) -> NSImage {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Copiste") ?? NSImage()
        image.isTemplate = true
        return image
    }
}

import AppKit

/// Shows the standard About panel, which reads the app's name, icon, version, build number,
/// and copyright straight from `Info.plist` — nothing to keep in sync by hand.
@MainActor
enum AboutPanel {
    static func show() {
        WindowRaiser.present {
            NSApp.orderFrontStandardAboutPanel(options: [.credits: self.credits])
        }
    }

    /// The panel's own copyright line stays blank, so the copyright is shown here instead —
    /// still read from `Info.plist`, so the year has one source and cannot go stale.
    private static var credits: NSAttributedString {
        let copyright = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
        let text = """
        Reads text from images on your clipboard, on device.

        \(copyright ?? "")
        github.com/bixentemal/Copiste
        """
        return NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: {
                    let style = NSMutableParagraphStyle()
                    style.alignment = .center
                    return style
                }(),
            ])
    }
}

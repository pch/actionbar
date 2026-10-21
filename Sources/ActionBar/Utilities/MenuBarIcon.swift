import AppKit

enum MenuBarIcon {
    static func image(statusDotColor: NSColor? = nil) -> NSImage {
        let size = NSSize(width: 18, height: 18)

        guard let symbol = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "ActionBar")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)) else {
            return NSImage(size: size)
        }

        guard let dotColor = statusDotColor else {
            // No dot — pure template image, macOS handles dark/light automatically
            symbol.isTemplate = true
            return symbol
        }

        // A colored dot can't be part of a template image, so tint the symbol for the
        // current menu bar appearance ourselves.
        let menuBarColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .white : .black
        }

        let image = NSImage(size: size, flipped: false) { rect in
            let symbolRect = NSRect(
                x: 0,
                y: (rect.height - symbol.size.height) / 2,
                width: symbol.size.width,
                height: symbol.size.height
            )
            symbol.draw(in: symbolRect)

            menuBarColor.setFill()
            symbolRect.fill(using: .sourceAtop)

            let dotSize: CGFloat = 6
            dotColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.width - dotSize, y: 0, width: dotSize, height: dotSize)).fill()

            return true
        }
        image.isTemplate = false
        return image
    }
}

extension RunStatus {
    var color: NSColor {
        switch self {
        case .success: return .systemGreen
        case .failure: return .systemRed
        case .running: return .systemOrange
        case .queued: return .systemYellow
        case .cancelled, .unknown: return .systemGray
        }
    }
}

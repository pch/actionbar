import AppKit

enum MenuBarIcon {
    static func makeMenuBarIcon(statusDotColor: NSColor? = nil) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let symbolName = "checkmark.circle"

        guard let baseSymbol = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "ActionBar"
        ) else {
            return NSImage(size: size)
        }

        let sizeConfig = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)

        guard let dotColor = statusDotColor else {
            // No dot — pure template image, macOS handles dark/light automatically
            guard let image = baseSymbol.withSymbolConfiguration(sizeConfig) else {
                return NSImage(size: size)
            }
            image.isTemplate = true
            return image
        }

        // With dot — draw SF Symbol with appearance-adaptive color
        let menuBarColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? .white : .black
        }

        guard let sizedSymbol = baseSymbol.withSymbolConfiguration(sizeConfig) else {
            return NSImage(size: size)
        }

        let image = NSImage(size: size, flipped: false) { rect in
            // Draw the SF Symbol as template, then tint it
            let symbolSize = sizedSymbol.size
            let symbolRect = NSRect(
                x: 0,
                y: (rect.height - symbolSize.height) / 2,
                width: symbolSize.width,
                height: symbolSize.height
            )
            sizedSymbol.draw(in: symbolRect)

            // Tint the drawn pixels with menuBarColor
            menuBarColor.setFill()
            symbolRect.fill(using: .sourceAtop)

            // Draw the status dot
            let dotSize: CGFloat = 6
            let dotRect = NSRect(
                x: rect.width - dotSize,
                y: 0,
                width: dotSize,
                height: dotSize
            )
            dotColor.setFill()
            NSBezierPath(ovalIn: dotRect).fill()

            return true
        }
        image.isTemplate = false
        return image
    }

    static func statusColor(for status: RunStatus) -> NSColor {
        switch status {
        case .success: return .systemGreen
        case .failure: return .systemRed
        case .running: return .systemOrange
        case .queued: return .systemYellow
        case .cancelled: return .systemGray
        case .unknown: return .systemGray
        }
    }
}

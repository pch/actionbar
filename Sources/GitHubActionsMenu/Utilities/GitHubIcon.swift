import AppKit
import SwiftUI

enum GitHubIcon {
    // MARK: - SVG Path Parser

    /// Minimal SVG path parser supporting M, C, c, S, s, A, a, Z commands.
    /// Parses the GitHub Octocat SVG path data into an NSBezierPath.
    static func parseSVGPath(_ d: String, in rect: NSRect) -> NSBezierPath {
        let path = NSBezierPath()
        var tokens: [String] = []

        // Tokenize: split on command letters and whitespace/commas, keeping command letters
        var current = ""
        for ch in d {
            if "MmCcSsAaZzLlHhVvQqTt".contains(ch) {
                if !current.trimmingCharacters(in: .whitespaces).isEmpty {
                    tokens.append(contentsOf: splitNumbers(current))
                }
                tokens.append(String(ch))
                current = ""
            } else {
                current.append(ch)
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            tokens.append(contentsOf: splitNumbers(current))
        }

        var i = 0
        var cx: CGFloat = 0, cy: CGFloat = 0 // current point
        var lastControl: NSPoint? = nil
        var lastCommand: Character = "M"

        func num() -> CGFloat {
            guard i < tokens.count else { return 0 }
            let val = CGFloat(Double(tokens[i]) ?? 0)
            i += 1
            return val
        }

        func hasMoreNumbers() -> Bool {
            guard i < tokens.count else { return false }
            return Double(tokens[i]) != nil
        }

        // The GitHub logo is defined in a 98x96 viewBox. Scale to fit rect.
        let viewBoxW: CGFloat = 98
        let viewBoxH: CGFloat = 96
        let scaleX = rect.width / viewBoxW
        let scaleY = rect.height / viewBoxH

        func tx(_ x: CGFloat) -> CGFloat { rect.origin.x + x * scaleX }
        func ty(_ y: CGFloat) -> CGFloat { rect.origin.y + rect.height - y * scaleY } // flip Y

        while i < tokens.count {
            let token = tokens[i]
            guard let cmd = token.first, token.count == 1, "MmCcSsAaZzLlHhVv".contains(cmd) else {
                i += 1
                continue
            }
            i += 1
            lastCommand = cmd

            switch cmd {
            case "M":
                repeat {
                    cx = num(); cy = num()
                    path.move(to: NSPoint(x: tx(cx), y: ty(cy)))
                } while hasMoreNumbers()

            case "m":
                repeat {
                    cx += num(); cy += num()
                    path.move(to: NSPoint(x: tx(cx), y: ty(cy)))
                } while hasMoreNumbers()

            case "C":
                repeat {
                    let x1 = num(), y1 = num()
                    let x2 = num(), y2 = num()
                    cx = num(); cy = num()
                    path.curve(to: NSPoint(x: tx(cx), y: ty(cy)),
                               controlPoint1: NSPoint(x: tx(x1), y: ty(y1)),
                               controlPoint2: NSPoint(x: tx(x2), y: ty(y2)))
                    lastControl = NSPoint(x: x2, y: y2)
                } while hasMoreNumbers()

            case "c":
                repeat {
                    let dx1 = num(), dy1 = num()
                    let dx2 = num(), dy2 = num()
                    let dx = num(), dy = num()
                    let x1 = cx + dx1, y1 = cy + dy1
                    let x2 = cx + dx2, y2 = cy + dy2
                    cx += dx; cy += dy
                    path.curve(to: NSPoint(x: tx(cx), y: ty(cy)),
                               controlPoint1: NSPoint(x: tx(x1), y: ty(y1)),
                               controlPoint2: NSPoint(x: tx(x2), y: ty(y2)))
                    lastControl = NSPoint(x: x2, y: y2)
                } while hasMoreNumbers()

            case "S":
                repeat {
                    let reflected = reflectControl(current: NSPoint(x: cx, y: cy), last: lastControl)
                    let x2 = num(), y2 = num()
                    cx = num(); cy = num()
                    path.curve(to: NSPoint(x: tx(cx), y: ty(cy)),
                               controlPoint1: NSPoint(x: tx(reflected.x), y: ty(reflected.y)),
                               controlPoint2: NSPoint(x: tx(x2), y: ty(y2)))
                    lastControl = NSPoint(x: x2, y: y2)
                } while hasMoreNumbers()

            case "s":
                repeat {
                    let reflected = reflectControl(current: NSPoint(x: cx, y: cy), last: lastControl)
                    let dx2 = num(), dy2 = num()
                    let dx = num(), dy = num()
                    let x2 = cx + dx2, y2 = cy + dy2
                    cx += dx; cy += dy
                    path.curve(to: NSPoint(x: tx(cx), y: ty(cy)),
                               controlPoint1: NSPoint(x: tx(reflected.x), y: ty(reflected.y)),
                               controlPoint2: NSPoint(x: tx(x2), y: ty(y2)))
                    lastControl = NSPoint(x: x2, y: y2)
                } while hasMoreNumbers()

            case "A", "a":
                // Simplified arc handling: for the GitHub logo we approximate arcs with line segments
                repeat {
                    let _ = num() // rx
                    let _ = num() // ry
                    let _ = num() // rotation
                    let _ = num() // large-arc
                    let _ = num() // sweep
                    if cmd == "A" {
                        cx = num(); cy = num()
                    } else {
                        cx += num(); cy += num()
                    }
                    path.line(to: NSPoint(x: tx(cx), y: ty(cy)))
                    lastControl = nil
                } while hasMoreNumbers()

            case "L":
                repeat {
                    cx = num(); cy = num()
                    path.line(to: NSPoint(x: tx(cx), y: ty(cy)))
                    lastControl = nil
                } while hasMoreNumbers()

            case "l":
                repeat {
                    cx += num(); cy += num()
                    path.line(to: NSPoint(x: tx(cx), y: ty(cy)))
                    lastControl = nil
                } while hasMoreNumbers()

            case "H":
                repeat {
                    cx = num()
                    path.line(to: NSPoint(x: tx(cx), y: ty(cy)))
                    lastControl = nil
                } while hasMoreNumbers()

            case "h":
                repeat {
                    cx += num()
                    path.line(to: NSPoint(x: tx(cx), y: ty(cy)))
                    lastControl = nil
                } while hasMoreNumbers()

            case "V":
                repeat {
                    cy = num()
                    path.line(to: NSPoint(x: tx(cx), y: ty(cy)))
                    lastControl = nil
                } while hasMoreNumbers()

            case "v":
                repeat {
                    cy += num()
                    path.line(to: NSPoint(x: tx(cx), y: ty(cy)))
                    lastControl = nil
                } while hasMoreNumbers()

            case "Z", "z":
                path.close()
                lastControl = nil

            default:
                break
            }

            if !"CcSs".contains(lastCommand) {
                lastControl = nil
            }
        }

        return path
    }

    private static func splitNumbers(_ s: String) -> [String] {
        var results: [String] = []
        var current = ""
        var hasDecimal = false
        var lastWasE = false

        for ch in s {
            if ch == "," || ch == " " || ch == "\t" || ch == "\n" || ch == "\r" {
                if !current.isEmpty {
                    results.append(current)
                    current = ""
                }
                hasDecimal = false
                lastWasE = false
            } else if ch == "-" && !current.isEmpty && !lastWasE {
                results.append(current)
                current = String(ch)
                hasDecimal = false
                lastWasE = false
            } else if ch == "." && hasDecimal {
                // Second decimal point starts a new number
                results.append(current)
                current = String(ch)
                hasDecimal = true
                lastWasE = false
            } else {
                if ch == "." { hasDecimal = true }
                current.append(ch)
                lastWasE = (ch == "e" || ch == "E")
            }
        }
        if !current.isEmpty {
            results.append(current)
        }
        return results
    }

    private static func reflectControl(current: NSPoint, last: NSPoint?) -> NSPoint {
        guard let last = last else { return current }
        return NSPoint(x: 2 * current.x - last.x, y: 2 * current.y - last.y)
    }

    // MARK: - GitHub Octocat SVG Path

    /// GitHub's Octocat mark SVG path (viewBox 98 96)
    private static let octocatPath = "M48.854 0C21.839 0 0 22 0 49.217c0 21.756 13.993 40.172 33.405 46.69 2.427.49 3.316-1.059 3.316-2.362 0-1.141-.08-5.052-.08-9.127-13.59 2.934-16.42-5.867-16.42-5.867-2.184-5.704-5.42-7.17-5.42-7.17-4.448-3.015.324-3.015.324-3.015 4.934.326 7.523 5.052 7.523 5.052 4.367 7.496 11.404 5.378 14.235 4.074.404-3.178 1.699-5.378 3.074-6.6-10.839-1.141-22.243-5.378-22.243-24.283 0-5.378 1.94-9.778 5.014-13.2-.485-1.222-2.184-6.275.486-13.038 0 0 4.125-1.304 13.426 5.052a46.97 46.97 0 0 1 12.214-1.63c4.125 0 8.33.571 12.213 1.63 9.302-6.356 13.427-5.052 13.427-5.052 2.67 6.763.97 11.816.485 13.038 3.155 3.422 5.015 7.822 5.015 13.2 0 18.905-11.404 23.06-22.324 24.283 1.78 1.548 3.316 4.481 3.316 9.126 0 6.6-.08 11.897-.08 13.526 0 1.304.89 2.853 3.316 2.364 19.412-6.52 33.405-24.935 33.405-46.691C97.707 22 75.788 0 48.854 0z"

    // MARK: - Image Generation

    private static let iconRect = NSRect(x: 1, y: 1.5, width: 16, height: 15.5)

    static func makeMenuBarIcon(statusDotColor: NSColor? = nil) -> NSImage {
        let size = NSSize(width: 18, height: 18)

        guard let dotColor = statusDotColor else {
            // No dot — pure template image, macOS handles dark/light automatically
            let image = NSImage(size: size, flipped: false) { _ in
                let path = parseSVGPath(octocatPath, in: iconRect)
                NSColor.black.setFill()
                path.fill()
                return true
            }
            image.isTemplate = true
            return image
        }

        // With dot — draw octocat using an appearance-adaptive color
        let menuBarColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? .white : .black
        }

        let image = NSImage(size: size, flipped: false) { rect in
            let path = parseSVGPath(octocatPath, in: iconRect)
            menuBarColor.setFill()
            path.fill()

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

    /// Renders the octocat on a white rounded-rect background for use as the app icon
    /// (shown in notifications, Dock, etc.).
    static func makeAppIcon() -> NSImage {
        let w = 256
        let size = NSSize(width: w, height: w)

        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: w,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return NSImage(size: size)
        }

        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx

        let rect = NSRect(origin: .zero, size: size)

        // White rounded-rect background (macOS icon style)
        NSColor.white.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 48, yRadius: 48).fill()

        // Draw octocat centered with padding
        let padding: CGFloat = 36
        let iconRect = NSRect(
            x: padding,
            y: padding,
            width: rect.width - padding * 2,
            height: rect.height - padding * 2
        )
        NSColor(red: 0.13, green: 0.13, blue: 0.13, alpha: 1.0).setFill()
        parseSVGPath(octocatPath, in: iconRect).fill()

        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = ctx.makeImage() else {
            return NSImage(size: size)
        }
        return NSImage(cgImage: cgImage, size: size)
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

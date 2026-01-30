#!/usr/bin/env swift
// Generates AppIcon.icns from the GitHub octocat SVG path data.
// Usage: swift Scripts/generate-icon.swift

import AppKit

// MARK: - SVG Path Parser (copied from GitHubIcon.swift)

let octocatPath = "M48.854 0C21.839 0 0 22 0 49.217c0 21.756 13.993 40.172 33.405 46.69 2.427.49 3.316-1.059 3.316-2.362 0-1.141-.08-5.052-.08-9.127-13.59 2.934-16.42-5.867-16.42-5.867-2.184-5.704-5.42-7.17-5.42-7.17-4.448-3.015.324-3.015.324-3.015 4.934.326 7.523 5.052 7.523 5.052 4.367 7.496 11.404 5.378 14.235 4.074.404-3.178 1.699-5.378 3.074-6.6-10.839-1.141-22.243-5.378-22.243-24.283 0-5.378 1.94-9.778 5.014-13.2-.485-1.222-2.184-6.275.486-13.038 0 0 4.125-1.304 13.426 5.052a46.97 46.97 0 0 1 12.214-1.63c4.125 0 8.33.571 12.213 1.63 9.302-6.356 13.427-5.052 13.427-5.052 2.67 6.763.97 11.816.485 13.038 3.155 3.422 5.015 7.822 5.015 13.2 0 18.905-11.404 23.06-22.324 24.283 1.78 1.548 3.316 4.481 3.316 9.126 0 6.6-.08 11.897-.08 13.526 0 1.304.89 2.853 3.316 2.364 19.412-6.52 33.405-24.935 33.405-46.691C97.707 22 75.788 0 48.854 0z"

func splitNumbers(_ s: String) -> [String] {
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

func reflectControl(current: NSPoint, last: NSPoint?) -> NSPoint {
    guard let last = last else { return current }
    return NSPoint(x: 2 * current.x - last.x, y: 2 * current.y - last.y)
}

func parseSVGPath(_ d: String, in rect: NSRect) -> NSBezierPath {
    let path = NSBezierPath()
    var tokens: [String] = []

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
    var cx: CGFloat = 0, cy: CGFloat = 0
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

    let viewBoxW: CGFloat = 98
    let viewBoxH: CGFloat = 96
    let scaleX = rect.width / viewBoxW
    let scaleY = rect.height / viewBoxH

    func tx(_ x: CGFloat) -> CGFloat { rect.origin.x + x * scaleX }
    func ty(_ y: CGFloat) -> CGFloat { rect.origin.y + rect.height - y * scaleY }

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
            repeat { cx = num(); cy = num(); path.move(to: NSPoint(x: tx(cx), y: ty(cy))) } while hasMoreNumbers()
        case "m":
            repeat { cx += num(); cy += num(); path.move(to: NSPoint(x: tx(cx), y: ty(cy))) } while hasMoreNumbers()
        case "C":
            repeat {
                let x1 = num(), y1 = num(), x2 = num(), y2 = num()
                cx = num(); cy = num()
                path.curve(to: NSPoint(x: tx(cx), y: ty(cy)),
                           controlPoint1: NSPoint(x: tx(x1), y: ty(y1)),
                           controlPoint2: NSPoint(x: tx(x2), y: ty(y2)))
                lastControl = NSPoint(x: x2, y: y2)
            } while hasMoreNumbers()
        case "c":
            repeat {
                let dx1 = num(), dy1 = num(), dx2 = num(), dy2 = num()
                let dx = num(), dy = num()
                let x1 = cx + dx1, y1 = cy + dy1, x2 = cx + dx2, y2 = cy + dy2
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
                let dx2 = num(), dy2 = num(), dx = num(), dy = num()
                let x2 = cx + dx2, y2 = cy + dy2
                cx += dx; cy += dy
                path.curve(to: NSPoint(x: tx(cx), y: ty(cy)),
                           controlPoint1: NSPoint(x: tx(reflected.x), y: ty(reflected.y)),
                           controlPoint2: NSPoint(x: tx(x2), y: ty(y2)))
                lastControl = NSPoint(x: x2, y: y2)
            } while hasMoreNumbers()
        case "A", "a":
            repeat {
                _ = num(); _ = num(); _ = num(); _ = num(); _ = num()
                if cmd == "A" { cx = num(); cy = num() } else { cx += num(); cy += num() }
                path.line(to: NSPoint(x: tx(cx), y: ty(cy)))
                lastControl = nil
            } while hasMoreNumbers()
        case "L":
            repeat { cx = num(); cy = num(); path.line(to: NSPoint(x: tx(cx), y: ty(cy))); lastControl = nil } while hasMoreNumbers()
        case "l":
            repeat { cx += num(); cy += num(); path.line(to: NSPoint(x: tx(cx), y: ty(cy))); lastControl = nil } while hasMoreNumbers()
        case "H":
            repeat { cx = num(); path.line(to: NSPoint(x: tx(cx), y: ty(cy))); lastControl = nil } while hasMoreNumbers()
        case "h":
            repeat { cx += num(); path.line(to: NSPoint(x: tx(cx), y: ty(cy))); lastControl = nil } while hasMoreNumbers()
        case "V":
            repeat { cy = num(); path.line(to: NSPoint(x: tx(cx), y: ty(cy))); lastControl = nil } while hasMoreNumbers()
        case "v":
            repeat { cy += num(); path.line(to: NSPoint(x: tx(cx), y: ty(cy))); lastControl = nil } while hasMoreNumbers()
        case "Z", "z":
            path.close(); lastControl = nil
        default:
            break
        }
        if !"CcSs".contains(lastCommand) { lastControl = nil }
    }
    return path
}

// MARK: - Icon Generation

func renderIcon(size: Int) -> Data {
    guard let ctx = CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("Failed to create CGContext for size \(size)") }

    let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx

    let s = CGFloat(size)
    let rect = NSRect(x: 0, y: 0, width: s, height: s)

    // White rounded-rect background
    let cornerRadius = s * (48.0 / 256.0)
    NSColor.white.setFill()
    NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()

    // Octocat
    let padding = s * (36.0 / 256.0)
    let iconRect = NSRect(x: padding, y: padding, width: s - padding * 2, height: s - padding * 2)
    NSColor(red: 0.13, green: 0.13, blue: 0.13, alpha: 1.0).setFill()
    parseSVGPath(octocatPath, in: iconRect).fill()

    NSGraphicsContext.restoreGraphicsState()

    guard let cgImage = ctx.makeImage() else { fatalError("Failed to create CGImage") }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("Failed to create PNG") }
    return png
}

// MARK: - iconutil-based .icns generation

let iconsetDir = "/tmp/AppIcon.iconset"
let icnsPath = "Resources/AppIcon.icns"

// Clean up
try? FileManager.default.removeItem(atPath: iconsetDir)
try FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

// Required sizes for macOS .icns
let sizes: [(name: String, px: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

for entry in sizes {
    let data = renderIcon(size: entry.px)
    let path = "\(iconsetDir)/\(entry.name).png"
    try data.write(to: URL(fileURLWithPath: path))
    print("  \(entry.name).png (\(entry.px)x\(entry.px))")
}

// Run iconutil to create .icns
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetDir, "-o", icnsPath]
try process.run()
process.waitUntilExit()

if process.terminationStatus == 0 {
    print("Created \(icnsPath)")
} else {
    print("iconutil failed with status \(process.terminationStatus)")
    exit(1)
}

// Clean up
try? FileManager.default.removeItem(atPath: iconsetDir)

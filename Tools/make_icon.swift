// Renders AppIcon.iconset from code so the repository carries no binary blobs.
// Usage: swift Tools/make_icon.swift <output.iconset>

import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make_icon.swift <output.iconset>\n".utf8))
    exit(2)
}
let outputDirectory = URL(fileURLWithPath: arguments[1])
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

/// macOS icons are drawn inside a rounded square with this corner ratio.
let cornerRatio: CGFloat = 0.2237

func drawIcon(size: Int) -> Data? {
    let side = CGFloat(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    // Leave the standard margin macOS expects around an app icon's artwork.
    let inset = side * 0.06
    let plate = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let shape = NSBezierPath(roundedRect: plate, xRadius: plate.width * cornerRatio, yRadius: plate.width * cornerRatio)

    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 0.36, green: 0.44, blue: 0.95, alpha: 1),
        ending: NSColor(calibratedRed: 0.22, green: 0.24, blue: 0.62, alpha: 1)
    )
    gradient?.draw(in: shape, angle: -90)

    // Clipboard body.
    let bodyWidth = plate.width * 0.50
    let bodyHeight = plate.height * 0.60
    let body = NSRect(
        x: plate.midX - bodyWidth / 2,
        y: plate.midY - bodyHeight / 2 - plate.height * 0.03,
        width: bodyWidth,
        height: bodyHeight
    )
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: bodyWidth * 0.13, yRadius: bodyWidth * 0.13)
    NSColor.white.setFill()
    bodyPath.fill()

    // Clip at the top.
    let clipWidth = bodyWidth * 0.46
    let clipHeight = plate.height * 0.11
    let clip = NSRect(
        x: plate.midX - clipWidth / 2,
        y: body.maxY - clipHeight * 0.45,
        width: clipWidth,
        height: clipHeight
    )
    let clipPath = NSBezierPath(roundedRect: clip, xRadius: clipHeight * 0.35, yRadius: clipHeight * 0.35)
    NSColor(calibratedWhite: 0.88, alpha: 1).setFill()
    clipPath.fill()

    // Three lines of "content", shortest last, to read as a stack of snippets.
    let lineColor = NSColor(calibratedRed: 0.36, green: 0.44, blue: 0.95, alpha: 1)
    lineColor.setFill()
    let lineHeight = body.height * 0.075
    let lineInset = body.width * 0.16
    let widths: [CGFloat] = [1.0, 0.82, 0.55]
    for (index, factor) in widths.enumerated() {
        let y = body.maxY - body.height * (0.34 + 0.18 * CGFloat(index))
        let rect = NSRect(
            x: body.minX + lineInset,
            y: y,
            width: (body.width - lineInset * 2) * factor,
            height: lineHeight
        )
        NSBezierPath(roundedRect: rect, xRadius: lineHeight / 2, yRadius: lineHeight / 2).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

// The set of sizes `iconutil` expects in an .iconset directory.
let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for variant in variants {
    guard let data = drawIcon(size: variant.pixels) else {
        FileHandle.standardError.write(Data("failed to render \(variant.name)\n".utf8))
        exit(1)
    }
    try data.write(to: outputDirectory.appendingPathComponent("\(variant.name).png"))
}

print("wrote \(variants.count) icon variants to \(outputDirectory.path)")

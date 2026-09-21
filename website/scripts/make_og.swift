// Renders website/assets/og-image.png (1200x630) from code.
// Usage: swift website/scripts/make_og.swift <icon.png> <output.png>
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let icon = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write(Data("usage: make_og.swift <icon.png> <output.png>\n".utf8)); exit(2)
}
let W = 1200, H = 630
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
    let ctx = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
ctx.imageInterpolation = .high

let bounds = NSRect(x: 0, y: 0, width: W, height: H)
NSGradient(colors: [NSColor(calibratedRed: 0.10, green: 0.09, blue: 0.20, alpha: 1),
                    NSColor(calibratedRed: 0.22, green: 0.24, blue: 0.62, alpha: 1)])?.draw(in: bounds, angle: -35)

// A soft stack of "clips" behind the copy, echoing the popup's rows.
for (i, alpha) in [0.05, 0.08, 0.12].enumerated() {
    let card = NSRect(x: 690 + CGFloat(i) * 26, y: 110 + CGFloat(i) * 34, width: 420, height: 92)
    NSColor(white: 1, alpha: alpha).setFill()
    NSBezierPath(roundedRect: card, xRadius: 16, yRadius: 16).fill()
}
let selected = NSRect(x: 742, y: 178, width: 420, height: 92)
NSColor(calibratedRed: 0.36, green: 0.44, blue: 0.95, alpha: 1).setFill()
NSBezierPath(roundedRect: selected, xRadius: 16, yRadius: 16).fill()
NSColor.white.setFill()
for (j, w) in [300.0, 220.0].enumerated() {
    NSBezierPath(roundedRect: NSRect(x: 772, y: 232 - CGFloat(j) * 26, width: w, height: 12), xRadius: 6, yRadius: 6).fill()
}

icon.draw(in: NSRect(x: 84, y: 388, width: 132, height: 132))

func serif(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    if let d = base.fontDescriptor.withDesign(.serif), let f = NSFont(descriptor: d, size: size) { return f }
    return base
}
func draw(_ text: String, at p: NSPoint, font: NSFont, color: NSColor) {
    (text as NSString).draw(at: p, withAttributes: [.font: font, .foregroundColor: color])
}
draw("Pastiche", at: NSPoint(x: 80, y: 250), font: serif(112, .bold), color: .white)
draw("Everything you've copied,", at: NSPoint(x: 84, y: 160), font: NSFont.systemFont(ofSize: 40, weight: .medium),
     color: NSColor(white: 1, alpha: 0.92))
draw("one shortcut away.", at: NSPoint(x: 84, y: 108), font: NSFont.systemFont(ofSize: 40, weight: .medium),
     color: NSColor(white: 1, alpha: 0.92))
draw("Open-source clipboard history for macOS", at: NSPoint(x: 84, y: 48),
     font: NSFont.systemFont(ofSize: 24, weight: .regular), color: NSColor(white: 1, alpha: 0.6))

NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: args[2]))
print("wrote \(args[2])")

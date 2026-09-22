// Places a window capture on a 2880x1800 canvas with a caption.
// Usage: swift compose.swift <window.png> "<headline>" <out.png>
// Draws off-screen only; it opens no windows.
import AppKit

let args = CommandLine.arguments
guard args.count == 4, let window = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write(Data("usage: compose.swift <window.png> \"<headline>\" <out.png>\n".utf8)); exit(2)
}
let W = 2880, H = 1800
// Draw on RGBA (AppKit cannot draw into 24-bit RGB), flatten at the end.
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
    let ctx = NSGraphicsContext(bitmapImageRep: rep) else { FileHandle.standardError.write(Data("no drawing context\n".utf8)); exit(1) }
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx; ctx.imageInterpolation = .high

let canvas = NSRect(x: 0, y: 0, width: W, height: H)
NSGradient(colors: [NSColor(calibratedRed: 0.10, green: 0.09, blue: 0.24, alpha: 1),
                    NSColor(calibratedRed: 0.24, green: 0.27, blue: 0.68, alpha: 1)])?.draw(in: canvas, angle: -35)

// Caption, left.
func serif(_ size: CGFloat) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: .bold)
    if let d = base.fontDescriptor.withDesign(.serif), let f = NSFont(descriptor: d, size: size) { return f }
    return base
}
let style = NSMutableParagraphStyle(); style.lineBreakMode = .byWordWrapping; style.lineSpacing = 6
(args[2] as NSString).draw(in: NSRect(x: 190, y: 620, width: 1180, height: 700),
    withAttributes: [.font: serif(150), .foregroundColor: NSColor.white, .paragraphStyle: style])
("Pastiche" as NSString).draw(at: NSPoint(x: 194, y: 200),
    withAttributes: [.font: NSFont.systemFont(ofSize: 56, weight: .semibold), .foregroundColor: NSColor(white: 1, alpha: 0.7)])

// Window, right: as large as fits a 1300 x 1440 box, keeping its aspect ratio.
let size = window.size
let scale = min(1300 / size.width, 1440 / size.height)
let target = NSSize(width: size.width * scale, height: size.height * scale)
let box = NSRect(x: 1500, y: 0, width: 1250, height: H)
let frame = NSRect(x: box.midX - target.width / 2, y: (CGFloat(H) - target.height) / 2, width: target.width, height: target.height)
let shadow = NSShadow(); shadow.shadowBlurRadius = 110; shadow.shadowOffset = NSSize(width: 0, height: -40)
shadow.shadowColor = NSColor(white: 0, alpha: 0.5)
NSGraphicsContext.saveGraphicsState(); shadow.set()
window.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.restoreGraphicsState()

// The App Store rejects screenshots with an alpha channel, even a fully opaque
// one, so write the image without it.
guard let source = rep.cgImage,
      let flat = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                           space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { exit(1) }
flat.draw(source, in: CGRect(x: 0, y: 0, width: W, height: H))
guard let image = flat.makeImage(),
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[3]) as CFURL, "public.png" as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { exit(1) }
print("wrote \(args[3])")

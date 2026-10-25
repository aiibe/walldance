import AppKit

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: swift scripts/InstallerBackground.swift OUTPUT.png")
}

let size = NSSize(width: 680, height: 400)
let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: 1360, pixelsHigh: 800,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
bitmap.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let context = NSGraphicsContext.current!.cgContext
context.translateBy(x: 0, y: size.height)
context.scaleBy(x: 1, y: -1)
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)

let bounds = NSRect(origin: .zero, size: size)
NSGradient(colors: [
    NSColor(srgbRed: 0.96, green: 0.98, blue: 1, alpha: 1),
    NSColor(srgbRed: 0.86, green: 0.92, blue: 1, alpha: 1)
])!.draw(in: bounds, angle: 0)

func text(_ value: String, y: CGFloat, font: NSFont, color: NSColor) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    (value as NSString).draw(
        in: NSRect(x: 40, y: y, width: 600, height: 48),
        withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
    )
}

let ink = NSColor(srgbRed: 0.08, green: 0.14, blue: 0.25, alpha: 1)
text("Walldance", y: 43, font: .systemFont(ofSize: 32, weight: .semibold), color: ink)
text("Drag Walldance to Applications", y: 89,
     font: .systemFont(ofSize: 15), color: ink.withAlphaComponent(0.65))

for x: CGFloat in [98, 446] {
    let card = NSBezierPath(roundedRect: NSRect(x: x, y: 144, width: 136, height: 160),
                            xRadius: 26, yRadius: 26)
    NSColor.white.withAlphaComponent(0.65).setFill()
    card.fill()
    NSColor.white.withAlphaComponent(0.95).setStroke()
    card.lineWidth = 1
    card.stroke()
}

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 307, y: 213))
arrow.line(to: NSPoint(x: 371, y: 213))
arrow.move(to: NSPoint(x: 358, y: 200))
arrow.line(to: NSPoint(x: 371, y: 213))
arrow.line(to: NSPoint(x: 358, y: 226))
arrow.lineWidth = 3
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
NSColor(srgbRed: 0.14, green: 0.43, blue: 0.90, alpha: 0.75).setStroke()
arrow.stroke()

text("Then open Walldance from Applications.", y: 339,
     font: .systemFont(ofSize: 12), color: ink.withAlphaComponent(0.5))
NSGraphicsContext.restoreGraphicsState()

try bitmap.representation(using: .png, properties: [:])!.write(
    to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic
)

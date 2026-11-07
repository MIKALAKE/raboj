// Renders Răboj's app icon (a tally stick: four notches crossed by a fifth) into an .iconset folder.
// Usage: swift scripts/make-icon.swift build/AppIcon.iconset && iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try? FileManager.default.removeItem(at: output)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 1024, height: 1024)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    // macOS icon grid: an 824 pt body centered in the 1024 pt canvas.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 24
    shadow.set()
    color(0x1B1D23).setFill()
    shape.fill()
    NSGraphicsContext.current?.restoreGraphicsState()
    NSGradient(starting: color(0x2B2E37), ending: color(0x15161B))!.draw(in: shape, angle: -90)

    let notches = NSBezierPath()
    notches.lineWidth = 58
    notches.lineCapStyle = .round
    for x in [322.0, 452.0, 582.0, 712.0] {
        notches.move(to: NSPoint(x: x, y: 290))
        notches.line(to: NSPoint(x: x, y: 734))
    }
    color(0xF4EEE3).setStroke()
    notches.stroke()

    let slash = NSBezierPath()
    slash.lineWidth = 58
    slash.lineCapStyle = .round
    slash.move(to: NSPoint(x: 248, y: 330))
    slash.line(to: NSPoint(x: 786, y: 694))
    color(0x60A5FA).setStroke()
    slash.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let sizes: [(String, Int)] = [
    ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
    ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
    ("512x512", 512), ("512x512@2x", 1024),
]
for (name, pixels) in sizes {
    try render(pixels: pixels).write(to: output.appendingPathComponent("icon_\(name).png"))
}
print("Wrote \(sizes.count) images to \(output.path)")

import AppKit

// Reproducible vector artwork; no downloaded or third-party image assets.
let output = CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.iconset"
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
func drawIcon(size: Int, name: String) throws {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Cannot create icon bitmap") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(size) / 1024)
    transform.concat()
    let tile = NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 205, yRadius: 205)
    NSGradient(starting: NSColor(calibratedRed: 0.16, green: 0.44, blue: 0.98, alpha: 1), ending: NSColor(calibratedRed: 0.16, green: 0.22, blue: 0.69, alpha: 1))!.draw(in: tile, angle: -70)
    NSColor.white.withAlphaComponent(0.20).setFill()
    NSBezierPath(roundedRect: NSRect(x: 160, y: 350, width: 430, height: 455), xRadius: 80, yRadius: 80).fill()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: NSRect(x: 420, y: 200, width: 430, height: 455), xRadius: 80, yRadius: 80).fill()
    ("文" as NSString).draw(at: NSPoint(x: 225, y: 445), withAttributes: [.font: NSFont.systemFont(ofSize: 280, weight: .medium), .foregroundColor: NSColor.white])
    ("A" as NSString).draw(at: NSPoint(x: 530, y: 285), withAttributes: [.font: NSFont.systemFont(ofSize: 280, weight: .semibold), .foregroundColor: NSColor(calibratedRed: 0.16, green: 0.34, blue: 0.82, alpha: 1)])
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode icon") }
    try png.write(to: URL(fileURLWithPath: output).appendingPathComponent(name))
}
for size in [16, 32, 128, 256, 512] {
    try drawIcon(size: size, name: "icon_\(size)x\(size).png")
    try drawIcon(size: size * 2, name: "icon_\(size)x\(size)@2x.png")
}

import AppKit

enum MenuBarIcon {
    static let pointSize = NSSize(width: 18, height: 18)

    static func image() -> NSImage {
        let image = NSImage(size: pointSize)
        for scale in [2, 3] {
            image.addRepresentation(makeRepresentation(scale: CGFloat(scale)))
        }
        image.isTemplate = true
        return image
    }

    private static func makeRepresentation(scale: CGFloat) -> NSBitmapImageRep {
        let pixels = Int((pointSize.width * scale).rounded())
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        rep.size = pointSize
        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return rep }
        context.shouldAntialias = true
        context.imageInterpolation = .high
        NSGraphicsContext.current = context
        draw(in: NSRect(origin: .zero, size: pointSize))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    // Template (black/clear) version of the app icon, sized so 文 and A stay readable at 18pt.
    static func draw(in rect: NSRect) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        cg.saveGState()
        let scale = rect.width / 18
        cg.scaleBy(x: scale, y: scale)
        cg.setShouldAntialias(true)

        let outer = CGPath(roundedRect: CGRect(x: 0.35, y: 0.35, width: 17.3, height: 17.3), cornerWidth: 3.9, cornerHeight: 3.9, transform: nil)
        cg.addPath(outer)
        cg.clip()
        cg.setFillColor(NSColor.black.cgColor)
        cg.addPath(outer)
        cg.fillPath()

        let backRect = CGRect(x: 1.45, y: 5.35, width: 8.55, height: 10.0)
        let frontRect = CGRect(x: 7.85, y: 2.15, width: 8.7, height: 10.15)
        let backCard = CGPath(roundedRect: backRect, cornerWidth: 1.85, cornerHeight: 1.85, transform: nil)
        let frontCard = CGPath(roundedRect: frontRect, cornerWidth: 1.85, cornerHeight: 1.85, transform: nil)
        let wen = centeredGlyph("文", font: NSFont.systemFont(ofSize: 6.6, weight: .medium), in: backRect.offsetBy(dx: -0.55, dy: 0.15))
        let letterA = centeredGlyph("A", font: NSFont.systemFont(ofSize: 7.4, weight: .semibold), in: frontRect.offsetBy(dx: 0, dy: -0.15))

        cg.setBlendMode(.destinationOut)
        cg.setFillColor(NSColor.black.withAlphaComponent(0.38).cgColor)
        cg.addPath(backCard)
        cg.fillPath()
        cg.setFillColor(NSColor.black.cgColor)
        cg.addPath(wen)
        cg.fillPath()
        cg.addPath(frontCard)
        cg.fillPath()

        cg.setBlendMode(.normal)
        cg.setFillColor(NSColor.black.cgColor)
        cg.addPath(letterA)
        cg.fillPath()
        cg.restoreGState()
    }

    private static func centeredGlyph(_ string: String, font: NSFont, in rect: CGRect) -> CGPath {
        let raw = glyphPath(string, font: font, at: .zero)
        let bounds = raw.boundingBoxOfPath
        guard !bounds.isNull, !bounds.isEmpty else { return raw }
        var translation = CGAffineTransform(
            translationX: rect.midX - bounds.midX,
            y: rect.midY - bounds.midY
        )
        return raw.copy(using: &translation) ?? raw
    }

    private static func glyphPath(_ string: String, font: NSFont, at origin: CGPoint) -> CGPath {
        let path = CGMutablePath()
        let characters = Array(string.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        CTFontGetGlyphsForCharacters(font, characters, &glyphs, characters.count)
        var x = origin.x
        var advances = [CGSize](repeating: .zero, count: glyphs.count)
        CTFontGetAdvancesForGlyphs(font, .default, glyphs, &advances, glyphs.count)
        for index in glyphs.indices {
            var translation = CGAffineTransform(translationX: x, y: origin.y)
            if let glyph = CTFontCreatePathForGlyph(font, glyphs[index], &translation) {
                path.addPath(glyph)
            }
            x += advances[index].width
        }
        return path
    }
}

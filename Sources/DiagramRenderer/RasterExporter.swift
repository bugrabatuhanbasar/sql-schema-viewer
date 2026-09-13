import Foundation
import SchemaModel

#if canImport(AppKit) && canImport(CoreGraphics)
import AppKit
import CoreGraphics
import CoreText

/// Renders a `DiagramScene` into raster (PNG) and vector (PDF) bytes via
/// Core Graphics. Both back-ends share the same drawing primitives so the
/// vector PDF and the pixel PNG stay visually identical.
public enum RasterExporter {
    /// Encoded PNG (2× logical scale for retina).
    public static func png(_ scene: DiagramScene, scale: CGFloat = 2.0) -> Data? {
        let size = contentSize(scene)
        let width = Int(size.width * scale)
        let height = Int(size.height * scale)
        guard width > 0, height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: 20, y: 20)
        drawScene(scene, in: ctx)
        guard let img = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: img)
        return rep.representation(using: .png, properties: [:])
    }

    /// Encoded PDF, single page sized to fit the scene.
    public static func pdf(_ scene: DiagramScene) -> Data? {
        let size = contentSize(scene)
        var mediaBox = CGRect(origin: .zero, size: size)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }
        ctx.beginPDFPage(nil)
        // Flip vertically so our top-left coordinate space matches PDF's.
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: 20, y: 20)
        drawScene(scene, in: ctx)
        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }

    // MARK: shared drawing

    private static func contentSize(_ scene: DiagramScene) -> CGSize {
        var maxX: Double = 0, maxY: Double = 0
        for n in scene.nodes {
            maxX = max(maxX, n.rect.x + n.rect.width)
            maxY = max(maxY, n.rect.y + n.rect.height)
        }
        return CGSize(width: maxX + 40, height: maxY + 40)
    }

    private static func drawScene(_ scene: DiagramScene, in ctx: CGContext) {
        // Background
        ctx.setFillColor(CGColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1))
        ctx.fill(CGRect(x: -20, y: -20, width: contentSize(scene).width, height: contentSize(scene).height))

        ctx.setLineWidth(1.2)
        ctx.setStrokeColor(CGColor(gray: 0.35, alpha: 0.7))
        for edge in scene.edges {
            let p1 = CGPoint(x: edge.from.x, y: edge.from.y)
            let p2 = CGPoint(x: edge.to.x, y: edge.to.y)
            let midX = (p1.x + p2.x) / 2
            ctx.beginPath()
            ctx.move(to: p1)
            ctx.addCurve(to: p2, control1: CGPoint(x: midX, y: p1.y), control2: CGPoint(x: midX, y: p2.y))
            ctx.strokePath()
        }

        for n in scene.nodes {
            let rect = CGRect(x: n.rect.x, y: n.rect.y, width: n.rect.width, height: n.rect.height)
            let corner: CGFloat = 6
            let path = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
            ctx.addPath(path)
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fillPath()
            let header = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 28)
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil))
            ctx.clip()
            ctx.setFillColor(CGColor(red: 0.85, green: 0.90, blue: 1, alpha: 1))
            ctx.fill(header)
            ctx.restoreGState()
            ctx.addPath(path)
            ctx.setStrokeColor(CGColor(gray: 0.72, alpha: 1))
            ctx.setLineWidth(1)
            ctx.strokePath()

            drawText(n.title, at: CGPoint(x: rect.minX + 10, y: rect.minY + 8), fontSize: 13, bold: true, in: ctx)
            var y = header.maxY + 4
            for line in n.lines {
                if y > rect.maxY - 8 { break }
                drawText(line, at: CGPoint(x: rect.minX + 10, y: y), fontSize: 11, monospace: true, in: ctx)
                y += 16
            }
        }
    }

    private static func drawText(_ text: String, at point: CGPoint, fontSize: CGFloat, bold: Bool = false, monospace: Bool = false, in ctx: CGContext) {
        let font: CTFont
        if monospace {
            font = CTFontCreateWithName("Menlo" as CFString, fontSize, nil)
        } else if bold {
            font = CTFontCreateUIFontForLanguage(.emphasizedSystem, fontSize, nil) ?? CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
        } else {
            font = CTFontCreateUIFontForLanguage(.system, fontSize, nil) ?? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: CGColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1),
        ]
        let attr = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attr)
        ctx.textPosition = CGPoint(x: point.x, y: point.y + fontSize)
        // Text goes in current coordinate space; save and flip locally so
        // it renders right-side-up regardless of caller transform.
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -fontSize - point.y - point.y)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}
#endif

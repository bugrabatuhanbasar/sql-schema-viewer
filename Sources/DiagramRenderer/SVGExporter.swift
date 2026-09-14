import Foundation
import SchemaModel

/// Serializes a `DiagramScene` to true-vector SVG text. Zero
/// dependencies — the output is byte-stable for a given scene, which is
/// what `RendererGoldenTests` relies on.
public enum SVGExporter {
    public static func export(_ scene: DiagramScene, style: Style = .light) -> String {
        var maxX: Double = 0, maxY: Double = 0
        for n in scene.nodes {
            maxX = max(maxX, n.rect.x + n.rect.width)
            maxY = max(maxY, n.rect.y + n.rect.height)
        }
        let w = Int(maxX + 40), h = Int(maxY + 40)
        var out: [String] = []
        out.append(#"<?xml version="1.0" encoding="UTF-8" standalone="no"?>"#)
        out.append("""
        <svg xmlns="http://www.w3.org/2000/svg" width="\(w)" height="\(h)" viewBox="0 0 \(w) \(h)">
        """)
        out.append(#"<style>text{font-family:-apple-system,Helvetica,Arial,sans-serif;font-size:12px;fill:\#(style.textColor);}</style>"#)
        out.append(#"<rect x="0" y="0" width="100%" height="100%" fill="\#(style.background)"/>"#)

        let bx0 = scene.nodes.map(\.rect.x).min() ?? 0
        let bx1 = scene.nodes.map { $0.rect.x + $0.rect.width }.max() ?? 0
        for edge in scene.edges {
            let firstPoint: (x: Double, y: Double)
            let lastPoint: (x: Double, y: Double)
            let firstDir: (x: Double, y: Double)
            let lastDir: (x: Double, y: Double)
            if !edge.waypoints.isEmpty {
                let pts = edge.waypoints
                var d = "M \(pts[0].x) \(pts[0].y)"
                for i in 1..<pts.count { d += " L \(pts[i].x) \(pts[i].y)" }
                out.append(#"<path d="\#(d)" fill="none" stroke="\#(style.edgeColor)" stroke-width="1.3" stroke-linejoin="miter"/>"#)
                firstPoint = (pts[0].x, pts[0].y)
                lastPoint  = (pts[pts.count - 1].x, pts[pts.count - 1].y)
                firstDir = unit(from: pts[0], to: pts[1])
                lastDir  = unit(from: pts[pts.count - 2], to: pts[pts.count - 1])
            } else {
                let p1 = edge.fromRect.borderPoint(toward: (edge.toRect.midX, edge.toRect.midY))
                let p2 = edge.toRect.borderPoint(toward: (edge.fromRect.midX, edge.fromRect.midY))
                let c1x: Double, c2x: Double
                if edge.isLongSpan {
                    let bothLeft = (p1.x + p2.x) / 2 < (bx0 + bx1) / 2
                    let dx: Double = bothLeft ? bx0 - 60 : bx1 + 60
                    c1x = dx; c2x = dx
                } else {
                    let m = (p1.x + p2.x) / 2
                    c1x = m; c2x = m
                }
                let path = "M \(p1.x) \(p1.y) C \(c1x) \(p1.y) \(c2x) \(p2.y) \(p2.x) \(p2.y)"
                out.append(#"<path d="\#(path)" fill="none" stroke="\#(style.edgeColor)" stroke-width="1.3"/>"#)
                firstPoint = p1; lastPoint = p2
                let (dx, dy) = (p2.x - p1.x, p2.y - p1.y)
                let len = max(1, (dx * dx + dy * dy).squareRoot())
                firstDir = (dx / len, dy / len); lastDir = firstDir
            }

            let fx = firstPoint.x + firstDir.x * 18
            let fy = firstPoint.y + firstDir.y * 18
            out.append(pillLabel(edge.fromCardinality, x: fx, y: fy, style: style))
            let tx = lastPoint.x - lastDir.x * 18
            let ty = lastPoint.y - lastDir.y * 18
            out.append(pillLabel(edge.toCardinality, x: tx, y: ty, style: style))
        }

        for n in scene.nodes {
            let rx = n.rect.x, ry = n.rect.y, rw = n.rect.width, rh = n.rect.height
            out.append(#"<rect x="\#(rx)" y="\#(ry)" width="\#(rw)" height="\#(rh)" rx="8" ry="8" fill="\#(style.nodeFill)" stroke="\#(style.nodeStroke)" stroke-width="1"/>"#)
            out.append(#"<rect x="\#(rx)" y="\#(ry)" width="\#(rw)" height="30" rx="8" ry="8" fill="\#(style.headerFill)"/>"#)
            out.append(#"<text x="\#(rx + 10)" y="\#(ry + 20)" font-weight="600">\#(escape(n.title))</text>"#)
            var ty = ry + 46
            for line in n.lines {
                if ty > ry + rh - 6 { break }
                out.append(#"<text x="\#(rx + 10)" y="\#(ty)" font-family="Menlo,monospace" font-size="11">\#(escape(line))</text>"#)
                ty += 16
            }
        }
        out.append("</svg>")
        return out.joined(separator: "\n") + "\n"
    }

    private static func labelPoint(near p: (x: Double, y: Double), opposite q: (x: Double, y: Double), offset: Double) -> (Double, Double) {
        let dx = q.x - p.x, dy = q.y - p.y
        let len = max(1, (dx * dx + dy * dy).squareRoot())
        return (p.x + dx / len * offset, p.y + dy / len * offset)
    }

    private static func unit(from a: DiagramScene.Point, to b: DiagramScene.Point) -> (x: Double, y: Double) {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = max(0.0001, (dx * dx + dy * dy).squareRoot())
        return (dx / len, dy / len)
    }

    /// SVG `d` attribute for a rounded-corner polyline. Corners are
    /// smoothed with quadratic bezier arcs (control point at the sharp
    /// vertex), matching what the on-screen canvas draws.
    private static func roundedPolylinePathData(points pts: [DiagramScene.Point], radius: Double) -> String {
        guard pts.count >= 2 else { return "" }
        var d = "M \(pts[0].x) \(pts[0].y)"
        for i in 1..<(pts.count - 1) {
            let prev = pts[i - 1], curr = pts[i], next = pts[i + 1]
            let dxIn = curr.x - prev.x, dyIn = curr.y - prev.y
            let dxOut = next.x - curr.x, dyOut = next.y - curr.y
            let lenIn = max(0.0001, (dxIn * dxIn + dyIn * dyIn).squareRoot())
            let lenOut = max(0.0001, (dxOut * dxOut + dyOut * dyOut).squareRoot())
            let r = min(radius, lenIn / 2, lenOut / 2)
            let ex = curr.x - dxIn / lenIn * r
            let ey = curr.y - dyIn / lenIn * r
            let xx = curr.x + dxOut / lenOut * r
            let xy = curr.y + dyOut / lenOut * r
            d += " L \(ex) \(ey) Q \(curr.x) \(curr.y) \(xx) \(xy)"
        }
        let last = pts[pts.count - 1]
        d += " L \(last.x) \(last.y)"
        return d
    }

    private static func pillLabel(_ text: String, x: Double, y: Double, style: Style) -> String {
        // width heuristic: ~7pt per glyph + 8 padding.
        let w = Double(text.count) * 7 + 10
        let h = 16.0
        let rx = x - w / 2, ry = y - h / 2
        return #"<g><rect x="\#(rx)" y="\#(ry)" width="\#(w)" height="\#(h)" rx="4" ry="4" fill="\#(style.labelFill)" stroke="\#(style.labelStroke)" stroke-width="0.5"/><text x="\#(x)" y="\#(y + 4)" text-anchor="middle" font-size="10" font-weight="600" fill="\#(style.textColor)">\#(escape(text))</text></g>"#
    }

    private static func escape(_ s: String) -> String {
        var r = s.replacingOccurrences(of: "&", with: "&amp;")
        r = r.replacingOccurrences(of: "<", with: "&lt;")
        r = r.replacingOccurrences(of: ">", with: "&gt;")
        r = r.replacingOccurrences(of: "\"", with: "&quot;")
        return r
    }

    public struct Style: Sendable {
        public var background: String
        public var textColor: String
        public var edgeColor: String
        public var nodeFill: String
        public var nodeStroke: String
        public var headerFill: String
        public var labelFill: String
        public var labelStroke: String
        public static let light = Style(
            background: "#fafafa", textColor: "#111",
            edgeColor: "#555", nodeFill: "#ffffff",
            nodeStroke: "#bbbbbb", headerFill: "#dbe7ff",
            labelFill: "#ffffff", labelStroke: "#cccccc"
        )
        public static let dark = Style(
            background: "#1c1c1e", textColor: "#f0f0f0",
            edgeColor: "#a0a0a0", nodeFill: "#2a2a2e",
            nodeStroke: "#555555", headerFill: "#3a4d69",
            labelFill: "#2f2f34", labelStroke: "#5a5a5a"
        )
    }
}

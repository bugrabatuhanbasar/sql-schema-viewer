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

        for edge in scene.edges {
            let p1 = edge.fromRect.borderPoint(toward: (edge.toRect.midX, edge.toRect.midY))
            let p2 = edge.toRect.borderPoint(toward: (edge.fromRect.midX, edge.fromRect.midY))
            let mid = (p1.x + p2.x) / 2
            let path = "M \(p1.x) \(p1.y) C \(mid) \(p1.y) \(mid) \(p2.y) \(p2.x) \(p2.y)"
            out.append(#"<path d="\#(path)" fill="none" stroke="\#(style.edgeColor)" stroke-width="1.3"/>"#)

            let (fx, fy) = labelPoint(near: p1, opposite: p2, offset: 18)
            let (tx, ty) = labelPoint(near: p2, opposite: p1, offset: 18)
            out.append(pillLabel(edge.fromCardinality, x: fx, y: fy, style: style))
            out.append(pillLabel(edge.toCardinality,   x: tx, y: ty, style: style))
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

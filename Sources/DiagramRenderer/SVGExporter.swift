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
            let mid = (edge.from.x + edge.to.x) / 2
            let path = "M \(edge.from.x) \(edge.from.y) C \(mid) \(edge.from.y) \(mid) \(edge.to.y) \(edge.to.x) \(edge.to.y)"
            out.append(#"<path d="\#(path)" fill="none" stroke="\#(style.edgeColor)" stroke-width="1.2"/>"#)
            // Cardinality labels 22 units from each endpoint along the edge.
            let dx = edge.to.x - edge.from.x, dy = edge.to.y - edge.from.y
            let len = max(1, (dx * dx + dy * dy).squareRoot())
            let fx = edge.from.x + dx / len * 22
            let fy = edge.from.y + dy / len * 22
            let tx = edge.to.x - dx / len * 22
            let ty = edge.to.y - dy / len * 22
            out.append(#"<text x="\#(fx)" y="\#(fy)" text-anchor="middle" font-weight="600" font-size="10">\#(escape(edge.fromCardinality))</text>"#)
            out.append(#"<text x="\#(tx)" y="\#(ty)" text-anchor="middle" font-weight="600" font-size="10">\#(escape(edge.toCardinality))</text>"#)
        }

        for n in scene.nodes {
            let rx = n.rect.x, ry = n.rect.y, rw = n.rect.width, rh = n.rect.height
            out.append(#"<rect x="\#(rx)" y="\#(ry)" width="\#(rw)" height="\#(rh)" rx="6" ry="6" fill="\#(style.nodeFill)" stroke="\#(style.nodeStroke)" stroke-width="1"/>"#)
            out.append(#"<rect x="\#(rx)" y="\#(ry)" width="\#(rw)" height="28" rx="6" ry="6" fill="\#(style.headerFill)"/>"#)
            out.append(#"<text x="\#(rx + 10)" y="\#(ry + 19)" font-weight="600">\#(escape(n.title))</text>"#)
            var ty = ry + 44
            for line in n.lines {
                if ty > ry + rh - 6 { break }
                out.append(#"<text x="\#(rx + 10)" y="\#(ty)" font-family="Menlo,monospace" font-size="11">\#(escape(line))</text>"#)
                ty += 16
            }
        }
        out.append("</svg>")
        return out.joined(separator: "\n") + "\n"
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
        public static let light = Style(
            background: "#fafafa", textColor: "#111",
            edgeColor: "#555", nodeFill: "#ffffff",
            nodeStroke: "#bbbbbb", headerFill: "#dbe7ff"
        )
        public static let dark = Style(
            background: "#1c1c1e", textColor: "#f0f0f0",
            edgeColor: "#a0a0a0", nodeFill: "#2a2a2e",
            nodeStroke: "#555555", headerFill: "#3a4d69"
        )
    }
}

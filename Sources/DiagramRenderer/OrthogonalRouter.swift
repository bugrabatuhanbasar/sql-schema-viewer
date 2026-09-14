import Foundation
import SchemaModel

/// Right-angle edge router used for the "Orthogonal" edge routing style.
///
/// # Algorithm — deliberately simple, ERD-tool-classic
///
/// For every FK edge we pick the two node faces the edge should cross based
/// on the dominant axis (dy vs dx), then draw a plain Z-shape from the
/// centre of the source's face to the centre of the target's face:
///
/// ```
///   source-centre ─▶ mid-channel  ─▶  target-centre
///        │                                 ▲
///        └───────── one bend ─────────────┘
/// ```
///
/// If source and target sit on the same axis the polyline collapses to a
/// straight line. Corners are sharp — no bezier smoothing — so the output
/// looks like the connectors in dbdiagram.io / DBeaver / DrawSQL rather
/// than a schematic bezier arc.
///
/// The older port-fanning + channel-packing pass produced too many wiggles
/// on hub tables; this version accepts that multiple edges leaving the
/// same face share a starting point, which is what human diagrams do too.
public enum OrthogonalRouter {

    public static func route(edges: [DiagramScene.EdgeShape]) -> [[DiagramScene.Point]] {
        edges.map { simpleRoute(from: $0.fromRect, to: $0.toRect) }
    }

    private static func simpleRoute(
        from src: DiagramScene.Rect,
        to dst: DiagramScene.Rect
    ) -> [DiagramScene.Point] {
        let dy = dst.midY - src.midY
        let dx = dst.midX - src.midX

        if abs(dy) >= abs(dx) {
            // Predominantly vertical — the FK-DAG common case.
            let goingDown = dy > 0
            let srcY = goingDown ? src.y + src.height : src.y
            let dstY = goingDown ? dst.y : dst.y + dst.height
            let srcPort = DiagramScene.Point(x: src.midX, y: srcY)
            let dstPort = DiagramScene.Point(x: dst.midX, y: dstY)
            if abs(src.midX - dst.midX) < 1 {
                // Aligned columns → single vertical segment.
                return [srcPort, dstPort]
            }
            let midY = (srcY + dstY) / 2
            return [
                srcPort,
                DiagramScene.Point(x: srcPort.x, y: midY),
                DiagramScene.Point(x: dstPort.x, y: midY),
                dstPort,
            ]
        } else {
            // Predominantly horizontal.
            let goingRight = dx > 0
            let srcX = goingRight ? src.x + src.width : src.x
            let dstX = goingRight ? dst.x : dst.x + dst.width
            let srcPort = DiagramScene.Point(x: srcX, y: src.midY)
            let dstPort = DiagramScene.Point(x: dstX, y: dst.midY)
            if abs(src.midY - dst.midY) < 1 {
                return [srcPort, dstPort]
            }
            let midX = (srcX + dstX) / 2
            return [
                srcPort,
                DiagramScene.Point(x: midX, y: srcPort.y),
                DiagramScene.Point(x: midX, y: dstPort.y),
                dstPort,
            ]
        }
    }
}

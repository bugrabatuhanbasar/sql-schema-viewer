import Foundation
import SchemaModel

/// Right-angle edge router used for the "Orthogonal" edge routing style.
///
/// # Two-pass algorithm
///
/// 1. **Group by source face + target face.** Every edge picks the face it
///    should leave the source on (top / bottom / left / right, chosen from
///    the dominant axis dy vs dx) and the opposite face on the target.
/// 2. **Fan the source ports** for edges sharing the same source face:
///    they are sorted by target position and their exit x (or y) is
///    distributed evenly across ~85 % of that face, so five children of a
///    hub table don't all leave from the same pixel.
/// 3. **Fan the target ports** by the same rule.
/// 4. **Stagger the mid-channel** for edges sharing the same source face:
///    the horizontal (or vertical) run gets a small slot-based offset so
///    parallel runs sit on different lanes instead of stacking on top of
///    each other — this was the "one bar split into five" bug in the
///    earlier screenshot.
///
/// Result: crisp Z-shapes that look like the connectors in dbdiagram.io
/// / DBeaver ER view / DrawSQL, with clean fan-outs on hub tables.
public enum OrthogonalRouter {

    public struct Config: Sendable {
        /// How far from a rect's corner the outermost port sits.
        public var portInset: Double = 14
        /// How wide the mid-channel lane spread should be (in points)
        /// between the first and last parallel edge sharing a face.
        public var laneSpread: Double = 32
        public init() {}
    }

    public static func route(
        edges: [DiagramScene.EdgeShape],
        config: Config = Config()
    ) -> [[DiagramScene.Point]] {
        // Assign each edge a source face + target face.
        var faces: [Face] = edges.map(Face.init(edge:))

        // Group by source face key (rect + which side) — these are the
        // edges we need to fan out. Same for target.
        var sourceGroups: [FaceKey: [Int]] = [:]
        var targetGroups: [FaceKey: [Int]] = [:]
        for (i, f) in faces.enumerated() {
            sourceGroups[f.srcKey, default: []].append(i)
            targetGroups[f.dstKey, default: []].append(i)
        }

        // Source port assignment: sort by opposite-endpoint coordinate
        // (target midX for vertical faces, target midY for horizontal),
        // then distribute along the source face with an inset.
        var sourceSlots: [Int: (slot: Int, count: Int)] = [:]
        for (_, ids) in sourceGroups {
            let sorted = ids.sorted { a, b in faces[a].dstProjected < faces[b].dstProjected }
            for (s, id) in sorted.enumerated() {
                sourceSlots[id] = (s, sorted.count)
            }
        }

        // Target port assignment: mirror image.
        var targetSlots: [Int: (slot: Int, count: Int)] = [:]
        for (_, ids) in targetGroups {
            let sorted = ids.sorted { a, b in faces[a].srcProjected < faces[b].srcProjected }
            for (s, id) in sorted.enumerated() {
                targetSlots[id] = (s, sorted.count)
            }
        }

        // Build the polyline for each edge.
        var routes: [[DiagramScene.Point]] = Array(repeating: [], count: edges.count)
        for (idx, f) in faces.enumerated() {
            let srcSlotInfo = sourceSlots[idx] ?? (0, 1)
            let dstSlotInfo = targetSlots[idx] ?? (0, 1)
            let srcPort = port(rect: f.srcRect, side: f.srcSide,
                               slot: srcSlotInfo.slot, count: srcSlotInfo.count,
                               inset: config.portInset)
            let dstPort = port(rect: f.dstRect, side: f.dstSide,
                               slot: dstSlotInfo.slot, count: dstSlotInfo.count,
                               inset: config.portInset)
            routes[idx] = polyline(
                src: srcPort, dst: dstPort,
                side: f.srcSide,
                laneSlot: srcSlotInfo.slot, laneCount: srcSlotInfo.count,
                laneSpread: config.laneSpread
            )
        }
        return routes
    }

    // MARK: internals

    private enum Side: Sendable { case top, bottom, left, right }

    private struct FaceKey: Hashable {
        var rectMinX: Double
        var rectMinY: Double
        var side: Side
    }
    private struct Face {
        var srcRect: DiagramScene.Rect
        var dstRect: DiagramScene.Rect
        var srcSide: Side
        var dstSide: Side
        var srcKey: FaceKey
        var dstKey: FaceKey
        /// Coordinate to sort source-face slots by (= target midX for
        /// vertical faces, target midY for horizontal). Puts the leftmost
        /// child under the leftmost port.
        var srcProjected: Double
        var dstProjected: Double

        init(edge: DiagramScene.EdgeShape) {
            self.srcRect = edge.fromRect
            self.dstRect = edge.toRect
            let dy = dstRect.midY - srcRect.midY
            let dx = dstRect.midX - srcRect.midX
            let srcSide: Side, dstSide: Side
            if abs(dy) >= abs(dx) {
                if dy < 0 { srcSide = .top;    dstSide = .bottom }
                else      { srcSide = .bottom; dstSide = .top }
            } else {
                if dx > 0 { srcSide = .right; dstSide = .left }
                else      { srcSide = .left;  dstSide = .right }
            }
            self.srcSide = srcSide; self.dstSide = dstSide
            self.srcKey = FaceKey(rectMinX: srcRect.x, rectMinY: srcRect.y, side: srcSide)
            self.dstKey = FaceKey(rectMinX: dstRect.x, rectMinY: dstRect.y, side: dstSide)
            switch srcSide {
            case .top, .bottom: srcProjected = dstRect.midX
            case .left, .right: srcProjected = dstRect.midY
            }
            switch dstSide {
            case .top, .bottom: dstProjected = srcRect.midX
            case .left, .right: dstProjected = srcRect.midY
            }
        }
    }

    private static func port(
        rect: DiagramScene.Rect, side: Side,
        slot: Int, count: Int, inset: Double
    ) -> DiagramScene.Point {
        let effectiveInset = min(inset, min(rect.width, rect.height) / 4)
        let (start, end): (Double, Double)
        switch side {
        case .top, .bottom:
            start = rect.x + effectiveInset
            end = rect.x + rect.width - effectiveInset
        case .left, .right:
            start = rect.y + effectiveInset
            end = rect.y + rect.height - effectiveInset
        }
        let coord: Double
        if count > 1 { coord = start + (end - start) * Double(slot) / Double(count - 1) }
        else         { coord = (start + end) / 2 }
        switch side {
        case .top:    return .init(x: coord, y: rect.y)
        case .bottom: return .init(x: coord, y: rect.y + rect.height)
        case .left:   return .init(x: rect.x, y: coord)
        case .right:  return .init(x: rect.x + rect.width, y: coord)
        }
    }

    /// Build the Z-shape polyline from source port to target port.
    /// `laneSlot` biases the mid-channel so parallel edges don't stack.
    private static func polyline(
        src: DiagramScene.Point,
        dst: DiagramScene.Point,
        side srcSide: Side,
        laneSlot: Int, laneCount: Int,
        laneSpread: Double
    ) -> [DiagramScene.Point] {
        // Distribute the mid coord across `laneSpread` around the average,
        // so 5 edges from the same face use 5 distinct mid lanes.
        let laneOffset: Double
        if laneCount > 1 {
            let normalized = (Double(laneSlot) / Double(laneCount - 1)) - 0.5
            laneOffset = normalized * laneSpread
        } else {
            laneOffset = 0
        }
        switch srcSide {
        case .top, .bottom:
            // Vertical exit → horizontal mid channel.
            let midYRaw = (src.y + dst.y) / 2
            let midY = midYRaw + laneOffset
            if abs(src.x - dst.x) < 0.5 { return [src, dst] }
            return [
                src,
                DiagramScene.Point(x: src.x, y: midY),
                DiagramScene.Point(x: dst.x, y: midY),
                dst,
            ]
        case .left, .right:
            // Horizontal exit → vertical mid channel.
            let midXRaw = (src.x + dst.x) / 2
            let midX = midXRaw + laneOffset
            if abs(src.y - dst.y) < 0.5 { return [src, dst] }
            return [
                src,
                DiagramScene.Point(x: midX, y: src.y),
                DiagramScene.Point(x: midX, y: dst.y),
                dst,
            ]
        }
    }
}

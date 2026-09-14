import Foundation
import SchemaModel

/// Right-angle edge router with channel packing.
///
/// # Design
///
/// Given a set of node rects and a set of FK edges (source rect → target
/// rect), produce for each edge a polyline of the form:
///
/// ```
///   source ─▶ vertical stub ─▶ horizontal channel ─▶ vertical stub ─▶ target
/// ```
///
/// Each edge picks a **port** on each end (bottom/top/left/right), and the
/// port slot is distributed across the node's side so multiple edges on
/// the same node don't overlap. Horizontal segments run through **channels**
/// — thin strips of empty space between layers — and multiple edges that
/// share a channel are packed onto distinct sub-lanes so they don't collide.
///
/// This is a compact, one-pass heuristic — not full Sugiyama — but it
/// matches what professional ERD tools produce for typical FK graphs.
public enum OrthogonalRouter {

    public struct Config: Sendable {
        public var portInsetFromRectCorner: Double = 24
        public var stubLength: Double = 22
        public var channelLaneStep: Double = 12
        public init() {}
    }

    /// Compute the polyline for every edge given the layout that produced
    /// the current rects. Order preserved.
    public static func route(
        edges: [DiagramScene.EdgeShape],
        config: Config = Config()
    ) -> [[DiagramScene.Point]] {
        // 1. Assign a target port on each rect side per edge.
        //    - Edges going strictly up exit from the source top and enter
        //      the target bottom (typical FK-DAG shape).
        //    - Edges going strictly down do the reverse.
        //    - Otherwise, route side-to-side (right→left or left→right).
        var portsBySide: [PortKey: [PortAssignment]] = [:]
        var descriptors: [Descriptor] = []
        for (idx, edge) in edges.enumerated() {
            let d = descriptorFor(edge: edge, index: idx)
            descriptors.append(d)
            portsBySide[PortKey(rectMinX: d.srcRect.x, rectMinY: d.srcRect.y, side: d.srcSide), default: []]
                .append(PortAssignment(edgeIndex: idx, sortKey: d.srcSortKey))
            portsBySide[PortKey(rectMinX: d.dstRect.x, rectMinY: d.dstRect.y, side: d.dstSide), default: []]
                .append(PortAssignment(edgeIndex: idx, sortKey: d.dstSortKey))
        }

        // Sort each side's ports by sortKey, distribute them evenly across
        // the middle 60 % of the rect side.
        var portPoints: [Int: (src: DiagramScene.Point, dst: DiagramScene.Point)] = [:]
        for (_, port) in descriptors.enumerated() {
            portPoints[port.index] = (
                .init(x: 0, y: 0), .init(x: 0, y: 0)  // filled below
            )
        }
        func distribute(rect: DiagramScene.Rect, side: Side, count: Int, slot: Int) -> DiagramScene.Point {
            let inset = min(config.portInsetFromRectCorner, min(rect.width, rect.height) / 3)
            let usableStart: Double
            let usableEnd: Double
            let axis: String
            switch side {
            case .top, .bottom:
                usableStart = rect.x + inset
                usableEnd = rect.x + rect.width - inset
                axis = "x"
            case .left, .right:
                usableStart = rect.y + inset
                usableEnd = rect.y + rect.height - inset
                axis = "y"
            }
            let step = count > 1 ? (usableEnd - usableStart) / Double(count - 1) : 0
            let coord = count > 1 ? usableStart + step * Double(slot) : (usableStart + usableEnd) / 2
            switch side {
            case .top:    _ = axis; return .init(x: coord, y: rect.y)
            case .bottom: return .init(x: coord, y: rect.y + rect.height)
            case .left:   return .init(x: rect.x, y: coord)
            case .right:  return .init(x: rect.x + rect.width, y: coord)
            }
        }
        for (key, assignments) in portsBySide {
            let sorted = assignments.sorted { $0.sortKey < $1.sortKey }
            for (slot, assign) in sorted.enumerated() {
                let d = descriptors[assign.edgeIndex]
                let isSrc = (d.srcRect.x == key.rectMinX && d.srcRect.y == key.rectMinY && d.srcSide == key.side)
                if isSrc {
                    let p = distribute(rect: d.srcRect, side: d.srcSide, count: sorted.count, slot: slot)
                    portPoints[assign.edgeIndex]?.src = p
                } else {
                    let p = distribute(rect: d.dstRect, side: d.dstSide, count: sorted.count, slot: slot)
                    portPoints[assign.edgeIndex]?.dst = p
                }
            }
        }

        // 2. For each edge, walk from source port along its stub, then a
        //    horizontal channel at a per-edge lane offset, then along the
        //    target stub. Lane offsets are picked so that edges sharing a
        //    channel don't lie on the same y (up-down) or x (left-right).
        var routes: [[DiagramScene.Point]] = Array(repeating: [], count: edges.count)
        var channelUsage: [Int: [ChannelEntry]] = [:]  // integer-quantized y (or x) → sorted lanes
        for (idx, d) in descriptors.enumerated() {
            guard let (src, dst) = portPoints[idx] else { continue }
            routes[idx] = polyline(
                src: src, dst: dst,
                descriptor: d,
                stub: config.stubLength,
                laneStep: config.channelLaneStep,
                channelUsage: &channelUsage
            )
        }
        return routes
    }

    // MARK: Helpers

    private enum Side: Sendable, Hashable { case top, bottom, left, right }

    private struct PortKey: Hashable {
        var rectMinX: Double; var rectMinY: Double; var side: Side
    }
    private struct PortAssignment {
        var edgeIndex: Int
        var sortKey: Double
    }
    private struct Descriptor {
        var index: Int
        var srcRect: DiagramScene.Rect
        var dstRect: DiagramScene.Rect
        var srcSide: Side
        var dstSide: Side
        var srcSortKey: Double
        var dstSortKey: Double
        /// Predominant direction of the edge — "up" (dst above src) vs "down"
        /// vs "sideways". Used to pick the port faces and to lay out the
        /// mid-channel.
        var direction: Direction
    }
    private enum Direction: Sendable { case up, down, right, left }

    private static func descriptorFor(edge: DiagramScene.EdgeShape, index: Int) -> Descriptor {
        let src = edge.fromRect, dst = edge.toRect
        let dy = dst.midY - src.midY
        let dx = dst.midX - src.midX
        let dir: Direction
        let srcSide: Side, dstSide: Side
        if abs(dy) >= abs(dx) {
            if dy < 0 { dir = .up;   srcSide = .top;    dstSide = .bottom }
            else      { dir = .down; srcSide = .bottom; dstSide = .top }
        } else {
            if dx > 0 { dir = .right; srcSide = .right; dstSide = .left }
            else      { dir = .left;  srcSide = .left;  dstSide = .right }
        }
        // Sort key so ports fan out in the direction of travel (leftmost
        // target x picks the leftmost port on the source top, etc.).
        let srcKey: Double = (dir == .up || dir == .down) ? dst.midX : dst.midY
        let dstKey: Double = (dir == .up || dir == .down) ? src.midX : src.midY
        return Descriptor(
            index: index,
            srcRect: src, dstRect: dst,
            srcSide: srcSide, dstSide: dstSide,
            srcSortKey: srcKey, dstSortKey: dstKey,
            direction: dir
        )
    }

    private struct ChannelEntry: Hashable {
        var edgeIndex: Int
        var lane: Int
    }

    private static func polyline(
        src: DiagramScene.Point,
        dst: DiagramScene.Point,
        descriptor d: Descriptor,
        stub: Double,
        laneStep: Double,
        channelUsage: inout [Int: [ChannelEntry]]
    ) -> [DiagramScene.Point] {
        // Compute the raw path first, then bin the channel y (or x) so we
        // can offset duplicates onto separate lanes.
        switch d.direction {
        case .up:
            // src port sits on src.top, dst port sits on dst.bottom.
            let stub1 = DiagramScene.Point(x: src.x, y: src.y - stub)
            let stub2 = DiagramScene.Point(x: dst.x, y: dst.y + stub)
            let midYRaw = (stub1.y + stub2.y) / 2
            let (midY, _) = pickLane(dimension: midYRaw, group: d.index,
                                     usage: &channelUsage, laneStep: laneStep)
            return [
                src,
                stub1,
                DiagramScene.Point(x: stub1.x, y: midY),
                DiagramScene.Point(x: stub2.x, y: midY),
                stub2,
                dst,
            ]
        case .down:
            let stub1 = DiagramScene.Point(x: src.x, y: src.y + stub)
            let stub2 = DiagramScene.Point(x: dst.x, y: dst.y - stub)
            let midYRaw = (stub1.y + stub2.y) / 2
            let (midY, _) = pickLane(dimension: midYRaw, group: d.index,
                                     usage: &channelUsage, laneStep: laneStep)
            return [
                src,
                stub1,
                DiagramScene.Point(x: stub1.x, y: midY),
                DiagramScene.Point(x: stub2.x, y: midY),
                stub2,
                dst,
            ]
        case .right:
            let stub1 = DiagramScene.Point(x: src.x + stub, y: src.y)
            let stub2 = DiagramScene.Point(x: dst.x - stub, y: dst.y)
            let midXRaw = (stub1.x + stub2.x) / 2
            let (midX, _) = pickLane(dimension: midXRaw, group: d.index,
                                     usage: &channelUsage, laneStep: laneStep)
            return [
                src,
                stub1,
                DiagramScene.Point(x: midX, y: stub1.y),
                DiagramScene.Point(x: midX, y: stub2.y),
                stub2,
                dst,
            ]
        case .left:
            let stub1 = DiagramScene.Point(x: src.x - stub, y: src.y)
            let stub2 = DiagramScene.Point(x: dst.x + stub, y: dst.y)
            let midXRaw = (stub1.x + stub2.x) / 2
            let (midX, _) = pickLane(dimension: midXRaw, group: d.index,
                                     usage: &channelUsage, laneStep: laneStep)
            return [
                src,
                stub1,
                DiagramScene.Point(x: midX, y: stub1.y),
                DiagramScene.Point(x: midX, y: stub2.y),
                stub2,
                dst,
            ]
        }
    }

    /// Quantize the raw channel coordinate to a 24-pt bin and hand out a
    /// zig-zagging lane offset so co-located edges don't overlap.
    private static func pickLane(
        dimension raw: Double,
        group: Int,
        usage: inout [Int: [ChannelEntry]],
        laneStep: Double
    ) -> (adjusted: Double, lane: Int) {
        let bin = Int((raw / 24).rounded())
        let existing = usage[bin] ?? []
        // Pick the lowest unused lane: 0, +1, -1, +2, -2, ...
        var lane = 0
        let usedLanes = Set(existing.map(\.lane))
        while usedLanes.contains(lane) {
            lane = lane >= 0 ? -(lane + 1) : -lane
        }
        usage[bin, default: []].append(ChannelEntry(edgeIndex: group, lane: lane))
        return (raw + Double(lane) * laneStep, lane)
    }
}

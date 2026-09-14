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
        /// Extra clearance around the diagram used by long-span detour
        /// routing so edges arc cleanly outside every node.
        public var detourClearance: Double = 60
        /// Short vertical (or horizontal) step off the source/target port
        /// before the detour turns toward the outer channel.
        public var detourStub: Double = 24
        public init() {}
    }

    public static func route(
        edges: [DiagramScene.EdgeShape],
        allNodes: [DiagramScene.NodeShape] = [],
        config: Config = Config()
    ) -> [[DiagramScene.Point]] {
        // Assign each edge a source face + target face.
        var faces: [Face] = edges.map(Face.init(edge:))

        // A single face (rect + side) can hold both outgoing and incoming
        // ports at once — e.g. `threads` sends an FK up to `users` from
        // its top edge AND receives one from `thread_posts` on the same
        // top edge. If we assign source and target ports on that face in
        // separate passes, each pass sees only its own port and puts it
        // at the geometric centre → both ports overlap exactly.
        //
        // Instead: collect every port (source + target) that lands on a
        // given face into ONE list, sort by the position of the OTHER
        // endpoint, and distribute all of them across the face together.
        struct PortEntry {
            var edgeIndex: Int
            var isSource: Bool
            var projected: Double
        }
        var facePorts: [FaceKey: [PortEntry]] = [:]
        for (i, f) in faces.enumerated() {
            facePorts[f.srcKey, default: []].append(
                PortEntry(edgeIndex: i, isSource: true,  projected: f.dstProjected)
            )
            facePorts[f.dstKey, default: []].append(
                PortEntry(edgeIndex: i, isSource: false, projected: f.srcProjected)
            )
        }

        var sourceSlots: [Int: (slot: Int, count: Int)] = [:]
        var targetSlots: [Int: (slot: Int, count: Int)] = [:]
        for (_, entries) in facePorts {
            let sorted = entries.sorted { $0.projected < $1.projected }
            for (slot, entry) in sorted.enumerated() {
                let info = (slot, sorted.count)
                if entry.isSource { sourceSlots[entry.edgeIndex] = info }
                else              { targetSlots[entry.edgeIndex] = info }
            }
        }

        // Build a tentative polyline for each edge — source-fan slots
        // give the initial lane bias so children of a hub table start out
        // on distinct lanes.
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

        // Rescue long-span edges: any Z-shape whose mid segment passes
        // *through* another table (not the endpoints') gets re-routed as
        // a 6-point detour that arcs cleanly outside the diagram bounds.
        // Without this the "posts → users" edge from the sample schema
        // slices horizontally right through `threads` and `audit_events`
        // because its natural mid_y = (654 + 196) / 2 = 425 sits smack in
        // the middle of layer 1.
        if !allNodes.isEmpty {
            let bx0 = allNodes.map(\.rect.x).min() ?? 0
            let bx1 = allNodes.map { $0.rect.x + $0.rect.width }.max() ?? 0
            let by0 = allNodes.map(\.rect.y).min() ?? 0
            let by1 = allNodes.map { $0.rect.y + $0.rect.height }.max() ?? 0

            // First pass: find edges that need a detour and record their
            // preferred outer side. Group them by (source face, outer side)
            // so we can hand each edge a distinct lane along the outer
            // channel.
            struct DetourNeed { var edgeIndex: Int; var srcSide: Side; var goingLeft: Bool; var goingUp: Bool }
            var needs: [DetourNeed] = []
            for (idx, route) in routes.enumerated() {
                let f = faces[idx]
                if routeCollidesWithNodes(route, allNodes: allNodes, exclude: [f.srcRect, f.dstRect]) {
                    let midX = (route[0].x + route[route.count - 1].x) / 2
                    let midY = (route[0].y + route[route.count - 1].y) / 2
                    needs.append(DetourNeed(
                        edgeIndex: idx, srcSide: f.srcSide,
                        goingLeft: midX - bx0 < bx1 - midX,
                        goingUp:   midY - by0 < by1 - midY
                    ))
                }
            }

            // Group by (outer side used, i.e. left vs right vs up vs down)
            // — every group shares an outer channel and gets slots 0, 1,
            // 2… spread by `laneSpread` so parallel detours end up on
            // distinct rails instead of stacking on the same x (or y).
            struct GroupKey: Hashable { var horizontalOuter: Bool; var positive: Bool }
            var groupIds: [GroupKey: [Int]] = [:]
            for (i, n) in needs.enumerated() {
                let horizontalOuter: Bool
                let positive: Bool
                switch n.srcSide {
                case .top, .bottom:
                    horizontalOuter = true
                    positive = !n.goingLeft    // true = right outer, false = left
                case .left, .right:
                    horizontalOuter = false
                    positive = !n.goingUp      // true = bottom outer, false = top
                }
                groupIds[GroupKey(horizontalOuter: horizontalOuter, positive: positive), default: []].append(i)
            }
            var slotOf: [Int: Int] = [:]
            for (_, group) in groupIds {
                // Sort by src.y for vertical-exit edges, src.x for horizontal-
                // exit edges. Ports closer to the outer channel edge take
                // the innermost lane.
                let sorted = group.sorted { a, b in
                    let ra = routes[needs[a].edgeIndex][0]
                    let rb = routes[needs[b].edgeIndex][0]
                    return ra.y != rb.y ? ra.y < rb.y : ra.x < rb.x
                }
                for (slot, i) in sorted.enumerated() { slotOf[i] = slot }
            }

            for (i, need) in needs.enumerated() {
                let slot = slotOf[i] ?? 0
                let offset = Double(slot) * config.laneSpread
                let leftX  = bx0 - config.detourClearance - offset
                let rightX = bx1 + config.detourClearance + offset
                let topY   = by0 - config.detourClearance - offset
                let bottomY = by1 + config.detourClearance + offset
                let route = routes[need.edgeIndex]
                routes[need.edgeIndex] = detourPolyline(
                    src: route[0], dst: route[route.count - 1],
                    srcSide: need.srcSide,
                    detourX: need.goingLeft ? leftX : rightX,
                    detourY: need.goingUp   ? topY  : bottomY,
                    stub: config.detourStub
                )
            }
        }

        // Global collision resolution: any pair of edges whose mid channels
        // overlap on the same lane get pushed apart.
        resolveChannelCollisions(&routes, laneStep: 22)

        return routes
    }

    /// Does any segment of the polyline clip a non-endpoint node's rect?
    private static func routeCollidesWithNodes(
        _ route: [DiagramScene.Point],
        allNodes: [DiagramScene.NodeShape],
        exclude: [DiagramScene.Rect]
    ) -> Bool {
        for node in allNodes {
            let r = node.rect
            let isEndpoint = exclude.contains { rect in
                abs(rect.x - r.x) < 0.5 && abs(rect.y - r.y) < 0.5
            }
            if isEndpoint { continue }
            for i in 0..<(route.count - 1) {
                let a = route[i], b = route[i + 1]
                if segmentIntersectsRect(a: a, b: b, rect: r) { return true }
            }
        }
        return false
    }

    private static func segmentIntersectsRect(a: DiagramScene.Point, b: DiagramScene.Point, rect: DiagramScene.Rect) -> Bool {
        // Liang–Barsky, same as DiagramRenderer.
        let pad = 4.0
        let xmin = rect.x - pad, xmax = rect.x + rect.width + pad
        let ymin = rect.y - pad, ymax = rect.y + rect.height + pad
        var t0 = 0.0, t1 = 1.0
        let dx = b.x - a.x, dy = b.y - a.y
        let p = [-dx, dx, -dy, dy]
        let q = [a.x - xmin, xmax - a.x, a.y - ymin, ymax - a.y]
        for i in 0..<4 {
            if p[i] == 0 {
                if q[i] < 0 { return false }
            } else {
                let t = q[i] / p[i]
                if p[i] < 0 { if t > t1 { return false }; if t > t0 { t0 = t } }
                else { if t < t0 { return false }; if t < t1 { t1 = t } }
            }
        }
        return true
    }

    /// 6-point detour polyline: exits the source port, walks a short stub,
    /// arcs OUTSIDE the diagram on the closer side, drops to target level,
    /// walks a short stub back, and enters the target port.
    private static func detourPolyline(
        src: DiagramScene.Point, dst: DiagramScene.Point,
        srcSide: Side,
        detourX: Double, detourY: Double,
        stub: Double
    ) -> [DiagramScene.Point] {
        switch srcSide {
        case .top:
            // Source exits upward; target enters from below.
            // Stub goes up; detour turns horizontally at src.y - stub;
            // vertical arm at detourX; second turn at dst.y + stub;
            // stub back to target.
            let srcAway = DiagramScene.Point(x: src.x, y: src.y - stub)
            let dstAway = DiagramScene.Point(x: dst.x, y: dst.y + stub)
            return [
                src,
                srcAway,
                DiagramScene.Point(x: detourX, y: srcAway.y),
                DiagramScene.Point(x: detourX, y: dstAway.y),
                dstAway,
                dst,
            ]
        case .bottom:
            let srcAway = DiagramScene.Point(x: src.x, y: src.y + stub)
            let dstAway = DiagramScene.Point(x: dst.x, y: dst.y - stub)
            return [
                src,
                srcAway,
                DiagramScene.Point(x: detourX, y: srcAway.y),
                DiagramScene.Point(x: detourX, y: dstAway.y),
                dstAway,
                dst,
            ]
        case .left:
            let srcAway = DiagramScene.Point(x: src.x - stub, y: src.y)
            let dstAway = DiagramScene.Point(x: dst.x + stub, y: dst.y)
            return [
                src,
                srcAway,
                DiagramScene.Point(x: srcAway.x, y: detourY),
                DiagramScene.Point(x: dstAway.x, y: detourY),
                dstAway,
                dst,
            ]
        case .right:
            let srcAway = DiagramScene.Point(x: src.x + stub, y: src.y)
            let dstAway = DiagramScene.Point(x: dst.x - stub, y: dst.y)
            return [
                src,
                srcAway,
                DiagramScene.Point(x: srcAway.x, y: detourY),
                DiagramScene.Point(x: dstAway.x, y: detourY),
                dstAway,
                dst,
            ]
        }
    }

    /// Slide mid channels apart when they'd otherwise overlap. Each edge's
    /// polyline is a 4-point Z-shape: [src, corner1, corner2, dst]. The
    /// segment from corner1 → corner2 is the mid channel we're allowed to
    /// slide; the two stubs (src→corner1 and corner2→dst) are anchored to
    /// their node borders and stay put.
    ///
    /// For each iteration we collect every mid segment, sort by lane, walk
    /// forward, and any two segments whose lanes are closer than `laneStep`
    /// AND whose orthogonal ranges overlap get separated. Bounded by a
    /// small iteration cap so a pathological schema can't loop.
    private static func resolveChannelCollisions(
        _ routes: inout [[DiagramScene.Point]],
        laneStep: Double
    ) {
        struct MidSeg { var index: Int; var isHorizontal: Bool; var lane: Double; var range: (Double, Double) }
        for _ in 0..<24 {
            var segs: [MidSeg] = []
            for (i, r) in routes.enumerated() where r.count == 4 {
                // r = [src, corner1, corner2, dst]
                if abs(r[1].y - r[2].y) < 0.5 {
                    // Horizontal mid (possibly zero-length when the two
                    // corners share the same x — still worth tracking so
                    // parallel Z-shapes get pushed apart).
                    segs.append(MidSeg(
                        index: i, isHorizontal: true,
                        lane: r[1].y,
                        range: (min(r[1].x, r[2].x) - 10, max(r[1].x, r[2].x) + 10)
                    ))
                } else if abs(r[1].x - r[2].x) < 0.5 {
                    segs.append(MidSeg(
                        index: i, isHorizontal: false,
                        lane: r[1].x,
                        range: (min(r[1].y, r[2].y) - 10, max(r[1].y, r[2].y) + 10)
                    ))
                }
            }
            var moved = false
            for orient in [true, false] {
                var group = segs.filter { $0.isHorizontal == orient }
                group.sort { $0.lane < $1.lane }
                for i in 0..<group.count {
                    for j in (i + 1)..<group.count {
                        let a = group[i], b = group[j]
                        if b.lane - a.lane >= laneStep { break }
                        let overlap = min(a.range.1, b.range.1) - max(a.range.0, b.range.0)
                        if overlap > 0 {
                            let bump = laneStep - (b.lane - a.lane)
                            let route = routes[b.index]
                            var updated = route
                            if b.isHorizontal {
                                updated[1] = DiagramScene.Point(x: route[1].x, y: route[1].y + bump)
                                updated[2] = DiagramScene.Point(x: route[2].x, y: route[2].y + bump)
                            } else {
                                updated[1] = DiagramScene.Point(x: route[1].x + bump, y: route[1].y)
                                updated[2] = DiagramScene.Point(x: route[2].x + bump, y: route[2].y)
                            }
                            routes[b.index] = updated
                            group[j].lane += bump
                            moved = true
                        }
                    }
                }
            }
            if !moved { break }
        }
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
            // Vertical exit → horizontal mid channel. Always emit a full
            // Z-shape (never collapse to a 2-point straight line) so the
            // global collision pass has a mid segment to slide along.
            let midYRaw = (src.y + dst.y) / 2
            let midY = midYRaw + laneOffset
            return [
                src,
                DiagramScene.Point(x: src.x, y: midY),
                DiagramScene.Point(x: dst.x, y: midY),
                dst,
            ]
        case .left, .right:
            let midXRaw = (src.x + dst.x) / 2
            let midX = midXRaw + laneOffset
            return [
                src,
                DiagramScene.Point(x: midX, y: src.y),
                DiagramScene.Point(x: midX, y: dst.y),
                dst,
            ]
        }
    }
}

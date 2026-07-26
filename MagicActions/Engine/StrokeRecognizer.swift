import Foundation
import CoreGraphics

/// $1 Unistroke Recognizer (Wobbrock, Wilson & Li, UIST 2007).
/// Template matcher with resampling, indicative-angle rotation, square scaling
/// and golden-section search over rotation. Straight-line strokes are handled
/// separately because non-uniform square scaling degenerates for 1-D paths.
enum StrokeRecognizer {
    static let sampleCount = 64
    static let squareSize: CGFloat = 250
    private static let angleRange: CGFloat = .pi / 4 // ±45°
    private static let anglePrecision: CGFloat = .pi / 90 // 2°
    private static let phi: CGFloat = 0.5 * (-1 + sqrt(5))

    /// Recognize a raw path against templates. Returns (templateID, score 0..1).
    static func recognize(_ raw: [CGPoint], templates: [StrokeTemplate], threshold: Double) -> (id: UUID, score: Double)? {
        guard raw.count >= 4 else { return nil }

        // 1-D strokes: classify as directional lines when a matching line template exists.
        if let line = lineDirection(raw) {
            if templates.contains(where: { $0.id == line.uuid }) {
                return (line.uuid, 1.0)
            }
            return nil
        }

        guard let candidate = normalize(raw) else { return nil }
        var best: (id: UUID, distance: CGFloat)?
        for template in templates {
            guard let processed = normalize(template.points) else { continue }
            let d = distanceAtBestAngle(candidate, processed)
            if best == nil || d < best!.distance {
                best = (template.id, d)
            }
        }
        guard let best else { return nil }
        let halfDiagonal = 0.5 * sqrt(2 * squareSize * squareSize)
        let score = Double(1 - best.distance / halfDiagonal)
        return score >= threshold ? (best.id, score) : nil
    }

    /// Detect near-1-D strokes and classify by dominant direction.
    static func lineDirection(_ raw: [CGPoint]) -> BuiltinStroke? {
        let box = boundingBox(raw)
        let w = box.width, h = box.height
        guard max(w, h) > 0 else { return nil }
        guard min(w, h) / max(w, h) < 0.25 else { return nil }
        guard let first = raw.first, let last = raw.last else { return nil }
        let dx = last.x - first.x
        let dy = last.y - first.y
        if abs(dx) >= abs(dy) {
            return dx > 0 ? .lineRight : .lineLeft
        } else {
            return dy > 0 ? .lineUp : .lineDown // touch coords: y up
        }
    }

    // MARK: - $1 pipeline

    static func normalize(_ points: [CGPoint]) -> [CGPoint]? {
        guard points.count >= 2 else { return nil }
        var pts = resample(points, to: sampleCount)
        guard pts.count >= 2 else { return nil }
        let angle = indicativeAngle(pts)
        pts = rotate(pts, by: -angle)
        pts = scaleToSquare(pts, size: squareSize)
        pts = translateToOrigin(pts)
        return pts
    }

    private static func resample(_ points: [CGPoint], to n: Int) -> [CGPoint] {
        let interval = pathLength(points) / CGFloat(n - 1)
        guard interval > 0 else { return points }
        var d: CGFloat = 0
        var newPoints = [points[0]]
        var pts = points
        var i = 1
        while i < pts.count {
            let dist = distance(pts[i - 1], pts[i])
            if d + dist >= interval {
                let t = (interval - d) / dist
                let q = CGPoint(
                    x: pts[i - 1].x + t * (pts[i].x - pts[i - 1].x),
                    y: pts[i - 1].y + t * (pts[i].y - pts[i - 1].y)
                )
                newPoints.append(q)
                pts.insert(q, at: i)
                d = 0
            } else {
                d += dist
            }
            i += 1
        }
        if newPoints.count == n - 1, let last = points.last {
            newPoints.append(last)
        }
        return newPoints
    }

    private static func indicativeAngle(_ points: [CGPoint]) -> CGFloat {
        let c = centroid(points)
        return atan2(c.y - points[0].y, c.x - points[0].x)
    }

    private static func rotate(_ points: [CGPoint], by angle: CGFloat) -> [CGPoint] {
        let c = centroid(points)
        let cosA = cos(angle), sinA = sin(angle)
        return points.map { p in
            CGPoint(
                x: (p.x - c.x) * cosA - (p.y - c.y) * sinA + c.x,
                y: (p.x - c.x) * sinA + (p.y - c.y) * cosA + c.y
            )
        }
    }

    private static func scaleToSquare(_ points: [CGPoint], size: CGFloat) -> [CGPoint] {
        let box = boundingBox(points)
        guard box.width > 0, box.height > 0 else { return points }
        return points.map { CGPoint(x: $0.x * size / box.width, y: $0.y * size / box.height) }
    }

    private static func translateToOrigin(_ points: [CGPoint]) -> [CGPoint] {
        let c = centroid(points)
        return points.map { CGPoint(x: $0.x - c.x, y: $0.y - c.y) }
    }

    private static func distanceAtBestAngle(_ candidate: [CGPoint], _ template: [CGPoint]) -> CGFloat {
        var a = -angleRange
        var b = angleRange
        var x1 = phi * a + (1 - phi) * b
        var f1 = distanceAtAngle(candidate, template, angle: x1)
        var x2 = (1 - phi) * a + phi * b
        var f2 = distanceAtAngle(candidate, template, angle: x2)
        while abs(b - a) > anglePrecision {
            if f1 < f2 {
                b = x2; x2 = x1; f2 = f1
                x1 = phi * a + (1 - phi) * b
                f1 = distanceAtAngle(candidate, template, angle: x1)
            } else {
                a = x1; x1 = x2; f1 = f2
                x2 = (1 - phi) * a + phi * b
                f2 = distanceAtAngle(candidate, template, angle: x2)
            }
        }
        return min(f1, f2)
    }

    private static func distanceAtAngle(_ candidate: [CGPoint], _ template: [CGPoint], angle: CGFloat) -> CGFloat {
        let rotated = rotate(candidate, by: angle)
        return pathDistance(rotated, template)
    }

    private static func pathDistance(_ a: [CGPoint], _ b: [CGPoint]) -> CGFloat {
        let n = min(a.count, b.count)
        guard n > 0 else { return .greatestFiniteMagnitude }
        var d: CGFloat = 0
        for i in 0..<n { d += distance(a[i], b[i]) }
        return d / CGFloat(n)
    }

    // MARK: - Geometry helpers

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(b.x - a.x, b.y - a.y)
    }

    private static func pathLength(_ points: [CGPoint]) -> CGFloat {
        var d: CGFloat = 0
        for i in 1..<points.count { d += distance(points[i - 1], points[i]) }
        return d
    }

    private static func centroid(_ points: [CGPoint]) -> CGPoint {
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    private static func boundingBox(_ points: [CGPoint]) -> CGRect {
        var minX = CGFloat.greatestFiniteMagnitude, minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
        for p in points {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// Built-in stroke shapes with stable IDs. Points use touch coordinates (y up).
enum BuiltinStroke: String, CaseIterable, Sendable {
    case lineUp, lineDown, lineLeft, lineRight
    case circle, zigzag, vee

    var uuid: UUID {
        switch self {
        case .lineUp: return UUID(uuidString: "B0000000-0000-4000-8000-000000000001")!
        case .lineDown: return UUID(uuidString: "B0000000-0000-4000-8000-000000000002")!
        case .lineLeft: return UUID(uuidString: "B0000000-0000-4000-8000-000000000003")!
        case .lineRight: return UUID(uuidString: "B0000000-0000-4000-8000-000000000004")!
        case .circle: return UUID(uuidString: "B0000000-0000-4000-8000-000000000005")!
        case .zigzag: return UUID(uuidString: "B0000000-0000-4000-8000-000000000006")!
        case .vee: return UUID(uuidString: "B0000000-0000-4000-8000-000000000007")!
        }
    }

    var name: String {
        switch self {
        case .lineUp: return "上ライン"
        case .lineDown: return "下ライン"
        case .lineLeft: return "左ライン"
        case .lineRight: return "右ライン"
        case .circle: return "丸"
        case .zigzag: return "ジグザグ（Z）"
        case .vee: return "V字"
        }
    }

    /// Template geometry; lines are recognized via lineDirection() and need no points.
    var points: [CGPoint] {
        switch self {
        case .lineUp: return interpolated([CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 1)])
        case .lineDown: return interpolated([CGPoint(x: 0.5, y: 1), CGPoint(x: 0.5, y: 0)])
        case .lineLeft: return interpolated([CGPoint(x: 1, y: 0.5), CGPoint(x: 0, y: 0.5)])
        case .lineRight: return interpolated([CGPoint(x: 0, y: 0.5), CGPoint(x: 1, y: 0.5)])
        case .circle:
            return (0...32).map { i -> CGPoint in
                let a = 2 * CGFloat.pi * CGFloat(i) / 32 + .pi / 2
                return CGPoint(x: 0.5 + 0.5 * cos(a), y: 0.5 + 0.5 * sin(a))
            }
        case .zigzag:
            return interpolated([CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0)])
        case .vee:
            return interpolated([CGPoint(x: 0, y: 1), CGPoint(x: 0.5, y: 0), CGPoint(x: 1, y: 1)])
        }
    }

    var template: StrokeTemplate {
        StrokeTemplate(id: uuid, name: name, points: points, isBuiltin: true)
    }

    /// Densify a polyline so resampling has enough raw material.
    private func interpolated(_ corners: [CGPoint], stepsPerSegment: Int = 16) -> [CGPoint] {
        var out: [CGPoint] = []
        for i in 1..<corners.count {
            let a = corners[i - 1], b = corners[i]
            for s in 0..<stepsPerSegment {
                let t = CGFloat(s) / CGFloat(stepsPerSegment)
                out.append(CGPoint(x: a.x + t * (b.x - a.x), y: a.y + t * (b.y - a.y)))
            }
        }
        if let last = corners.last { out.append(last) }
        return out
    }
}

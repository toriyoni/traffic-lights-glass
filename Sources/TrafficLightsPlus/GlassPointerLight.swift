import AppKit

struct GlassLightSample: Equatable {
    let position: CGPoint
    let intensity: CGFloat

    func offsetBy(dx: CGFloat, dy: CGFloat) -> Self {
        Self(position: CGPoint(x: position.x + dx, y: position.y + dy), intensity: intensity)
    }
}

/// One shared source illuminates the capsule and all three colored surfaces.
/// Only entry/exit fades need a timer; the light position follows pointer events.
struct GlassPointerLightState {
    private(set) var position: CGPoint?
    private(set) var intensity: CGFloat = 0
    private var target: CGFloat = 0
    var isAnimating: Bool { intensity != target }
    var sample: GlassLightSample? {
        guard intensity > 0, let position else { return nil }
        return GlassLightSample(position: position, intensity: intensity)
    }

    mutating func advance(pointer: CGPoint, inside: Bool, elapsed: TimeInterval, reduceMotion: Bool) {
        target = inside && pointer.x.isFinite && pointer.y.isFinite ? 1 : 0
        if target == 1 { position = pointer }
        if reduceMotion { intensity = target }
        else if elapsed.isFinite && elapsed > 0 {
            let response: TimeInterval = target == 1 ? 0.035 : 0.055
            intensity += (target - intensity) * CGFloat(-expm1(-elapsed / response))
            if abs(target - intensity) < 0.0005 { intensity = target }
        }
        if intensity == 0 && target == 0 { position = nil }
    }

    mutating func reset() { position = nil; intensity = 0; target = 0 }
}

/// Optical additions are clipped to the actual material contour. Nothing here
/// replaces the native glass fill/refraction or creates a permanent outline.
struct GlassLightGeometry {
    let path: CGPath
    let bounds: CGRect
    private let boundary: [CGPoint]
    private let broadRim: CGPath
    private let fineRim: CGPath

    init(path: CGPath) {
        self.path = path
        bounds = path.boundingBoxOfPath
        broadRim = path.copy(strokingWithWidth: 5, lineCap: .round, lineJoin: .round, miterLimit: 2)
        fineRim = path.copy(strokingWithWidth: 1.5, lineCap: .round, lineJoin: .round, miterLimit: 2)
        var points: [CGPoint] = []
        var current = CGPoint.zero, start = CGPoint.zero
        path.applyWithBlock { item in
            let element = item.pointee
            switch element.type {
            case .moveToPoint:
                current = element.points[0]; start = current; points.append(current)
            case .addLineToPoint:
                current = element.points[0]; points.append(current)
            case .addQuadCurveToPoint:
                let origin = current, control = element.points[0], end = element.points[1]
                for step in 1...12 {
                    let t = CGFloat(step) / 12, u = 1 - t
                    points.append(CGPoint(x: u*u*origin.x + 2*u*t*control.x + t*t*end.x,
                                          y: u*u*origin.y + 2*u*t*control.y + t*t*end.y))
                }
                current = end
            case .addCurveToPoint:
                let origin = current, a = element.points[0], b = element.points[1], end = element.points[2]
                for step in 1...16 {
                    let t = CGFloat(step) / 16, u = 1 - t
                    points.append(CGPoint(x: u*u*u*origin.x + 3*u*u*t*a.x + 3*u*t*t*b.x + t*t*t*end.x,
                                          y: u*u*u*origin.y + 3*u*u*t*a.y + 3*u*t*t*b.y + t*t*t*end.y))
                }
                current = end
            case .closeSubpath: points.append(start); current = start
            @unknown default: break
            }
        }
        boundary = points
    }

    func distanceToBoundary(from point: CGPoint) -> CGFloat {
        guard point.x.isFinite, point.y.isFinite else { return .infinity }
        return zip(boundary, boundary.dropFirst()).reduce(CGFloat.infinity) { distance, pair in
            let a = pair.0, b = pair.1
            let dx = b.x - a.x, dy = b.y - a.y
            let lengthSquared = dx*dx + dy*dy
            let t = lengthSquared > 0 ? min(1, max(0, ((point.x-a.x)*dx + (point.y-a.y)*dy) / lengthSquared)) : 0
            return min(distance, hypot(point.x-a.x-dx*t, point.y-a.y-dy*t))
        }
    }

    func edgeStrength(at point: CGPoint) -> CGFloat {
        let reach = min(14, max(8, bounds.height * 0.3))
        let amount = max(0, 1 - distanceToBoundary(from: point) / reach)
        return amount * amount * (3 - 2 * amount)
    }

    func draw(sample: GlassLightSample?, dark: Bool, in context: CGContext) {
        guard let sample, sample.intensity.isFinite, sample.intensity > 0,
              sample.position.x.isFinite, sample.position.y.isFinite,
              bounds.width > 0, bounds.height > 0 else { return }
        let opacity = min(1, sample.intensity)
        let radius = max(16, min(40, min(bounds.width, bounds.height) * 0.9))
        context.saveGState()
        context.addPath(path); context.clip()
        context.setBlendMode(.screen)
        glow(in: context, at: sample.position, radius: radius, opacity: opacity * (dark ? 0.18 : 0.24))
        glow(in: context, at: sample.position, radius: radius * 0.32, opacity: opacity * 0.12)
        let edge = edgeStrength(at: sample.position) * opacity
        if edge > 0.001 {
            context.saveGState()
            context.addPath(broadRim); context.clip()
            glow(in: context, at: sample.position, radius: radius * 0.8, opacity: edge * 0.24)
            context.restoreGState()
            context.addPath(fineRim); context.clip()
            glow(in: context, at: sample.position, radius: radius * 0.7, opacity: edge * (dark ? 0.78 : 0.9))
        }
        context.restoreGState()
    }

    private func glow(in context: CGContext, at point: CGPoint, radius: CGFloat, opacity: CGFloat) {
        let components: [CGFloat] = [1, 1, 1, opacity, 1, 1, 1, opacity * 0.35, 1, 1, 1, 0]
        guard let gradient = CGGradient(colorSpace: CGColorSpaceCreateDeviceRGB(), colorComponents: components,
                                        locations: [0, 0.45, 1], count: 3) else { return }
        context.drawRadialGradient(gradient, startCenter: point, startRadius: 0, endCenter: point, endRadius: radius, options: [])
    }
}

final class GlassPointerLightView: NSView {
    private var geometry: GlassLightGeometry?
    private var sample: GlassLightSample?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(path: CGPath, sample: GlassLightSample?) {
        let changed = geometry?.path != path || self.sample != sample
        if geometry?.path != path { geometry = GlassLightGeometry(path: path) }
        self.sample = sample
        if changed { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(dirtyRect)
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        geometry?.draw(sample: sample, dark: dark, in: context)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

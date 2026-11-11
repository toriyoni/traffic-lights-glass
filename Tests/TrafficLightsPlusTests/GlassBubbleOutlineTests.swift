import CoreGraphics
import Testing
@testable import TrafficLightsPlus

private let bubbleWindow = CGRect(x: 200, y: 100, width: 600, height: 400)
private let bubbleNative: [WindowAction: CGRect] = [
    .close: CGRect(x: 212, y: 112, width: 14, height: 14),
    .minimize: CGRect(x: 232, y: 112, width: 14, height: 14),
    .zoom: CGRect(x: 252, y: 112, width: 14, height: 14)
]

@Test(arguments: [CGFloat(18), 23, 48])
func bubbleHasNoWaistsAndEnclosesTheLightsThroughoutThePointerSweep(size: CGFloat) throws {
    let resting = GlassGroupLayout.expandedFrames(nativeFrames: bubbleNative, controlSize: size, windowFrame: bubbleWindow)
    let left = try #require(resting[.close]), right = try #require(resting[.zoom])
    let host = try #require(GlassGroupLayout.presentationEnvelope(nativeFrames: bubbleNative, expandedFrames: resting, windowFrame: bubbleWindow))
    for index in 0...12 {
        for dy: CGFloat in [-12, 0, 12] {
            let pointer = CGPoint(x: left.midX + (right.midX - left.midX) * CGFloat(index) / 12, y: left.midY + dy)
            let weights = GlassGroupLayout.magnificationWeights(buttonFrames: resting, pointer: pointer)
            for progress: CGFloat in [0.2, 1] {
                let p = try #require(GlassGroupLayout.presentation(nativeFrames: bubbleNative, expandedFrames: resting, progress: progress, windowFrame: bubbleWindow, magnification: weights))
                let outline = GlassBubbleOutline(buttonFrames: p.buttonFrames, capsuleFrame: p.capsuleFrame,
                    padding: GlassGroupLayout.padding * progress, pointer: pointer, strength: weights.values.max()!)
                #expect(host.contains(outline.bounds))
                let points = sampledBoundary(outline.path)
                #expect(points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
                let turns = points.indices.map { index -> CGFloat in
                    let a = points[index], b = points[(index + 1) % points.count], c = points[(index + 2) % points.count]
                    return (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
                }
                // Any negative turn would be an inward neck, regardless of how
                // the curve was constructed. Sample the rendered quadratics.
                #expect(turns.allSatisfy { $0 >= -0.000001 })
                for frame in p.buttonFrames.values {
                    let radius = frame.width / 2 + GlassGroupLayout.padding * progress * 0.9
                    #expect((0..<32).allSatisfy { angle in
                        let theta = CGFloat(angle) * .pi / 16
                        return outline.path.contains(CGPoint(x: frame.midX + radius * cos(theta), y: frame.midY + radius * sin(theta)))
                    })
                }
            }
        }
    }
}

@Test func bubbleSwellsNearThePointerAndRespondsToItsVerticalPosition() throws {
    let resting = GlassGroupLayout.expandedFrames(nativeFrames: bubbleNative, controlSize: 23, windowFrame: bubbleWindow)
    let left = try #require(resting[.close])
    let pointer = CGPoint(x: left.midX, y: left.midY)
    let weights = GlassGroupLayout.magnificationWeights(buttonFrames: resting, pointer: pointer)
    let p = try #require(GlassGroupLayout.presentation(nativeFrames: bubbleNative, expandedFrames: resting, progress: 1, windowFrame: bubbleWindow, magnification: weights))
    let close = try #require(p.buttonFrames[.close]), zoom = try #require(p.buttonFrames[.zoom])
    func outline(dy: CGFloat) -> GlassBubbleOutline {
        GlassBubbleOutline(buttonFrames: p.buttonFrames, capsuleFrame: p.capsuleFrame, padding: 8,
            pointer: CGPoint(x: pointer.x, y: close.midY + dy), strength: 1)
    }
    let centered = outline(dy: 0)
    let nearHeight = verticalExtent(centered, at: close.midX)
    let farHeight = verticalExtent(centered, at: zoom.midX)
    #expect(nearHeight > farHeight + 6)
    let above = outline(dy: 8), below = outline(dy: -8)
    #expect(above.bounds.maxY > centered.bounds.maxY + 0.5)
    #expect(below.bounds.minY < centered.bounds.minY - 0.5)
    #expect(abs(above.bounds.maxY + below.bounds.minY - 2 * close.midY) < 0.001)
}

@Test func bubbleReturnsToAnExactCapsuleWithoutPressure() throws {
    let resting = GlassGroupLayout.expandedFrames(nativeFrames: bubbleNative, controlSize: 23, windowFrame: bubbleWindow)
    let capsule = try #require(GlassGroupLayout.capsuleFrame(buttonFrames: resting))
    for pointer in [CGPoint(x: capsule.midX, y: capsule.midY), CGPoint(x: CGFloat.nan, y: 0)] {
        let outline = GlassBubbleOutline(buttonFrames: resting, capsuleFrame: capsule, padding: 8, pointer: pointer, strength: 0)
        #expect(outline.bounds == capsule)
        #expect(outline.path.contains(CGPoint(x: capsule.midX, y: capsule.midY)))
        #expect(!outline.path.contains(capsule.origin))
    }
}

@Test func bubblePressureTracksWithoutOvershootAndReleasesItsTimer() {
    var motion = GlassMagnificationState()
    motion.advance(targetWeights: [.close: 1], elapsed: 1, reduceMotion: false, pointer: CGPoint(x: 10, y: 20))
    let target = CGPoint(x: 90, y: 40)
    motion.advance(targetWeights: [.zoom: 1], elapsed: 0, reduceMotion: false, pointer: target)
    #expect(motion.pointerLocation == CGPoint(x: 10, y: 20))
    #expect(motion.isAnimating)
    for _ in 0..<120 {
        let before = motion.pointerLocation!
        motion.advance(targetWeights: [.zoom: 1], elapsed: 1.0 / 120, reduceMotion: false, pointer: target)
        let after = motion.pointerLocation!
        #expect(after.x >= before.x && after.x <= target.x)
        #expect(after.y >= before.y && after.y <= target.y)
    }
    #expect(motion.pointerLocation == target && !motion.isAnimating)
    for _ in 0..<120 {
        motion.advance(targetWeights: [:], elapsed: 1.0 / 120, reduceMotion: false, pointer: CGPoint(x: 500, y: 500))
    }
    #expect(motion.pointerLocation == nil && !motion.isAnimating)
    motion.advance(targetWeights: [.minimize: 0.8], elapsed: 0, reduceMotion: true, pointer: target)
    #expect(motion.pointerLocation == target && !motion.isAnimating)
    motion.reset()
    #expect(motion.pointerLocation == nil && !motion.isAnimating)
}

private func verticalExtent(_ outline: GlassBubbleOutline, at x: CGFloat) -> CGFloat {
    let samples = stride(from: outline.bounds.minY, through: outline.bounds.maxY, by: 0.05)
        .filter { outline.path.contains(CGPoint(x: x, y: $0)) }
    return (samples.last ?? 0) - (samples.first ?? 0)
}

private func sampledBoundary(_ path: CGPath) -> [CGPoint] {
    var points: [CGPoint] = []
    var current = CGPoint.zero
    path.applyWithBlock { element in
        let e = element.pointee
        switch e.type {
        case .moveToPoint, .addLineToPoint:
            current = e.points[0]
            points.append(current)
        case .addQuadCurveToPoint:
            let start = current, control = e.points[0], end = e.points[1]
            for index in 1...8 {
                let t = CGFloat(index) / 8, u = 1 - t
                points.append(CGPoint(x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
                                      y: u * u * start.y + 2 * u * t * control.y + t * t * end.y))
            }
            current = end
        default: break
        }
    }
    if points.last == points.first { points.removeLast() }
    return points
}

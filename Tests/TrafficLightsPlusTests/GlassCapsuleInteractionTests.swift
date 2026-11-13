import AppKit
import Testing
@testable import TrafficLightsPlus

private let interactionBounds = CGRect(x: -800, y: -400, width: 1800, height: 1400)
private func restingLights(size: CGFloat = 23) -> [WindowAction: CGRect] {
    Dictionary(uniqueKeysWithValues: WindowAction.allCases.enumerated().map {
        ($0.element, CGRect(x: 100 + CGFloat($0.offset) * (size + GlassGroupLayout.gap), y: 100, width: size, height: size))
    })
}

@Test func outerLightsGrowOutwardsAndLeaveTheirNeighborsStill() throws {
    let resting = restingLights()
    let base = try #require(GlassGroupLayout.capsuleFrame(buttonFrames: resting))
    for selected in [WindowAction.close, .zoom] {
        let p = try #require(GlassGroupLayout.magnifiedPresentation(restingFrames: resting, weights: [selected: 1], windowFrame: interactionBounds))
        for action in WindowAction.allCases where action != selected {
            #expect(p.buttonFrames[action] == resting[action])
        }
        if selected == .close {
            #expect(p.capsuleFrame.minX < base.minX)
            #expect(p.buttonFrames[selected]!.maxX > resting[selected]!.maxX)
        } else {
            #expect(p.capsuleFrame.maxX > base.maxX)
            #expect(p.buttonFrames[selected]!.minX < resting[selected]!.minX)
        }
        let endCenter = selected == .close ? p.capsule.start : p.capsule.end
        #expect(endCenter == CGPoint(x: p.buttonFrames[selected]!.midX, y: p.buttonFrames[selected]!.midY))
        #expect(p.capsuleFrame.midY == base.midY)
        #expect(p.capsuleFrame.height < base.height + 7)
    }
}

@Test func middleLightPushesUnscaledNeighborsApartSymmetrically() throws {
    let resting = restingLights()
    let base = try #require(GlassGroupLayout.capsuleFrame(buttonFrames: resting))
    let p = try #require(GlassGroupLayout.magnifiedPresentation(restingFrames: resting, weights: [.minimize: 1], windowFrame: interactionBounds))
    let red = try #require(p.buttonFrames[.close]), yellow = try #require(p.buttonFrames[.minimize]), green = try #require(p.buttonFrames[.zoom])
    #expect(yellow.midX == resting[.minimize]?.midX)
    #expect(red.size == resting[.close]?.size && green.size == resting[.zoom]?.size)
    #expect(red.midX < resting[.close]!.midX && green.midX > resting[.zoom]!.midX)
    #expect(abs(resting[.close]!.midX - red.midX - (green.midX - resting[.zoom]!.midX)) < 0.000001)
    #expect(yellow.minX - red.maxX < GlassGroupLayout.gap)
    #expect(yellow.minX - red.maxX >= GlassGroupLayout.minimumHoverGap)
    #expect(p.capsuleFrame.midX == base.midX)
    #expect(p.capsuleFrame.minX < base.minX && p.capsuleFrame.maxX > base.maxX)
}

@Test func attractionIsSmallAndDoesNotScaleTheOtherLights() throws {
    let resting = restingLights()
    for selected in WindowAction.allCases {
        let weights: [WindowAction: CGFloat] = [selected: 1]
        let target = GlassGroupLayout.magnifiedFrames(restingFrames: resting, weights: weights, windowFrame: interactionBounds)
        let frame = try #require(target[selected])
        for delta in [CGPoint(x: -8, y: -6), CGPoint(x: 8, y: 6)] {
            let offsets = GlassGroupLayout.magneticOffsets(buttonFrames: target, weights: weights,
                pointer: CGPoint(x: frame.midX + delta.x, y: frame.midY + delta.y))
            let offset = try #require(offsets[selected])
            #expect(offsets.count == 1)
            #expect(offset.x * delta.x > 0 && offset.y * delta.y > 0)
            #expect(hypot(offset.x, offset.y) <= GlassGroupLayout.maximumAttraction)
            let p = try #require(GlassGroupLayout.magnifiedPresentation(restingFrames: resting, weights: weights,
                windowFrame: interactionBounds, attractions: offsets))
            for action in WindowAction.allCases {
                #expect(p.buttonFrames[action]?.size == target[action]?.size)
                if action != selected { #expect(p.buttonFrames[action] == target[action]) }
            }
            let base = try #require(GlassGroupLayout.magnifiedPresentation(restingFrames: resting, weights: weights, windowFrame: interactionBounds))
            #expect(p.capsule.radius == base.capsule.radius)
            if selected == .minimize { #expect(p.capsuleFrame == base.capsuleFrame) }
        }
    }
}

@Test(arguments: [CGFloat(18), 23, 48])
func roundCapsuleEnclosesEveryLightDuringStateChanges(size: CGFloat) throws {
    let resting = restingLights(size: size)
    let envelope = try #require(GlassGroupLayout.presentationEnvelope(nativeFrames: resting, expandedFrames: resting, windowFrame: interactionBounds))
    for source in WindowAction.allCases {
        for target in WindowAction.allCases {
            for t: CGFloat in [0, 0.1, 0.5, 0.9, 1] {
                let weights: [WindowAction: CGFloat] = source == target ? [target: t] : [source: 1 - t, target: t]
                for dy: CGFloat in [-1.4, 0, 1.4] {
                    let offsets: [WindowAction: CGPoint] = [target: CGPoint(x: 1.4 * t, y: dy * t)]
                    let p = try #require(GlassGroupLayout.presentation(nativeFrames: resting, expandedFrames: resting,
                        progress: 1, windowFrame: interactionBounds, magnification: weights, attractions: offsets))
                    let path = p.capsule.path
                    #expect(envelope.contains(p.capsuleFrame))
                    for frame in p.buttonFrames.values {
                        for angle in 0..<64 {
                            let theta = CGFloat(angle) * .pi / 32
                            let r = frame.width / 2 + 2
                            #expect(path.contains(CGPoint(x: frame.midX + r * cos(theta), y: frame.midY + r * sin(theta))))
                        }
                    }
                }
            }
        }
    }
}

@Test func aStationaryPointerDoesNotLoseItsLightWhileItExpands() throws {
    let resting = restingLights()
    for selected in WindowAction.allCases {
        let origin = try #require(resting[selected])
        for angle in 0..<12 {
            let theta = CGFloat(angle) * .pi / 6
            let pointer = CGPoint(x: origin.midX + origin.width * 0.49 * cos(theta),
                                  y: origin.midY + origin.height * 0.49 * sin(theta))
            var frames = resting
            var motion = GlassMagnificationState()
            for _ in 0..<90 {
                let weights = GlassGroupLayout.magnificationWeights(buttonFrames: frames, pointer: pointer)
                #expect(weights[selected] == 1)
                let target = GlassGroupLayout.magnifiedFrames(restingFrames: resting, weights: weights, windowFrame: interactionBounds)
                let offsets = GlassGroupLayout.magneticOffsets(buttonFrames: target, weights: weights, pointer: pointer)
                motion.advance(targetWeights: weights, elapsed: 1.0 / 120, reduceMotion: false, targetAttractions: offsets)
                frames = GlassGroupLayout.magnifiedFrames(restingFrames: resting, weights: motion.weights,
                    windowFrame: interactionBounds, attractions: motion.attractions)
            }
            #expect(motion.weights[selected] == 1 && !motion.isAnimating)
        }
    }
}

@Test func magneticMovementEasesWithoutOvershootAndReleasesItsTimer() {
    var motion = GlassMagnificationState()
    let target = CGPoint(x: 1.5, y: -1)
    for _ in 0..<100 {
        let before = motion.attractions[.zoom] ?? .zero
        motion.advance(targetWeights: [.zoom: 1], elapsed: 1.0 / 120, reduceMotion: false, targetAttractions: [.zoom: target])
        let after = motion.attractions[.zoom]!
        #expect(after.x >= before.x && after.x <= target.x)
        #expect(after.y <= before.y && after.y >= target.y)
    }
    #expect(motion.attractions[.zoom] == target && !motion.isAnimating)
    for _ in 0..<100 { motion.advance(targetWeights: [:], elapsed: 1.0 / 120, reduceMotion: false) }
    #expect(motion.attractions.values.allSatisfy { $0 == .zero } && !motion.isAnimating)
    motion.advance(targetWeights: [.minimize: 1], elapsed: 0, reduceMotion: true, targetAttractions: [.minimize: target])
    #expect(motion.attractions[.minimize] == target && !motion.isAnimating)
    motion.reset()
    #expect(motion.attractions.isEmpty && !motion.isAnimating)
}

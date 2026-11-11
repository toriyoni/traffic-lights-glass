import AppKit
import Testing
@testable import TrafficLightsPlus

private let magnificationWindow = CGRect(x: 250.25, y: 180.5, width: 600, height: 400)
private let magnificationNative: [WindowAction: CGRect] = [
    .close: CGRect(x: 262.25, y: 192.5, width: 14, height: 14),
    .minimize: CGRect(x: 282.25, y: 192.5, width: 14, height: 14),
    .zoom: CGRect(x: 302.25, y: 192.5, width: 14, height: 14)
]

@Test func glassMagnificationUsesDistanceWithASmoothFiniteInfluence() throws {
    let frames = GlassGroupLayout.expandedFrames(nativeFrames: magnificationNative, controlSize: 23, windowFrame: magnificationWindow)
    let center = try #require(frames[.minimize])
    let pointer = CGPoint(x: center.midX, y: center.midY)
    let weights = GlassGroupLayout.magnificationWeights(buttonFrames: frames, pointer: pointer)
    #expect(weights[.minimize] == 1)
    #expect(try #require(weights[.close]) < 0.3)
    #expect(abs(try #require(weights[.close]) - #require(weights[.zoom])) < 0.000001)

    let radius = (center.width + GlassGroupLayout.gap) * GlassGroupLayout.influenceRadiusInPitches
    let halfway = GlassGroupLayout.magnificationWeights(buttonFrames: frames, pointer: CGPoint(x: pointer.x, y: pointer.y + radius / 2))
    let edge = GlassGroupLayout.magnificationWeights(buttonFrames: frames, pointer: CGPoint(x: pointer.x, y: pointer.y + radius))
    let justInside = GlassGroupLayout.magnificationWeights(buttonFrames: frames, pointer: CGPoint(x: pointer.x, y: pointer.y + radius - 0.01))
    #expect(abs(try #require(halfway[.minimize]) - 0.5) < 0.000001)
    #expect(edge[.minimize] == 0)
    #expect(try #require(justInside[.minimize]) < 0.000001)
    #expect(GlassGroupLayout.magnificationWeights(buttonFrames: frames, pointer: CGPoint(x: CGFloat.nan, y: 0)).isEmpty)
}

@Test func movingBetweenLightsDoesNotSwitchSizesAbruptly() throws {
    let frames = GlassGroupLayout.expandedFrames(nativeFrames: magnificationNative, controlSize: 28, windowFrame: magnificationWindow)
    let close = try #require(frames[.close])
    let green = try #require(frames[.zoom])
    var previous = GlassGroupLayout.magnificationWeights(buttonFrames: frames, pointer: CGPoint(x: close.midX - 60, y: close.midY))
    for x in stride(from: close.midX - 60, through: green.midX + 60, by: 0.25) {
        let current = GlassGroupLayout.magnificationWeights(buttonFrames: frames, pointer: CGPoint(x: x, y: close.midY))
        for action in WindowAction.allCases {
            #expect(abs((current[action] ?? 0) - (previous[action] ?? 0)) < 0.01)
        }
        previous = current
    }
}

@Test(arguments: [CGFloat(18), 23, 48])
func magnifiedButtonsKeepTheirGapsAndStayInsideAStationaryEnvelope(size: CGFloat) throws {
    for dx: CGFloat in [0, 500] {
        let native = magnificationNative.mapValues { $0.offsetBy(dx: dx, dy: 0) }
        let resting = GlassGroupLayout.expandedFrames(nativeFrames: native, controlSize: size, windowFrame: magnificationWindow)
        let envelope = try #require(GlassGroupLayout.presentationEnvelope(nativeFrames: native, expandedFrames: resting, windowFrame: magnificationWindow))
        for a: CGFloat in [0, 0.5, 1] {
            for b: CGFloat in [0, 0.5, 1] {
                for c: CGFloat in [0, 0.5, 1] {
                    let weights: [WindowAction: CGFloat] = [.close: a, .minimize: b, .zoom: c]
                    let frames = GlassGroupLayout.magnifiedFrames(restingFrames: resting, weights: weights, windowFrame: magnificationWindow)
                    #expect(abs(try #require(frames[.minimize]).minX - #require(frames[.close]).maxX - GlassGroupLayout.gap) < 0.000001)
                    #expect(abs(try #require(frames[.zoom]).minX - #require(frames[.minimize]).maxX - GlassGroupLayout.gap) < 0.000001)
                    for progress: CGFloat in [0, 0.2, 0.65, 0.99, 1] {
                        let p = try #require(GlassGroupLayout.presentation(nativeFrames: native, expandedFrames: resting, progress: progress, windowFrame: magnificationWindow, magnification: weights))
                        #expect(magnificationWindow.contains(p.capsuleFrame))
                        #expect(envelope.insetBy(dx: -0.000001, dy: -0.000001).contains(p.capsuleFrame))
                    }
                }
            }
        }
    }
}

@Test func magnificationHandlesMissingButtonsAndInvalidInput() throws {
    let native = magnificationNative.filter { $0.key != .minimize }
    let resting = GlassGroupLayout.expandedFrames(nativeFrames: native, controlSize: 28, windowFrame: magnificationWindow)
    let frames = GlassGroupLayout.magnifiedFrames(restingFrames: resting, weights: [.close: .nan, .zoom: 50], windowFrame: magnificationWindow)
    #expect(frames[.minimize] == nil)
    #expect(frames[.close]?.width == 28)
    #expect(frames[.zoom]?.width == 28 * GlassGroupLayout.maximumMagnification)
    #expect(GlassGroupLayout.magnifiedFrames(restingFrames: [:], weights: [:], windowFrame: magnificationWindow).isEmpty)
}

@Test func magnificationEasesOutInBothDirectionsAndFinishesExactly() {
    var motion = GlassMagnificationState()
    for target: CGFloat in [1, 0] {
        var previousStep = CGFloat.infinity
        for _ in 0..<90 {
            let before = motion.weights[.close] ?? 0
            motion.advance(targetWeights: [.close: target], elapsed: 1.0 / 120, reduceMotion: false)
            let after = motion.weights[.close] ?? 0
            #expect(after >= min(before, target) && after <= max(before, target))
            let step = abs(after - before)
            // Only the final sub-pixel snap can be slightly larger than the
            // preceding step; it is far smaller than a display pixel.
            #expect(step <= previousStep + 0.0001)
            previousStep = step
        }
        #expect(motion.weights[.close] == target)
        #expect(!motion.isAnimating)
    }
    #expect(!motion.isMagnified)
}

@Test func magnificationRetargetsWithoutJumpingOrContinuingAwayFromThePointer() {
    var motion = GlassMagnificationState()
    motion.advance(targetWeights: [.close: 1], elapsed: 0.05, reduceMotion: false)
    let first = motion.weights[.close]!
    motion.advance(targetWeights: [.zoom: 1], elapsed: 0, reduceMotion: false)
    #expect(motion.weights[.close] == first)
    #expect(motion.isAnimating)
    motion.advance(targetWeights: [.zoom: 1], elapsed: 1.0 / 60, reduceMotion: false)
    #expect(motion.weights[.close]! < first)
    #expect(motion.weights[.zoom]! > 0)
    let second = motion.weights[.close]!
    motion.advance(targetWeights: [.close: 1], elapsed: 1.0 / 60, reduceMotion: false)
    #expect(motion.weights[.close]! > second)
}

@Test func magnificationIsFrameRateIndependentAndHonorsReducedMotion() {
    var reference = GlassMagnificationState()
    reference.advance(targetWeights: [.minimize: 1], elapsed: 0.2, reduceMotion: false)
    for rate in [30, 60, 120] {
        var motion = GlassMagnificationState()
        for _ in 0..<(rate / 5) {
            motion.advance(targetWeights: [.minimize: 1], elapsed: 1.0 / Double(rate), reduceMotion: false)
        }
        #expect(abs(motion.weights[.minimize]! - reference.weights[.minimize]!) < 0.000001)
    }
    reference.advance(targetWeights: [.zoom: 0.75], elapsed: 0, reduceMotion: true)
    #expect(reference.weights[.zoom] == 0.75)
    #expect(reference.weights[.minimize] == 0)
    #expect(!reference.isAnimating)
    reference.reset()
    #expect(!reference.isAnimating && !reference.isMagnified)
}

@MainActor
@Test func magnifiedNativeGlassKeepsTheWindowStillAndHitTargetsAligned() throws {
    let resting = GlassGroupLayout.expandedFrames(nativeFrames: magnificationNative, controlSize: 23, windowFrame: magnificationWindow)
    let host = try #require(GlassGroupLayout.presentationEnvelope(nativeFrames: magnificationNative, expandedFrames: resting, windowFrame: magnificationWindow))
    let panel = GlassGroupPanel()
    panel.ignoresMouseEvents = true
    defer { panel.orderOut(nil) }
    var fixedFrame: CGRect?
    for focused in WindowAction.allCases {
        for weight: CGFloat in [0, 0.1, 0.5, 0.9, 1, 0.8, 0.4, 0.1, 0] {
            let p = try #require(GlassGroupLayout.presentation(nativeFrames: magnificationNative, expandedFrames: resting, progress: 1, windowFrame: magnificationWindow, magnification: [focused: weight]))
            let focusedFrame = try #require(resting[focused])
            panel.present(buttonFrames: p.buttonFrames, nativeButtonFrames: [], capsuleFrame: p.capsuleFrame,
                progress: 1, containerFrame: host,
                pointer: CGPoint(x: focusedFrame.midX, y: focusedFrame.midY + 6), magnification: weight)
            panel.contentView?.layoutSubtreeIfNeeded()
            if let fixedFrame { #expect(panel.frame == fixedFrame) }
            fixedFrame = panel.frame
            for (action, view) in panel.buttonViews {
                let screen = panel.convertToScreen(view.convert(view.bounds, to: nil))
                let expected = try #require(p.buttonFrames[action])
                #expect(abs(screen.midX - expected.midX) < 0.000001)
                #expect(abs(screen.midY - expected.midY) < 0.000001)
                #expect(abs(screen.width - expected.width) < 0.000001)
                let hit = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: panel.contentView)
                #expect(panel.contentView?.hitTest(hit) === view)
            }
            #expect(!panel.canBecomeKey && !panel.canBecomeMain)
        }
    }
}

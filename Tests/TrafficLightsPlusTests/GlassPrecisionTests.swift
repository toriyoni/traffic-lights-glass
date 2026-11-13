import AppKit
import Testing
@testable import TrafficLightsPlus

private func precisionFrames(size: CGFloat = 23, origin: CGPoint = CGPoint(x: 12, y: 12)) -> [WindowAction: CGRect] {
    Dictionary(uniqueKeysWithValues: WindowAction.allCases.enumerated().map {
        ($0.element, CGRect(x: origin.x + CGFloat($0.offset) * (size + GlassGroupLayout.gap),
                            y: origin.y, width: size, height: size))
    })
}

@Test(arguments: [CGFloat(18), 23, 48])
func displayClearanceIsReservedBeforeEitherOuterLightGrows(size: CGFloat) throws {
    let screen = CGRect(x: 0, y: 0, width: 800, height: 600)
    for origin in [CGPoint(x: 12, y: 12), CGPoint(x: 640, y: 12)] {
        let resting = GlassGroupLayout.reservingHoverClearance(restingFrames: precisionFrames(size: size, origin: origin), displayFrame: screen)
        for selected in [WindowAction.close, .zoom] {
            let p = try #require(GlassGroupLayout.magnifiedPresentation(restingFrames: resting, weights: [selected: 1], windowFrame: screen))
            for other in WindowAction.allCases where other != selected {
                #expect(abs(p.buttonFrames[other]!.midX - resting[other]!.midX) < 0.000001)
                #expect(abs(p.buttonFrames[other]!.midY - resting[other]!.midY) < 0.000001)
            }
            #expect(screen.contains(p.capsuleFrame))
        }
        #expect(GlassGroupLayout.reservingHoverClearance(restingFrames: resting, displayFrame: screen) == resting)
    }
}

@Test(arguments: [CGFloat(18), 23, 48])
func circlingALightNeverMovesItsNeighborsEvenAtDisplayEdges(size: CGFloat) throws {
    let screen = CGRect(x: -600, y: -200, width: 1000, height: 700)
    for origin in [CGPoint(x: -588, y: -188), CGPoint(x: 200, y: -188), CGPoint(x: -588, y: 420)] {
        let resting = precisionFrames(size: size, origin: origin)
        for selected in WindowAction.allCases {
            let weights: [WindowAction: CGFloat] = [selected: 1]
            let base = try #require(GlassGroupLayout.magnifiedPresentation(restingFrames: resting, weights: weights, windowFrame: screen))
            for i in 0..<72 {
                let theta = CGFloat(i) * .pi / 36
                let p = try #require(GlassGroupLayout.magnifiedPresentation(restingFrames: resting, weights: weights, windowFrame: screen,
                    attractions: [selected: CGPoint(x: 2 * cos(theta), y: 2 * sin(theta))]))
                for other in WindowAction.allCases where other != selected {
                    #expect(p.buttonFrames[other] == base.buttonFrames[other])
                }
                #expect(p.capsule.radius == base.capsule.radius)
                if selected != .minimize {
                    #expect(p.capsule.start == CGPoint(x: p.buttonFrames[.close]!.midX, y: p.buttonFrames[.close]!.midY))
                    #expect(p.capsule.end == CGPoint(x: p.buttonFrames[.zoom]!.midX, y: p.buttonFrames[.zoom]!.midY))
                } else {
                    #expect(abs(p.capsule.start.y - p.buttonFrames[.close]!.midY) <= 0.600001)
                    #expect(abs(p.capsule.end.y - p.buttonFrames[.zoom]!.midY) <= 0.600001)
                }
                #expect(screen.contains(p.capsuleFrame))
            }
        }
    }
}

@Test(arguments: [CGFloat(18), 23, 48])
func horizontalSweepsCrossEveryLightWithoutAnEmptyTargetOrReversal(size: CGFloat) throws {
    let resting = precisionFrames(size: size, origin: CGPoint(x: 100, y: 100))
    let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
    for direction in [-1, 1] {
        for dy: CGFloat in [-size * 0.3, 0, size * 0.3] {
            var shown = resting
            var motion = GlassMagnificationState()
            var last = direction > 0 ? WindowAction.close.rawValue : WindowAction.zoom.rawValue
            for step in 0...240 {
                let t = CGFloat(direction > 0 ? step : 240 - step) / 240
                let pointer = CGPoint(x: resting[.close]!.midX + (resting[.zoom]!.midX - resting[.close]!.midX) * t,
                                      y: resting[.close]!.midY + dy)
                let target = GlassGroupLayout.magnificationWeights(buttonFrames: shown, pointer: pointer)
                let selected = try #require(target.first(where: { $0.value == 1 })?.key)
                #expect(target.values.filter { $0 > 0 }.count == 1)
                #expect(direction * (selected.rawValue - last) >= 0)
                last = selected.rawValue
                let goal = GlassGroupLayout.magnifiedFrames(restingFrames: resting, weights: target, windowFrame: bounds)
                let offsets = GlassGroupLayout.magneticOffsets(buttonFrames: goal, weights: target, pointer: pointer)
                motion.advance(targetWeights: target, elapsed: 1.0 / 120, reduceMotion: false, targetAttractions: offsets)
                shown = GlassGroupLayout.magnifiedFrames(restingFrames: resting, weights: motion.weights, windowFrame: bounds, attractions: motion.attractions)
            }
        }
    }
}

@MainActor
@Test func visualGapsRouteClicksToOneLightAndRejectCrossButtonReleases() throws {
    let frames = precisionFrames(origin: CGPoint(x: 500, y: 500))
    let panel = GlassGroupPanel()
    panel.ignoresMouseEvents = true
    defer { panel.orderOut(nil) }
    panel.present(buttonFrames: frames, nativeButtonFrames: [], capsuleFrame: GlassGroupLayout.capsuleFrame(buttonFrames: frames)!, progress: 1)
    var fired: [WindowAction] = []
    panel.buttonViews.values.forEach { $0.actionHandler = { fired.append($0) } }
    let content = try #require(panel.contentView)
    func event(_ type: NSEvent.EventType, screenPoint: CGPoint) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: panel.convertPoint(fromScreen: screenPoint), modifierFlags: [],
            timestamp: 0, windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    for (left, right) in [(WindowAction.close, WindowAction.minimize), (.minimize, .zoom)] {
        let a = frames[left]!, b = frames[right]!
        for fraction: CGFloat in [0.25, 0.75] {
            let point = CGPoint(x: a.maxX + (b.minX - a.maxX) * fraction, y: a.midY)
            let intended = fraction < 0.5 ? left : right
            let local = content.convert(panel.convertPoint(fromScreen: point), from: nil)
            let hit = try #require(content.hitTest(local) as? OverlayButtonView)
            #expect(hit === panel.buttonViews[intended])
            #expect(!hit.bounds.contains(hit.convert(event(.leftMouseDown, screenPoint: point).locationInWindow, from: nil)))
            let count = fired.count
            hit.mouseDown(with: event(.leftMouseDown, screenPoint: point))
            hit.mouseUp(with: event(.leftMouseUp, screenPoint: point))
            hit.mouseUp(with: event(.leftMouseUp, screenPoint: point))
            #expect(fired.count == count + 1 && fired.last == intended)
        }
    }
    let red = panel.buttonViews[.close]!
    let count = fired.count
    red.mouseDown(with: event(.leftMouseDown, screenPoint: CGPoint(x: frames[.close]!.midX, y: frames[.close]!.midY)))
    red.mouseUp(with: event(.leftMouseUp, screenPoint: CGPoint(x: frames[.zoom]!.midX, y: frames[.zoom]!.midY)))
    #expect(fired.count == count)
}

@MainActor
@Test func circlingKeepsNativeMaterialCanvasAndInactiveViewsFixed() throws {
    let resting = precisionFrames(origin: CGPoint(x: 500.25, y: 400.75))
    let bounds = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let host = try #require(GlassGroupLayout.presentationEnvelope(nativeFrames: resting, expandedFrames: resting, windowFrame: bounds))
    let panel = GlassGroupPanel()
    panel.ignoresMouseEvents = true
    defer { panel.orderOut(nil) }
    var canvas: CGRect?
    var unchangedViews: [WindowAction: CGRect] = [:]
    for i in 0..<48 {
        let theta = CGFloat(i) * .pi / 24
        let p = try #require(GlassGroupLayout.magnifiedPresentation(restingFrames: resting, weights: [.zoom: 1], windowFrame: bounds,
            attractions: [.zoom: CGPoint(x: 2 * cos(theta), y: 2 * sin(theta))]))
        panel.present(buttonFrames: p.buttonFrames, nativeButtonFrames: [], capsuleFrame: p.capsuleFrame,
            progress: 1, containerFrame: host, capsulePath: p.capsule.path)
        panel.contentView?.layoutSubtreeIfNeeded()
        if let canvas { #expect(panel.frame == canvas) }
        canvas = panel.frame
        #expect(panel.frame.insetBy(dx: 15, dy: 15).contains(p.capsuleFrame))
        let content = try #require(panel.contentView)
        #expect(content.subviews.allSatisfy { $0.frame == content.bounds })
        for action in [WindowAction.close, .minimize] {
            let view = panel.buttonViews[action]!
            if let previous = unchangedViews[action] { #expect(view.frame == previous) }
            unchangedViews[action] = view.frame
            let actual = panel.convertToScreen(view.convert(view.bounds, to: nil))
            #expect(actual == p.buttonFrames[action])
        }
    }
}

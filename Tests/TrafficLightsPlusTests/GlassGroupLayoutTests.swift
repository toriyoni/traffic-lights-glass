import CoreGraphics
import Testing
@testable import TrafficLightsPlus

private let glassNativeFrames: [WindowAction: CGRect] = [
    .close: CGRect(x: 12, y: 12, width: 14, height: 14),
    .minimize: CGRect(x: 32, y: 12, width: 14, height: 14),
    .zoom: CGRect(x: 52, y: 12, width: 14, height: 14)
]

@Test func glassControlsHaveDistinctTargetsAndKeepCapsuleInsideWindow() throws {
    let window = CGRect(x: 0, y: 0, width: 800, height: 600)
    let frames = GlassGroupLayout.expandedFrames(
        nativeFrames: glassNativeFrames, controlSize: 28, windowFrame: window
    )
    let close = try #require(frames[.close])
    let minimize = try #require(frames[.minimize])
    let zoom = try #require(frames[.zoom])
    let capsule = try #require(GlassGroupLayout.capsuleFrame(buttonFrames: frames))
    #expect(close.width == 28)
    #expect(minimize.minX - close.maxX == GlassGroupLayout.gap)
    #expect(zoom.minX - minimize.maxX == GlassGroupLayout.gap)
    #expect(!close.intersects(minimize))
    #expect(!minimize.intersects(zoom))
    #expect(capsule.minX >= window.minX + 4)
    #expect(capsule.minY >= window.minY + 4)
    #expect(window.contains(capsule))
}

@Test func glassControlsClampAtTheRightEdgeAndSupportNegativeScreenCoordinates() throws {
    let window = CGRect(x: -800, y: -200, width: 300, height: 200)
    let native: [WindowAction: CGRect] = [
        .close: CGRect(x: -560, y: -188, width: 14, height: 14),
        .minimize: CGRect(x: -540, y: -188, width: 14, height: 14),
        .zoom: CGRect(x: -520, y: -188, width: 14, height: 14)
    ]
    let frames = GlassGroupLayout.expandedFrames(nativeFrames: native, controlSize: 48, windowFrame: window)
    let capsule = try #require(GlassGroupLayout.capsuleFrame(buttonFrames: frames))
    #expect(capsule.maxX == window.maxX - 4)
    #expect(window.contains(capsule))
}

@Test func glassLayoutCompactsMissingButtonsWithoutInventingAnAction() throws {
    let native: [WindowAction: CGRect] = [.close: glassNativeFrames[.close]!, .zoom: glassNativeFrames[.zoom]!]
    let frames = GlassGroupLayout.expandedFrames(
        nativeFrames: native,
        controlSize: 28,
        windowFrame: CGRect(x: 0, y: 0, width: 800, height: 600)
    )
    let close = try #require(frames[.close])
    let zoom = try #require(frames[.zoom])
    #expect(frames[.minimize] == nil)
    #expect(zoom.minX - close.maxX == GlassGroupLayout.gap)
    #expect(GlassGroupLayout.capsuleFrame(buttonFrames: [:]) == nil)
}

@Test func glassLayoutNeverShrinksLargeNativeButtonsOrOverlapsInNarrowWindows() throws {
    let native: [WindowAction: CGRect] = [
        .close: CGRect(x: 12, y: 12, width: 32, height: 32),
        .minimize: CGRect(x: 50, y: 12, width: 32, height: 32)
    ]
    let frames = GlassGroupLayout.expandedFrames(
        nativeFrames: native,
        controlSize: 18,
        windowFrame: CGRect(x: 0, y: 0, width: 80, height: 80)
    )
    let close = try #require(frames[.close])
    let minimize = try #require(frames[.minimize])
    #expect(close.width == 32)
    #expect(minimize.minX - close.maxX == GlassGroupLayout.gap)
}

@Test func glassGroupStartsNearNativeControlsAndRetainsTheWholeExpandedCapsule() {
    var state = GlassGroupRevealState()
    let native = CGRect(x: 10, y: 10, width: 54, height: 14)
    let expanded = CGRect(x: 8, y: 8, width: 116, height: 44)
    let visibleBeforeApproach = state.desiredVisibility(
        pointer: CGPoint(x: 100, y: 24), nativeRegion: native, expandedRegion: expanded, now: 0
    )
    #expect(!visibleBeforeApproach)
    let visibleAtNativeButton = state.desiredVisibility(
        pointer: CGPoint(x: 15, y: 15), nativeRegion: native, expandedRegion: expanded, now: 1
    )
    #expect(visibleAtNativeButton)
    let visibleInsideCapsule = state.desiredVisibility(
        pointer: CGPoint(x: 100, y: 24), nativeRegion: native, expandedRegion: expanded, now: 1.1
    )
    #expect(visibleInsideCapsule)
    #expect(state.isEngaged)
    #expect(!state.isWaitingToCollapse)
}

@Test func glassExitGraceIsCancelledByReentryAndRestartsOnNextExit() {
    var state = GlassGroupRevealState()
    let region = CGRect(x: 0, y: 0, width: 100, height: 50)
    let inside = CGPoint(x: 20, y: 20)
    let outside = CGPoint(x: 200, y: 200)
    let visibleOnEntry = state.desiredVisibility(
        pointer: inside, nativeRegion: region, expandedRegion: region, now: 1
    )
    #expect(visibleOnEntry)
    let visibleOnFirstExit = state.desiredVisibility(
        pointer: outside, nativeRegion: region, expandedRegion: region, now: 2
    )
    #expect(visibleOnFirstExit)
    #expect(state.isWaitingToCollapse)
    let visibleOnReentry = state.desiredVisibility(
        pointer: inside, nativeRegion: region, expandedRegion: region, now: 2.05
    )
    #expect(visibleOnReentry)
    #expect(!state.isWaitingToCollapse)
    let visibleOnSecondExit = state.desiredVisibility(
        pointer: outside, nativeRegion: region, expandedRegion: region, now: 3
    )
    #expect(visibleOnSecondExit)
    let visibleDuringGracePeriod = state.desiredVisibility(
        pointer: outside, nativeRegion: region, expandedRegion: region, now: 3.09
    )
    #expect(visibleDuringGracePeriod)
    let visibleAfterGracePeriod = state.desiredVisibility(
        pointer: outside, nativeRegion: region, expandedRegion: region, now: 3.11
    )
    #expect(!visibleAfterGracePeriod)
    #expect(!state.isEngaged)
    #expect(!state.isWaitingToCollapse)
}

@Test func glassSpringPopsPastRestingSizeThenSettlesAndStops() {
    var state = GlassGroupRevealState()
    state.advance(visible: true, elapsed: 0, reduceMotion: false)
    #expect(state.isAnimating)
    #expect(state.progress == 0)
    var peak: CGFloat = 0
    var crossedTargetWhileMoving = false
    for _ in 0..<60 {
        state.advance(visible: true, elapsed: 1.0 / 60, reduceMotion: false)
        peak = max(peak, state.progress)
        if state.progress > 1, state.velocity > 0 {
            crossedTargetWhileMoving = true
            #expect(state.isAnimating)
        }
    }
    #expect(crossedTargetWhileMoving)
    #expect(peak > 1.12 && peak < 1.20)
    #expect(state.progress == 1)
    #expect(state.velocity == 0)
    #expect(!state.isAnimating)

    var previous = state.progress
    for _ in 0..<60 {
        state.advance(visible: false, elapsed: 1.0 / 60, reduceMotion: false)
        #expect(state.progress <= previous)
        #expect(state.progress >= 0)
        previous = state.progress
    }
    #expect(state.progress == 0)
    #expect(!state.isAnimating)
}

@Test func glassSpringRetargetingPreservesPositionAndMomentum() {
    var state = GlassGroupRevealState()
    state.advance(visible: true, elapsed: 0.07, reduceMotion: false)
    let opening = state
    #expect(opening.velocity > 0)
    state.advance(visible: false, elapsed: 0, reduceMotion: false)
    #expect(state.progress == opening.progress)
    #expect(state.velocity == opening.velocity)
    state.advance(visible: false, elapsed: 0.08, reduceMotion: false)
    let closing = state
    #expect(closing.velocity < 0)
    state.advance(visible: true, elapsed: 0, reduceMotion: false)
    #expect(state.progress == closing.progress)
    #expect(state.velocity == closing.velocity)
    state.advance(visible: true, elapsed: 1.0 / 240, reduceMotion: false)
    #expect(abs(state.progress - closing.progress) < 0.05)
    #expect(state.progress < closing.progress)
    for _ in 0..<60 { state.advance(visible: true, elapsed: 1.0 / 60, reduceMotion: false) }
    #expect(state.progress == 1)
    #expect(!state.isAnimating)
}

@Test func glassSpringProducesTheSameMotionAcrossFrameRatesAndDroppedFrames() {
    var uninterrupted = GlassGroupRevealState()
    uninterrupted.advance(visible: true, elapsed: 0.2, reduceMotion: false)
    for rate in [30, 60, 120] {
        var state = GlassGroupRevealState()
        for _ in 0..<(rate / 5) {
            state.advance(visible: true, elapsed: 1.0 / Double(rate), reduceMotion: false)
        }
        #expect(abs(state.progress - uninterrupted.progress) < 0.0000001)
        #expect(abs(state.velocity - uninterrupted.velocity) < 0.0000001)
    }
    var interrupted = GlassGroupRevealState()
    for elapsed in [0.016, 0.044, 0.09, 0.05] {
        interrupted.advance(visible: true, elapsed: elapsed, reduceMotion: false)
    }
    #expect(abs(interrupted.progress - uninterrupted.progress) < 0.0000001)
    #expect(abs(interrupted.velocity - uninterrupted.velocity) < 0.0000001)
}

@Test func rapidGlassSpringReversalsStayBoundedAndCanFinishClosing() {
    var state = GlassGroupRevealState()
    for frame in 0..<240 {
        state.advance(visible: (frame / 5) % 2 == 0, elapsed: 1.0 / 60, reduceMotion: false)
        #expect(state.progress.isFinite && state.velocity.isFinite)
        #expect(state.progress >= 0 && state.progress <= GlassGroupRevealState.maximumProgress)
    }
    for _ in 0..<60 { state.advance(visible: false, elapsed: 1.0 / 60, reduceMotion: false) }
    #expect(state.progress == 0)
    #expect(state.velocity == 0)
    #expect(!state.isAnimating)
}

@Test func glassSpringRespectsReducedMotionAndClearsMomentumOnReset() {
    var state = GlassGroupRevealState()
    state.advance(visible: true, elapsed: 0.12, reduceMotion: false)
    state.advance(visible: true, elapsed: 0, reduceMotion: true)
    #expect(state.progress == 1)
    #expect(state.velocity == 0)
    #expect(!state.isAnimating)
    state.advance(visible: false, elapsed: 0, reduceMotion: true)
    #expect(state.progress == 0)
    #expect(!state.isAnimating)
    state.advance(visible: true, elapsed: 0.07, reduceMotion: false)
    state.advance(visible: false, elapsed: 0, reduceMotion: false, alwaysVisible: true)
    #expect(state.progress == 1)
    #expect(state.velocity == 0)
    #expect(!state.isAnimating)
    state.advance(visible: false, elapsed: 0.07, reduceMotion: false)
    state.reset()
    #expect(state.progress == 0)
    #expect(state.velocity == 0)
    #expect(!state.isAnimating)
    #expect(!state.isEngaged)
}

@Test func invalidElapsedTimeDoesNotCorruptTheGlassSpring() {
    var state = GlassGroupRevealState()
    state.advance(visible: true, elapsed: 0.07, reduceMotion: false)
    let previous = state
    for elapsed in [Double.nan, Double.infinity, -0.5] {
        state.advance(visible: true, elapsed: elapsed, reduceMotion: false)
        #expect(state.progress == previous.progress)
        #expect(state.velocity == previous.velocity)
    }
    state.advance(visible: false, elapsed: 100, reduceMotion: false)
    #expect(state.progress == 0)
    #expect(!state.isAnimating)
}

@Test(arguments: [CGFloat(18), 28, 48])
func glassSpringGeometryKeepsOvershootAndDistinctButtonsInsideWindow(size: CGFloat) throws {
    let window = CGRect(x: -800, y: -200, width: 800, height: 600)
    for atRightEdge in [false, true] {
        let native = glassNativeFrames.mapValues {
            $0.offsetBy(dx: window.minX + (atRightEdge ? 720 : 0), dy: window.minY)
        }
        let expanded = GlassGroupLayout.expandedFrames(nativeFrames: native, controlSize: size, windowFrame: window)
        for progress: CGFloat in [0, 0.3, 0.8, 1, 1.16, GlassGroupRevealState.maximumProgress] {
            let presented = GlassGroupLayout.presentationFrames(
                nativeFrames: native, expandedFrames: expanded, progress: progress, windowFrame: window
            )
            let capsule = try #require(GlassGroupLayout.capsuleFrame(
                buttonFrames: presented, padding: GlassGroupLayout.padding * progress
            ))
            #expect(window.contains(capsule))
            let close = try #require(presented[.close])
            let minimize = try #require(presented[.minimize])
            let zoom = try #require(presented[.zoom])
            #expect(!close.intersects(minimize))
            #expect(!minimize.intersects(zoom))
            #expect(close.width == close.height)
            if progress == 0 { #expect(presented == native) }
            if progress == 1 { #expect(presented == expanded) }
            if progress > 1 { #expect(close.width > size) }
        }
    }
}

@Test func reenteringVisibleCapsuleReversesCollapseButHiddenCapsuleDoesNotActivate() {
    var state = GlassGroupRevealState()
    let native = CGRect(x: 10, y: 10, width: 54, height: 14)
    let expanded = CGRect(x: 8, y: 8, width: 116, height: 44)
    let expandedOnlyPoint = CGPoint(x: 100, y: 30)
    let visibleAtNativeButton = state.desiredVisibility(
        pointer: CGPoint(x: 15, y: 15), nativeRegion: native, expandedRegion: expanded, now: 1
    )
    #expect(visibleAtNativeButton)
    state.advance(visible: true, elapsed: 0.24, reduceMotion: false)
    let visibleOnExit = state.desiredVisibility(
        pointer: CGPoint(x: 200, y: 200), nativeRegion: native, expandedRegion: expanded, now: 2
    )
    #expect(visibleOnExit)
    let visibleAfterGracePeriod = state.desiredVisibility(
        pointer: CGPoint(x: 200, y: 200), nativeRegion: native, expandedRegion: expanded, now: 2.11
    )
    #expect(!visibleAfterGracePeriod)
    state.advance(visible: false, elapsed: 0.09, reduceMotion: false)
    #expect(state.progress > 0)
    let visibleOnReentry = state.desiredVisibility(
        pointer: expandedOnlyPoint, nativeRegion: native, expandedRegion: expanded, now: 2.2
    )
    #expect(visibleOnReentry)
    state.reset()
    let visibleWhenFullyHidden = state.desiredVisibility(
        pointer: expandedOnlyPoint, nativeRegion: native, expandedRegion: expanded, now: 3
    )
    #expect(!visibleWhenFullyHidden)
}

@Test func alwaysVisibleModeClearsPendingExitSoTheAnimationTimerCanStop() {
    var state = GlassGroupRevealState()
    let region = CGRect(x: 0, y: 0, width: 100, height: 50)
    _ = state.desiredVisibility(pointer: CGPoint(x: 20, y: 20), nativeRegion: region, expandedRegion: region, now: 1)
    _ = state.desiredVisibility(pointer: CGPoint(x: 200, y: 200), nativeRegion: region, expandedRegion: region, now: 2)
    #expect(state.isWaitingToCollapse)

    state.advance(visible: true, elapsed: 0, reduceMotion: false, alwaysVisible: true)
    #expect(state.progress == 1)
    #expect(!state.isWaitingToCollapse)
    #expect(!state.isEngaged)
    #expect(!state.isAnimating)
}

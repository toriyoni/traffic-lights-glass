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
    #expect(!state.desiredVisibility(pointer: CGPoint(x: 100, y: 24), nativeRegion: native, expandedRegion: expanded, now: 0))
    #expect(state.desiredVisibility(pointer: CGPoint(x: 15, y: 15), nativeRegion: native, expandedRegion: expanded, now: 1))
    #expect(state.desiredVisibility(pointer: CGPoint(x: 100, y: 24), nativeRegion: native, expandedRegion: expanded, now: 1.1))
    #expect(state.isEngaged)
    #expect(!state.isWaitingToCollapse)
}

@Test func glassExitGraceIsCancelledByReentryAndRestartsOnNextExit() {
    var state = GlassGroupRevealState()
    let region = CGRect(x: 0, y: 0, width: 100, height: 50)
    let inside = CGPoint(x: 20, y: 20)
    let outside = CGPoint(x: 200, y: 200)
    #expect(state.desiredVisibility(pointer: inside, nativeRegion: region, expandedRegion: region, now: 1))
    #expect(state.desiredVisibility(pointer: outside, nativeRegion: region, expandedRegion: region, now: 2))
    #expect(state.isWaitingToCollapse)
    #expect(state.desiredVisibility(pointer: inside, nativeRegion: region, expandedRegion: region, now: 2.05))
    #expect(!state.isWaitingToCollapse)
    #expect(state.desiredVisibility(pointer: outside, nativeRegion: region, expandedRegion: region, now: 3))
    #expect(state.desiredVisibility(pointer: outside, nativeRegion: region, expandedRegion: region, now: 3.09))
    #expect(!state.desiredVisibility(pointer: outside, nativeRegion: region, expandedRegion: region, now: 3.11))
    #expect(!state.isEngaged)
    #expect(!state.isWaitingToCollapse)
}

@Test func glassMotionReversesFromCurrentProgressAndRespectsReducedMotion() {
    var state = GlassGroupRevealState()
    state.advance(visible: true, elapsed: 0.12, reduceMotion: false)
    #expect(abs(state.progress - 0.5) < 0.0001)
    state.advance(visible: false, elapsed: 0.045, reduceMotion: false)
    #expect(abs(state.progress - 0.25) < 0.0001)
    state.advance(visible: true, elapsed: 0.06, reduceMotion: false)
    #expect(abs(state.progress - 0.5) < 0.0001)
    state.advance(visible: true, elapsed: 0, reduceMotion: true)
    #expect(state.progress == 1)
    state.advance(visible: false, elapsed: 0, reduceMotion: true)
    #expect(state.progress == 0)
    state.advance(visible: false, elapsed: 0, reduceMotion: false, alwaysVisible: true)
    #expect(state.progress == 1)
    state.reset()
    #expect(state.progress == 0)
    #expect(!state.isEngaged)
}

@Test func reenteringVisibleCapsuleReversesCollapseButHiddenCapsuleDoesNotActivate() {
    var state = GlassGroupRevealState()
    let native = CGRect(x: 10, y: 10, width: 54, height: 14)
    let expanded = CGRect(x: 8, y: 8, width: 116, height: 44)
    let expandedOnlyPoint = CGPoint(x: 100, y: 30)
    #expect(state.desiredVisibility(pointer: CGPoint(x: 15, y: 15), nativeRegion: native, expandedRegion: expanded, now: 1))
    state.advance(visible: true, elapsed: 0.24, reduceMotion: false)
    #expect(state.desiredVisibility(pointer: CGPoint(x: 200, y: 200), nativeRegion: native, expandedRegion: expanded, now: 2))
    #expect(!state.desiredVisibility(pointer: CGPoint(x: 200, y: 200), nativeRegion: native, expandedRegion: expanded, now: 2.11))
    state.advance(visible: false, elapsed: 0.09, reduceMotion: false)
    #expect(state.progress > 0)
    #expect(state.desiredVisibility(pointer: expandedOnlyPoint, nativeRegion: native, expandedRegion: expanded, now: 2.2))
    state.reset()
    #expect(!state.desiredVisibility(pointer: expandedOnlyPoint, nativeRegion: native, expandedRegion: expanded, now: 3))
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
}

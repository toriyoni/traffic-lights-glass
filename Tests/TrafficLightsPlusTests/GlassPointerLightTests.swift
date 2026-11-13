import AppKit
import Testing
@testable import TrafficLightsPlus

@Test func pointerLightFadesWithoutOvershootAndReleasesItsTimer() {
    var state = GlassPointerLightState()
    let first = CGPoint(x: 11, y: 17), next = CGPoint(x: 29, y: 13)
    state.advance(pointer: first, inside: true, elapsed: 0, reduceMotion: false)
    #expect(state.isAnimating && state.sample == nil)
    for _ in 0..<90 {
        let before = state.intensity
        state.advance(pointer: first, inside: true, elapsed: 1.0/120, reduceMotion: false)
        #expect(state.intensity >= before && state.intensity <= 1)
    }
    #expect(state.sample == GlassLightSample(position: first, intensity: 1) && !state.isAnimating)
    state.advance(pointer: next, inside: true, elapsed: 0, reduceMotion: false)
    #expect(state.sample?.position == next)
    for _ in 0..<120 {
        let before = state.intensity
        state.advance(pointer: CGPoint(x: 1000, y: 1000), inside: false, elapsed: 1.0/120, reduceMotion: false)
        #expect(state.intensity <= before && state.intensity >= 0)
        if state.sample != nil { #expect(state.sample?.position == next) }
    }
    #expect(state.sample == nil && !state.isAnimating)
    state.advance(pointer: first, inside: true, elapsed: 0, reduceMotion: true)
    #expect(state.intensity == 1 && !state.isAnimating)
    state.reset()
    #expect(state.sample == nil && !state.isAnimating)
}

@Test func lightReflectionStrengthFollowsTheRealBoundary() {
    let circle = GlassLightGeometry(path: CGPath(ellipseIn: CGRect(x: 0, y: 0, width: 32, height: 32), transform: nil))
    #expect(circle.edgeStrength(at: CGPoint(x: 16, y: 16)) == 0)
    let near = circle.edgeStrength(at: CGPoint(x: 30, y: 16))
    let closer = circle.edgeStrength(at: CGPoint(x: 31.5, y: 16))
    #expect(near > 0.8 && closer > near)
    #expect(circle.edgeStrength(at: CGPoint(x: 90, y: 16)) == 0)
    #expect(circle.edgeStrength(at: CGPoint(x: CGFloat.nan, y: 0)) == 0)
    let capsule = GlassCapsuleGeometry(start: CGPoint(x: 30, y: 30), end: CGPoint(x: 100, y: 32), radius: 22)
    let geometry = GlassLightGeometry(path: capsule.path)
    #expect(geometry.edgeStrength(at: CGPoint(x: 9, y: 30)) > 0.9)
    #expect(geometry.edgeStrength(at: CGPoint(x: 65, y: 31)) == 0)
}

@Test func whiteLightStaysClippedToTheGlassAndBrightensNearThePointer() throws {
    let width = 80, height = 64
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.1, green: 0.3, blue: 0.15, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let data = try #require(context.data).assumingMemoryBound(to: UInt8.self)
    let before = Array(UnsafeBufferPointer(start: data, count: width * height * 4))
    let geometry = GlassLightGeometry(path: CGPath(ellipseIn: CGRect(x: 16, y: 12, width: 40, height: 40), transform: nil))
    geometry.draw(sample: GlassLightSample(position: CGPoint(x: 50, y: 32), intensity: 1), dark: true, in: context)
    func red(_ x: Int, _ y: Int) -> Int { Int(data[(y * width + x) * 4]) }
    #expect(red(50, 32) > Int(before[(32 * width + 50) * 4]) + 25)
    #expect(red(50, 32) > red(23, 32))
    for (x, y) in [(0, 0), (15, 32), (57, 32), (36, 54)] {
        let i = (y * width + x) * 4
        #expect(Array(UnsafeBufferPointer(start: data + i, count: 4)) == Array(before[i..<(i + 4)]))
    }
}

@MainActor
@Test func lightLayerNeverConsumesClicks() {
    let view = GlassPointerLightView(frame: CGRect(x: 0, y: 0, width: 100, height: 50))
    view.update(path: CGPath(roundedRect: view.bounds, cornerWidth: 25, cornerHeight: 25, transform: nil),
                sample: GlassLightSample(position: CGPoint(x: 20, y: 20), intensity: 1))
    #expect(view.hitTest(CGPoint(x: 20, y: 20)) == nil)
}

@MainActor
@Test func repeatedRevealsPrimeAnInvisibleFrameAtTheNativeLights() throws {
    let panel = GlassGroupPanel()
    panel.ignoresMouseEvents = true
    defer { panel.orderOut(nil) }
    for cycle in 0..<16 {
        let base = CGPoint(x: 200.25 + CGFloat(cycle % 2) * 220, y: 300.5 + CGFloat(cycle % 3) * 70)
        let native = Dictionary(uniqueKeysWithValues: WindowAction.allCases.enumerated().map {
            ($0.element, CGRect(x: base.x + CGFloat($0.offset) * 20, y: base.y, width: 14, height: 14))
        })
        let window = CGRect(x: base.x - 16, y: base.y - 16, width: 600, height: 400)
        let expanded = GlassGroupLayout.expandedFrames(nativeFrames: native, controlSize: cycle.isMultiple(of: 2) ? 23 : 48, windowFrame: window)
        let host = try #require(GlassGroupLayout.presentationEnvelope(nativeFrames: native, expandedFrames: expanded, windowFrame: window))
        for progress: CGFloat in [0, 0.03, 0.2, 1] {
            let p = try #require(GlassGroupLayout.presentation(nativeFrames: native, expandedFrames: expanded, progress: progress, windowFrame: window))
            panel.present(buttonFrames: p.buttonFrames, nativeButtonFrames: Array(native.values), capsuleFrame: p.capsuleFrame,
                progress: progress, containerFrame: host, capsulePath: p.capsule.path)
            if progress == 0 { #expect(panel.alphaValue == 0 && p.buttonFrames == native) }
            else { #expect(panel.alphaValue > 0) }
            for (action, view) in panel.buttonViews {
                let actual = panel.convertToScreen(view.convert(view.bounds, to: nil))
                let expected = try #require(p.buttonFrames[action])
                #expect(abs(actual.midX - expected.midX) < 0.000001)
                #expect(abs(actual.midY - expected.midY) < 0.000001)
            }
        }
        panel.orderOut(nil)
    }
}

@MainActor
@Test func firstShowNearTheMenuBarDoesNotShiftTheControlsDown() throws {
    let screen = try #require(NSScreen.screens.first)
    for phase: CGFloat in [0, 0.05, 1] {
        let panel = GlassGroupPanel()
        panel.ignoresMouseEvents = true
        defer { panel.orderOut(nil) }
        let native = Dictionary(uniqueKeysWithValues: WindowAction.allCases.enumerated().map {
            ($0.element, CGRect(x: screen.visibleFrame.minX + 150 + CGFloat($0.offset) * 20,
                                y: screen.visibleFrame.maxY - 30, width: 14, height: 14))
        })
        let expanded = GlassGroupLayout.expandedFrames(nativeFrames: native, controlSize: 23, windowFrame: screen.frame)
        let p = try #require(GlassGroupLayout.presentation(nativeFrames: native, expandedFrames: expanded, progress: phase, windowFrame: screen.frame))
        let host = try #require(GlassGroupLayout.presentationEnvelope(nativeFrames: native, expandedFrames: expanded, windowFrame: screen.frame))
        let expectedHost = host.union(p.capsuleFrame).insetBy(dx: -GlassGroupLayout.materialBleed, dy: -GlassGroupLayout.materialBleed).integral
        #expect(expectedHost.maxY > screen.visibleFrame.maxY)
        panel.present(buttonFrames: p.buttonFrames, nativeButtonFrames: Array(native.values), capsuleFrame: p.capsuleFrame,
                      progress: phase, containerFrame: host, capsulePath: p.capsule.path)
        #expect(panel.frame == expectedHost)
        for (action, view) in panel.buttonViews {
            let actual = panel.convertToScreen(view.convert(view.bounds, to: nil))
            #expect(abs(actual.midY - p.buttonFrames[action]!.midY) < 0.000001)
        }
    }
}

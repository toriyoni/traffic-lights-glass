import AppKit
import Testing
@testable import TrafficLightsPlus

@Test func zoomMenuArrowUsesTheCapturedGreenButtonPosition() {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 949)
    let anchor = CGRect(x: 395.25, y: 800.5, width: 33.35, height: 33.35)
    let placement = ZoomMenuPlacement(anchor: anchor, visibleScreen: screen)
    #expect(placement.belowAnchor)
    #expect(screen.contains(placement.frame))
    #expect(abs(placement.frame.minX + placement.arrowX - anchor.midX) < 0.000001)
    #expect(anchor.minY - placement.frame.maxY >= 3)
    #expect(anchor.minY - placement.frame.maxY < 4)
    #expect(placement.frame.origin.x.rounded() == placement.frame.origin.x)
    #expect(placement.path.boundingBoxOfPath.maxY == placement.frame.height)
}

@Test func zoomMenuStaysOnScreenAndCanOpenAboveLowWindows() {
    for screen in [CGRect(x: 0, y: 0, width: 1512, height: 949), CGRect(x: -1440, y: -300, width: 1440, height: 867)] {
        for x in [screen.minX + 8, screen.midX, screen.maxX - 42] {
            for y in [screen.minY + 20, screen.maxY - 44] {
                let anchor = CGRect(x: x, y: y, width: 33, height: 33)
                let p = ZoomMenuPlacement(anchor: anchor, visibleScreen: screen)
                #expect(screen.contains(p.frame))
                #expect(p.arrowX >= 24 && p.arrowX <= p.frame.width - 24)
                if y == screen.minY + 20 { #expect(!p.belowAnchor) }
                #expect(p.path.boundingBoxOfPath.minY == 0)
            }
        }
    }
}

@Test func menuApproachProtectionHandlesBothDirectionsAndClampedMenus() {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 949)
    for x: CGFloat in [500, 1472] {
        for y: CGFloat in [650, 20] {
            let green = CGRect(x: x, y: y, width: 33, height: 33)
            let p = ZoomMenuPlacement(anchor: green, visibleScreen: screen)
            let center = CGPoint(x: green.midX, y: green.midY)
            var state = ZoomMenuHoverProtection()
            state.reset(at: center)
            let retained1 = state.retain(at: center, source: green, placement: p, overOtherControl: false, now: 0)
            #expect(retained1)
            let direction: CGFloat = p.belowAnchor ? -1 : 1
            let edgeY = p.belowAnchor ? green.minY : green.maxY
            let diagonal = CGPoint(x: x == 500 ? green.maxX + 15 : green.minX - 15, y: edgeY + direction)
            #expect(!p.containsMenu(diagonal))
            #expect(!GlassGroupLayout.contains(diagonal, in: green))
            let retained2 = state.retain(at: diagonal, source: green.insetBy(dx: 3, dy: 3), placement: p, overOtherControl: false, now: 0.02)
            #expect(retained2)
            #expect(state.deadline != nil)
            // The menu's rounded edge must not cut off the protected approach
            // just before the pointer enters its visible pixels.
            let cornerApproach = CGPoint(x: p.frame.maxX + 3, y: p.frame.midY)
            let nearEdge = state.retain(at: cornerApproach, source: green, placement: p, overOtherControl: false, now: 0.08)
            #expect(nearEdge)
            let retained3 = state.retain(at: CGPoint(x: p.frame.midX, y: p.frame.midY), source: green, placement: p, overOtherControl: false, now: 0.10)
            #expect(retained3)
            #expect(state.deadline == nil)
            for offset: CGFloat in [-31, -62] {
                let retained4 = state.retain(at: CGPoint(x: green.midX + offset, y: green.midY - 10), source: green, placement: p, overOtherControl: true, now: 0.11)
                #expect(!retained4)
            }
        }
    }
}

@Test func menuApproachExpiresAndTurningAwayClosesImmediately() {
    let green = CGRect(x: 500, y: 650, width: 33, height: 33)
    let p = ZoomMenuPlacement(anchor: green, visibleScreen: CGRect(x: 0, y: 0, width: 1512, height: 949))
    let center = CGPoint(x: green.midX, y: green.midY)
    let diagonal = CGPoint(x: green.maxX + 15, y: green.minY - 1)
    var state = ZoomMenuHoverProtection()
    state.reset(at: center)
    let retained5 = state.retain(at: diagonal, source: green, placement: p, overOtherControl: false, now: 0)
    #expect(retained5)
    let retained6 = state.retain(at: diagonal, source: green, placement: p, overOtherControl: false, now: 0.2)
    #expect(retained6)
    let retained7 = state.retain(at: diagonal, source: green, placement: p, overOtherControl: false, now: 0.36)
    #expect(!retained7)
    state.reset(at: center)
    let retained8 = state.retain(at: diagonal, source: green, placement: p, overOtherControl: false, now: 1)
    #expect(retained8)
    let retained9 = state.retain(at: CGPoint(x: diagonal.x, y: diagonal.y + 5), source: green, placement: p, overOtherControl: false, now: 1.01)
    #expect(!retained9)
    state.reset(at: center)
    let retained10 = state.retain(at: CGPoint(x: green.maxX + 15, y: center.y), source: green, placement: p, overOtherControl: false, now: 2)
    #expect(!retained10)
}

@Test func menuEdgeToleranceIsSmallAndDoesNotRenewIndefinitely() {
    let green = CGRect(x: 500, y: 650, width: 33, height: 33)
    let p = ZoomMenuPlacement(anchor: green, visibleScreen: CGRect(x: 0, y: 0, width: 1512, height: 949))
    let inside = CGPoint(x: p.frame.midX, y: p.frame.midY)
    let edge = CGPoint(x: p.frame.minX - 4, y: p.frame.midY)
    var state = ZoomMenuHoverProtection()
    let retained11 = state.retain(at: inside, source: green, placement: p, overOtherControl: false, now: 0)
    #expect(retained11)
    let retained12 = state.retain(at: edge, source: green, placement: p, overOtherControl: false, now: 0.01)
    #expect(retained12)
    let retained13 = state.retain(at: edge, source: green, placement: p, overOtherControl: false, now: 0.1)
    #expect(retained13)
    let retained14 = state.retain(at: edge, source: green, placement: p, overOtherControl: false, now: 0.2)
    #expect(!retained14)
    let retained15 = state.retain(at: inside, source: green, placement: p, overOtherControl: false, now: 1)
    #expect(retained15)
    let retained16 = state.retain(at: CGPoint(x: edge.x - 4, y: edge.y), source: green, placement: p, overOtherControl: false, now: 1.01)
    #expect(!retained16)
}

@MainActor
@Test func protectionNeverExpandsTheClickableMenuAndClosesIfThePointerStops() async throws {
    let green = CGRect(x: 500, y: 650, width: 33, height: 33)
    var pointer = CGPoint(x: green.midX, y: green.midY)
    let menu = ZoomMenuPanel(anchor: green, visibleScreen: CGRect(x: 0, y: 0, width: 1512, height: 949),
        snapshot: WindowMenuSnapshot(enabled: [.fill], isFullScreen: false), language: .english, appearance: nil)
    menu.pointerLocation = { pointer }
    defer { menu.dismiss() }
    menu.present()
    pointer = CGPoint(x: green.maxX + 15, y: green.minY - 1)
    menu.updatePointerLocation(pointer)
    #expect(menu.isVisible)
    #expect(menu.ignoresMouseEvents && !menu.receivesMouse(at: pointer))
    try await Task.sleep(nanoseconds: 430_000_000)
    #expect(!menu.isVisible)
}

@MainActor
@Test func enteringTheMenuCancelsTheProtectionExpiry() async throws {
    let green = CGRect(x: 500, y: 650, width: 33, height: 33)
    var pointer = CGPoint(x: green.midX, y: green.midY)
    let menu = ZoomMenuPanel(anchor: green, visibleScreen: CGRect(x: 0, y: 0, width: 1512, height: 949),
        snapshot: WindowMenuSnapshot(enabled: [.fill], isFullScreen: false), language: .english, appearance: nil)
    menu.pointerLocation = { pointer }
    defer { menu.dismiss() }
    menu.present()
    pointer = CGPoint(x: green.maxX + 15, y: green.minY - 1)
    menu.updatePointerLocation(pointer)
    pointer = CGPoint(x: menu.placement.frame.midX, y: menu.placement.frame.midY)
    menu.updatePointerLocation(pointer)
    try await Task.sleep(nanoseconds: 430_000_000)
    #expect(menu.isVisible && !menu.ignoresMouseEvents)
    menu.otherControlsContain = { _ in true }
    menu.updatePointerLocation(pointer)
    #expect(!menu.isVisible)
}

@MainActor
@Test func menuClosesImmediatelyOutsideItsLiveSourceAndMenu() {
    var green = CGRect(x: 500, y: 650, width: 33, height: 33)
    let menu = ZoomMenuPanel(anchor: green, visibleScreen: CGRect(x: 0, y: 0, width: 1512, height: 949),
        snapshot: WindowMenuSnapshot(enabled: [.fill], isFullScreen: false), language: .english, appearance: nil)
    menu.sourceFrameProvider = { green }
    var dismissals = 0
    menu.onDismiss = { dismissals += 1 }
    defer { menu.dismiss() }
    menu.present()
    menu.updatePointerLocation(CGPoint(x: green.midX, y: green.midY))
    menu.updatePointerLocation(CGPoint(x: green.midX, y: green.minY - 1))
    menu.updatePointerLocation(CGPoint(x: menu.placement.frame.midX, y: menu.placement.frame.midY))
    #expect(menu.isVisible && dismissals == 0)
    green = green.insetBy(dx: 5, dy: 5)
    menu.updatePointerLocation(CGPoint(x: green.midX, y: green.maxY + 2))
    #expect(!menu.isVisible && dismissals == 1)
    menu.present()
    menu.updatePointerLocation(CGPoint(x: green.midX - 31, y: green.midY))
    #expect(!menu.isVisible && dismissals == 2)
}

@Test func fallbackWindowLayoutsUseVisibleScreenCoordinatesWithoutMovingOtherWindows() throws {
    let screen = CGRect(x: -1440, y: 33, width: 1440, height: 867)
    let left = try #require(WindowMenuCommand.left.frame(in: screen))
    let right = try #require(WindowMenuCommand.right.frame(in: screen))
    #expect(left.union(right) == screen)
    #expect(left.maxX == right.minX)
    let topLeft = try #require(WindowMenuCommand.topLeft.frame(in: screen))
    let bottomRight = try #require(WindowMenuCommand.bottomRight.frame(in: screen))
    #expect(topLeft.origin == screen.origin)
    #expect(bottomRight.maxX == screen.maxX && bottomRight.maxY == screen.maxY)
    #expect(WindowMenuCommand.fill.frame(in: screen) == screen)
    // These must remain native commands, never fake multi-window or Split View
    // operations by resizing just the selected window.
    for command in [WindowMenuCommand.halves, .threeWindows, .quarters, .fullScreenLeft, .fullScreenRight] {
        #expect(command.frame(in: screen) == nil)
    }
}

@MainActor
@Test func customZoomMenuKeepsItsAnchorAndDispatchesOneEnabledSelection() throws {
    let anchor = CGRect(x: 500.5, y: 650.25, width: 33.35, height: 33.35)
    let menu = ZoomMenuPanel(anchor: anchor, visibleScreen: CGRect(x: 0, y: 0, width: 1512, height: 949),
        snapshot: WindowMenuSnapshot(enabled: [.fill, .fullScreen], isFullScreen: false), language: .english, appearance: nil)
    var selections: [WindowMenuCommand] = []
    var dismissals = 0
    menu.onCommand = { selections.append($0) }
    menu.onDismiss = { dismissals += 1 }
    menu.present()
    defer { menu.dismiss() }
    #expect(menu.frame == menu.placement.frame.insetBy(dx: -ZoomMenuPanel.shadowInset, dy: -ZoomMenuPanel.shadowInset))
    #expect(!menu.canBecomeKey && !menu.canBecomeMain)
    #expect(menu.styleMask.contains(.nonactivatingPanel))
    let greenCenter = CGPoint(x: anchor.midX, y: anchor.midY)
    #expect(menu.frame.contains(greenCenter))
    #expect(!menu.receivesMouse(at: greenCenter))
    #expect(menu.receivesMouse(at: CGPoint(x: menu.placement.frame.midX, y: menu.placement.frame.midY)))
    func buttons(_ view: NSView) -> [NSButton] {
        (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons)
    }
    let controls = buttons(try #require(menu.contentView))
    let enter = try #require(controls.first { $0.title == "Enter Full Screen" })
    #expect(enter.isEnabled)
    #expect(controls.filter(\.isEnabled).count == 2)
    enter.performClick(nil)
    #expect(selections == [.fullScreen])
    #expect(dismissals == 1 && !menu.isVisible)
    menu.dismiss()
    #expect(dismissals == 1)
}

@MainActor
@Test func menuShadowCanCrossTheMenuBarWithoutMovingTheVisibleMenu() throws {
    let screen = try #require(NSScreen.screens.first)
    let anchor = CGRect(x: screen.visibleFrame.minX + 200, y: screen.visibleFrame.maxY - 20, width: 16, height: 16)
    let menu = ZoomMenuPanel(anchor: anchor, visibleScreen: screen.visibleFrame,
        snapshot: WindowMenuSnapshot(enabled: [.fullScreen], isFullScreen: false), language: .english, appearance: nil)
    defer { menu.dismiss() }
    menu.present()
    #expect(menu.frame == menu.placement.frame.insetBy(dx: -ZoomMenuPanel.shadowInset, dy: -ZoomMenuPanel.shadowInset))
    #expect(menu.frame.maxY > screen.visibleFrame.maxY)
    #expect(menu.placement.frame.maxY < anchor.minY)
    #expect(!menu.receivesMouse(at: CGPoint(x: anchor.midX, y: anchor.midY)))
}

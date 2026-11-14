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

@Test func menuRetentionExcludesOtherLightsAndEmptySpace() {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 949)
    for y: CGFloat in [650, 20] {
        let green = CGRect(x: 500, y: y, width: 33, height: 33)
        let p = ZoomMenuPlacement(anchor: green, visibleScreen: screen)
        #expect(p.containsInteraction(CGPoint(x: green.midX, y: green.midY), source: green))
        #expect(p.containsInteraction(CGPoint(x: p.frame.midX, y: p.frame.midY), source: green))
        let crossingY = p.belowAnchor ? green.minY - 1 : green.maxY + 1
        #expect(p.containsInteraction(CGPoint(x: green.midX, y: crossingY), source: green))
        #expect(!p.containsInteraction(CGPoint(x: green.midX - 31, y: green.midY), source: green))
        #expect(!p.containsInteraction(CGPoint(x: green.midX - 62, y: green.midY), source: green))
        #expect(!p.containsInteraction(CGPoint(x: green.maxX + 5, y: green.midY), source: green))
        #expect(!p.containsInteraction(CGPoint(x: p.frame.minX + 1, y: crossingY), source: green))
    }
    // A clamped menu must not turn the red/yellow controls into a retention
    // corridor when its body extends to the left of the green light.
    let green = CGRect(x: screen.maxX - 40, y: 650, width: 33, height: 33)
    let placement = ZoomMenuPlacement(anchor: green, visibleScreen: screen)
    let corner = CGPoint(x: green.minX + 1, y: green.maxY - 1)
    #expect(!placement.containsInteraction(corner, source: green))
    #expect(placement.containsInteraction(corner, source: green, sourceIsCircular: false))
    for offset: CGFloat in [-31, -62] {
        for dy: CGFloat in [-10, 0, 10] {
            #expect(!placement.containsInteraction(CGPoint(x: green.midX + offset, y: green.midY + dy), source: green))
        }
    }
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

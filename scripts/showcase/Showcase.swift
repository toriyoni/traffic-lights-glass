import AppKit
@testable import TrafficLightsPlus

// Documentation-only host. It renders production views and motion states;
// the scripted pointer never moves the system cursor or sends input events.
private enum Scene: String {
    case flow, reveal, light, appearance, menu
    var isMovie: Bool { [.flow, .reveal, .light].contains(self) }
    var title: String {
        switch self {
        case .flow: return "指到哪里，哪里回应。"
        case .reveal: return "轻轻靠近，从容收放。"
        case .light: return "一束柔光，跟着指针走。"
        case .appearance: return "浅色或深色，都自然融入。"
        case .menu: return "停在绿灯，接着安排窗口。"
        }
    }
    var detail: String {
        switch self {
        case .flow: return "连续换灯 · 独立放大 · 轻微吸附"
        case .reveal: return "从原位展开 · 先快后慢 · 平稳归位"
        case .light: return "柔光跟随 · 边缘反光 · 细微随动"
        case .appearance: return "原生 Liquid Glass · 彩色玻璃按钮"
        case .menu: return "绿灯旁展开 · 固定菜单位置"
        }
    }
    var height: CGFloat { self == .menu ? 560 : 330 }
}

private func label(_ string: String, _ x: CGFloat, _ y: CGFloat,
                   _ size: CGFloat, _ color: NSColor, weight: NSFont.Weight = .regular) {
    (string as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color
    ])
}

private final class Backdrop: NSView {
    let scene: Scene
    init(scene: Scene) { self.scene = scene; super.init(frame: CGRect(x: 0, y: 0, width: 840, height: scene.height)) }
    required init?(coder: NSCoder) { nil }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(srgbRed: 0.945, green: 0.950, blue: 0.960, alpha: 1).setFill()
        bounds.fill()
        label("TRAFFIC LIGHTS GLASS", 26, bounds.height - 34, 11,
              NSColor(calibratedWhite: 0.43, alpha: 1), weight: .semibold)
        label(scene.title, 24, bounds.height - 77, 25,
              NSColor(calibratedWhite: 0.12, alpha: 1), weight: .semibold)
        for row in 0..<2 {
            let dark = row == 1
            let x = CGFloat(row) * 412 + 24
            let card = CGRect(x: x, y: 39, width: 380, height: bounds.height - 139)
            let path = NSBezierPath(roundedRect: card, xRadius: 18, yRadius: 18)
            (dark ? NSColor(srgbRed: 0.128, green: 0.136, blue: 0.15, alpha: 1) : .white).setFill()
            path.fill()
            let muted = NSColor(calibratedWhite: dark ? 0.67 : 0.47, alpha: 1)
            label(dark ? "深色  /  DARK" : "浅色  /  LIGHT", x + 22, card.maxY - 35, 11, muted, weight: .medium)
            label(scene.detail, x + 22, card.minY + 21, 12, muted)
        }
        label("原生组件实录", 26, 13, 10, NSColor(calibratedWhite: 0.48, alpha: 1))
        label(scene.isMovie ? "1× 原速  ·  36 pt" : "36 pt", 706, 13, 10, NSColor(calibratedWhite: 0.48, alpha: 1))
    }
}

@MainActor
private final class ShowcaseHost: NSPanel {
    @objc(_hasActiveAppearance)
    private func showcaseHasActiveAppearance() -> Bool { true }
}

@MainActor
private final class Showcase {
    let scene: Scene
    let output: URL
    let host: NSPanel
    let groups = [GlassGroupPanel(), GlassGroupPanel()]
    var markers: [NSPanel] = []
    var menus: [ZoomMenuPanel] = []
    var nativeViews: [NSButton] = []
    var native: [[WindowAction: CGRect]] = []
    var resting: [[WindowAction: CGRect]] = []
    var current: [[WindowAction: CGRect]] = []
    var envelopes: [CGRect] = []
    var motion = [GlassMagnificationState(), GlassMagnificationState()]
    var light = [GlassPointerLightState(), GlassPointerLightState()]
    var reveal = [GlassGroupRevealState(), GlassGroupRevealState()]
    var fixed: [CGRect?] = [nil, nil]
    var checkedFrames = 0
    var started = 0.0
    var last = 0.0
    var timer: Timer?
    var recorder: Process?

    init(scene: Scene, output: URL) {
        self.scene = scene; self.output = output
        let visible = NSScreen.screens.first!.visibleFrame
        let candidates = [
            CGRect(x: visible.minX + 30, y: visible.minY + 35, width: 840, height: scene.height),
            CGRect(x: visible.maxX - 870, y: visible.maxY - scene.height - 35, width: 840, height: scene.height)
        ]
        let frame = candidates.first { !$0.insetBy(dx: -25, dy: -25).contains(NSEvent.mouseLocation) } ?? candidates[0]
        host = ShowcaseHost(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        host.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        host.isOpaque = true; host.ignoresMouseEvents = true
        host.hasShadow = false; host.backgroundColor = .white
        host.contentView = Backdrop(scene: scene)
        for row in 0..<2 {
            let dark = row == 1
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
            let center = CGPoint(x: frame.minX + CGFloat(row) * 412 + (scene == .menu ? 128 : 214),
                                 y: frame.minY + (scene == .menu ? 384 : 140))
            let small = Dictionary(uniqueKeysWithValues: WindowAction.allCases.enumerated().map {
                ($0.element, CGRect(x: center.x - 27 + CGFloat($0.offset) * 20, y: center.y - 7, width: 14, height: 14))
            })
            native.append(small)
            let expanded = GlassGroupLayout.expandedFrames(nativeFrames: small, controlSize: 36, windowFrame: frame)
            resting.append(expanded); current.append(scene == .reveal ? small : expanded)
            envelopes.append(GlassGroupLayout.presentationEnvelope(nativeFrames: small, expandedFrames: expanded, windowFrame: frame)!)
            let group = groups[row]
            group.appearance = appearance
            group.level = NSWindow.Level(rawValue: host.level.rawValue + 1)
            group.ignoresMouseEvents = true
            for button in group.buttonViews.values { button.isWindowActive = true; button.isGroupHovered = true }
            if scene == .reveal {
                for (action, type) in [(WindowAction.close, NSWindow.ButtonType.closeButton), (.minimize, .miniaturizeButton), (.zoom, .zoomButton)] {
                    let button = NSWindow.standardWindowButton(type, for: [.titled, .closable, .miniaturizable, .resizable])!
                    button.frame = small[action]!.offsetBy(dx: -frame.minX, dy: -frame.minY)
                    button.appearance = appearance
                    host.contentView!.addSubview(button); nativeViews.append(button)
                }
            }
            let cursor = NSCursor.arrow
            let marker = NSPanel(contentRect: CGRect(origin: .zero, size: cursor.image.size),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            marker.backgroundColor = .clear; marker.isOpaque = false
            marker.hasShadow = false; marker.ignoresMouseEvents = true
            marker.level = NSWindow.Level(rawValue: host.level.rawValue + 3)
            marker.contentView = NSImageView(image: cursor.image)
            markers.append(marker)
        }
    }

    // The path is input to the unmodified production state machines.
    // Interpolation only moves this demo pointer; it does not ease the controls.
    func pointer(at time: Double, row: Int) -> CGPoint {
        let center = resting[row][.minimize]!
        var points: [(Double, CGFloat, CGFloat)]
        switch scene {
        case .flow:
            points = [(0,-100,-34),(0.55,-100,-34),(0.90,-44,0),(1.55,-44,0),
                      (2.05,0,0),(2.55,0,0),(3.05,44,0),(3.45,44,0),
                      (3.75,51,7),(4.05,39,-6),(4.35,44,0),(4.70,0,0),
                      (5.10,-44,0),(5.45,0,0),(5.80,44,0),(6.15,0,0),
                      (6.50,-44,0),(6.90,-100,-34),(7.60,-100,-34)]
        case .reveal:
            points = [(0,-100,-34),(0.65,-100,-34),(0.95,0,0),(2.10,0,0),
                      (2.45,-100,-34),(3.30,-100,-34),(3.65,0,0),(4.80,0,0),
                      (5.15,-100,-34),(5.85,-100,-34),(6.10,0,0),(6.45,-100,-34),
                      (7.60,-100,-34)]
        case .light:
            points = [(0,-100,-34),(0.45,-100,-34),(0.85,0,0),(1.10,0,0),
                      (1.50,0,17),(1.95,0,-17),(2.40,0,17),(2.80,0,0),
                      (3.25,44,0),(3.60,44,0),(5.45,44,0),(5.85,0,22),
                      (6.20,-40,22),(6.60,-100,-34),(7.60,-100,-34)]
            if time >= 3.60 && time <= 5.45 {
                let phase = (time - 3.60) / 1.85 * 2 * Double.pi
                return CGPoint(x: center.midX + 44 + 18 * sin(phase), y: center.midY + 18 * (1 - cos(phase)) / 2)
            }
        case .appearance: return CGPoint(x: center.midX + 44 + 8, y: center.midY + 8)
        case .menu: return CGPoint(x: center.midX + 44, y: center.midY)
        }
        let t = min(max(time, 0), 7.5999)
        for i in 1..<points.count where t >= points[i-1].0 && t <= points[i].0 {
            let a = points[i-1], b = points[i]
            let p = CGFloat((t - a.0) / (b.0 - a.0))
            return CGPoint(x: center.midX + a.1 + (b.1-a.1)*p, y: center.midY + a.2 + (b.2-a.2)*p)
        }
        return CGPoint(x: center.midX - 100, y: center.midY - 34)
    }

    func render(time: Double, dt: Double) {
        for row in 0..<2 {
            let pointer = pointer(at: time, row: row)
            let weights = GlassGroupLayout.magnificationWeights(buttonFrames: current[row], pointer: pointer)
            let targets = GlassGroupLayout.magnifiedFrames(restingFrames: resting[row], weights: weights, windowFrame: host.frame)
            let offsets = GlassGroupLayout.magneticOffsets(buttonFrames: targets, weights: weights, pointer: pointer)
            motion[row].advance(targetWeights: weights, elapsed: dt, reduceMotion: false, targetAttractions: offsets)
            if scene == .reveal {
                let visible = reveal[row].desiredVisibility(pointer: pointer,
                    nativeRegion: GlassGroupLayout.capsuleFrame(buttonFrames: native[row], padding: GlassGroupLayout.activationPadding),
                    expandedRegion: GlassGroupLayout.capsuleFrame(buttonFrames: current[row], padding: GlassGroupLayout.retentionPadding), now: time)
                reveal[row].advance(visible: visible, elapsed: dt, reduceMotion: false)
            } else {
                reveal[row].advance(visible: true, elapsed: dt, reduceMotion: false, alwaysVisible: true)
            }
            let p = GlassGroupLayout.presentation(nativeFrames: native[row], expandedFrames: resting[row],
                progress: reveal[row].progress, windowFrame: host.frame,
                magnification: motion[row].weights, attractions: motion[row].attractions)!
            current[row] = p.buttonFrames
            light[row].advance(pointer: pointer, inside: p.capsule.path.contains(pointer), elapsed: dt, reduceMotion: false)
            let group = groups[row]
            group.present(buttonFrames: p.buttonFrames, nativeButtonFrames: [], capsuleFrame: p.capsuleFrame,
                          progress: reveal[row].progress, containerFrame: envelopes[row],
                          capsulePath: p.capsule.path, light: light[row].sample)
            // Keep the native placeholders underneath only while collapsed.
            // They are demo views, not another application's window controls.
            if scene == .reveal {
                for i in row*3..<row*3+3 { nativeViews[i].isHidden = reveal[row].progress > 0 }
            }
            if let expected = fixed[row] { precondition(expected == group.frame, "The capture host moved") }
            fixed[row] = group.frame
            for (action, view) in group.buttonViews {
                let rect = group.convertToScreen(view.convert(view.bounds, to: nil))
                precondition(abs(rect.midX-p.buttonFrames[action]!.midX) < 0.000001)
                precondition(abs(rect.midY-p.buttonFrames[action]!.midY) < 0.000001)
            }
            if scene != .appearance {
                let cursor = NSCursor.arrow
                markers[row].setFrameOrigin(CGPoint(x: pointer.x-cursor.hotSpot.x,
                    y: pointer.y-(cursor.image.size.height-cursor.hotSpot.y)))
                markers[row].orderFrontRegardless()
            }
        }
        checkedFrames += 1
    }

    func start() {
        host.orderFrontRegardless()
        render(time: 0, dt: 1)
        if !scene.isMovie {
            for _ in 0..<120 { render(time: 0, dt: 1.0/60) }
            if scene == .menu {
                for row in 0..<2 {
                    let menu = ZoomMenuPanel(anchor: current[row][.zoom]!, visibleScreen: host.frame,
                        snapshot: WindowMenuSnapshot(enabled: Set(WindowMenuCommand.allCases), isFullScreen: false),
                        language: .simplifiedChinese, appearance: groups[row].appearance)
                    menu.level = NSWindow.Level(rawValue: host.level.rawValue + 2)
                    menu.ignoresMouseEvents = true; menu.orderFrontRegardless(); menus.append(menu)
                }
            }
            Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { [self] _ in
                MainActor.assumeIsolated {
                    let capture = self.captureProcess(movie: false)
                    try! capture.run(); capture.waitUntilExit()
                    precondition(capture.terminationStatus == 0)
                    self.finish()
                }
            }
            return
        }
        last = ProcessInfo.processInfo.systemUptime
        started = last + 0.65
        timer = Timer(timeInterval: 1.0/60, repeats: true) { [self] _ in
            MainActor.assumeIsolated {
                let now = ProcessInfo.processInfo.systemUptime
                self.render(time: max(0, now-self.started), dt: now-self.last)
                self.last = now
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [self] _ in
            MainActor.assumeIsolated {
                let capture = self.captureProcess(movie: true)
                self.recorder = capture
                try! capture.run()
                self.started = ProcessInfo.processInfo.systemUptime + 0.35
            }
        }
        Timer.scheduledTimer(withTimeInterval: 8.8, repeats: false) { [self] _ in
            MainActor.assumeIsolated {
                self.timer?.invalidate()
                self.recorder?.waitUntilExit()
                precondition(self.recorder?.terminationStatus == 0)
                self.finish()
            }
        }
    }

    func captureProcess(movie: Bool) -> Process {
        if FileManager.default.fileExists(atPath: output.path) {
            try! FileManager.default.removeItem(at: output)
        }
        let capture = Process(); capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        let frame = host.frame
        let crop = "-R\(Int(frame.minX)),\(Int(NSScreen.screens.first!.frame.height-frame.maxY)),840,\(Int(scene.height))"
        capture.arguments = ["-x"] + (movie ? ["-v", "-V8.3"] : []) + [crop, output.path]
        return capture
    }

    func finish() {
        print("Captured \(scene.rawValue): \(checkedFrames) production-view updates; fixed hosts and native button centers verified")
        NSApplication.shared.terminate(nil)
    }
}

@main struct Main {
    @MainActor static func main() {
        guard CommandLine.arguments.count == 3, let scene = Scene(rawValue: CommandLine.arguments[1]) else {
            fatalError("Usage: showcase flow|reveal|light|appearance|menu output.mov|output.png")
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        precondition(output.pathExtension == (scene.isMovie ? "mov" : "png"), "Capture output must be a MOV or PNG file")
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited); app.finishLaunching()
        let showcase = Showcase(scene: scene, output: output)
        showcase.start()
        withExtendedLifetime(showcase) { app.run() }
    }
}

import AppKit

enum WindowAction: Int, CaseIterable {
    case close
    case minimize
    case zoom
}

final class OverlayButtonView: NSView {
    let action: WindowAction
    var behavior: ButtonBehavior {
        didSet {
            guard behavior != oldValue else { return }
            updateLocalizedMetadata()
            refreshAppearance()
        }
    }
    var language: AppLanguage = .simplifiedChinese {
        didSet { if language != oldValue { updateLocalizedMetadata() } }
    }
    var style: ControlStyle = .macOS { didSet { if style != oldValue { refreshAppearance() } } }
    var controlSize: CGFloat = 28 { didSet { if controlSize != oldValue { needsDisplay = true } } }
    var isControlEnabled = true { didSet { if isControlEnabled != oldValue { refreshAppearance() } } }
    var isWindowActive = false { didSet { if isWindowActive != oldValue { refreshAppearance() } } }
    var isGroupHovered = false { didSet { if isGroupHovered != oldValue { refreshAppearance() } } }
    var actionHandler: ((WindowAction) -> Void)?
    var hoverHandler: ((Bool) -> Void)?
    var pressHandler: ((WindowAction) -> Void)?
    // A grouped glass control shares the small visual gaps with its neighbors.
    // Points are in this view's coordinates, and may lie outside its bounds.
    var interactionContains: ((NSPoint) -> Bool)?

    var isColorVisible: Bool { isWindowActive || isGroupHovered || isHovered || isPressed }
    var isPointerHighlightVisible: Bool { isGroupHovered || isHovered || isPressed }

    func setPointerInside(_ inside: Bool) {
        guard inside != isHovered else { return }
        isHovered = inside
        if !inside { isPressed = false }
        refreshAppearance()
        if interactionContains != nil { hoverHandler?(inside) }
    }

    func resetInteractionState() {
        guard isHovered || isPressed || isGroupHovered else { return }
        isHovered = false
        isPressed = false
        isGroupHovered = false
        refreshAppearance()
    }

    private var isHovered = false
    private var isPressed = false
    private var trackingAreaRef: NSTrackingArea?
    private var glassSurface: NSView?
    private var pointerLight: GlassLightSample?
    private var fallbackLightGeometry: GlassLightGeometry?

    func updatePointerLight(_ sample: GlassLightSample?) {
        guard sample != nil || pointerLight != nil else { return }
        pointerLight = sample
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), let glass = glassSurface as? NSGlassEffectView { glass.contentView?.needsDisplay = true }
        #endif
        if glassSurface == nil { needsDisplay = true }
    }

    private func drawPointerLight(in view: NSView, geometry: GlassLightGeometry) {
        guard let sample = pointerLight, let window = view.window, let context = NSGraphicsContext.current?.cgContext else { return }
        let point = view.convert(window.convertPoint(fromScreen: sample.position), from: nil)
        let local = GlassLightSample(position: point, intensity: sample.intensity * (isControlEnabled ? 1 : 0.35))
        geometry.draw(sample: local, dark: view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua, in: context)
    }

    init(action: WindowAction) {
        self.action = action
        behavior = ButtonBehavior.defaultBehavior(for: action)
        super.init(frame: .zero)
        setAccessibilityRole(.button)
        updateLocalizedMetadata()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityAppearanceDidChange(_:)),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    override var isFlipped: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutGlassSurface()
    }

    override func layout() {
        super.layout()
        layoutGlassSurface()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        style == .liquidGlass || super.acceptsFirstMouse(for: event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard interactionContains == nil else { return }
        setPointerInside(true)
        hoverHandler?(true)
    }

    override func mouseExited(with event: NSEvent) {
        guard interactionContains == nil else { return }
        setPointerInside(false)
        hoverHandler?(false)
    }

    override func mouseDown(with event: NSEvent) {
        pressHandler?(action)
        guard isControlEnabled else { NSSound.beep(); return }
        isPressed = true
        refreshAppearance()
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            isPressed = false
            refreshAppearance()
        }
        let point = convert(event.locationInWindow, from: nil)
        guard isPressed, isControlEnabled,
              interactionContains?(point) ?? bounds.contains(point) else { return }
        // Consume the press before invoking code that can hide this panel.
        isPressed = false
        actionHandler?(action)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = bounds
        if style == .liquidGlass {
            if glassSurface == nil { drawGlassFallback(in: rect) }
            return
        }
        let actionColor = color(for: action)
        let idleColor = inactiveControlColor()
        let fillColor: NSColor

        if !isControlEnabled {
            fillColor = idleColor
        } else if isPressed {
            fillColor = actionColor.blended(withFraction: 0.24, of: .black) ?? actionColor
        } else if isHovered {
            fillColor = actionColor.blended(withFraction: 0.10, of: .black) ?? actionColor
        } else if isWindowActive || isGroupHovered {
            fillColor = actionColor
        } else {
            fillColor = idleColor
        }

        let path = style == .macOS
            ? NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            : edgeSquarePath(in: rect)
        fillColor.setFill()
        path.fill()

        if style == .macOS {
            NSColor.black.withAlphaComponent(0.16).setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        if style != .macOS || isPointerHighlightVisible {
            drawSymbol(in: rect)
        }
    }

    @objc private func accessibilityAppearanceDidChange(_ notification: Notification) {
        if Thread.isMainThread {
            refreshAppearance()
        } else {
            DispatchQueue.main.async { [weak self] in self?.refreshAppearance() }
        }
    }

    private func refreshAppearance() {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            if style == .liquidGlass && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
                let glass: GlassControlMaterialView
                if let existing = glassSurface as? GlassControlMaterialView {
                    glass = existing
                } else {
                    glass = GlassControlMaterialView(frame: .zero)
                    glass.style = .clear
                    glass.setAccessibilityElement(false)
                    glass.setAccessibilityChildren([])
                    let symbol = GlassControlSymbolView(frame: .zero)
                    symbol.wantsLayer = true
                    symbol.setAccessibilityElement(false)
                    symbol.drawLight = { [weak self, weak symbol] geometry in
                        guard let self, let symbol else { return }
                        self.drawPointerLight(in: symbol, geometry: geometry)
                    }
                    symbol.drawSymbol = { [weak self] bounds in
                        guard let self, self.shouldDrawGlassSymbol else { return }
                        // The material is inset by 1 pt. Keep the glyph's size
                        // and center identical to the existing click target.
                        self.drawSymbol(in: bounds.insetBy(dx: -1, dy: -1))
                    }
                    glass.contentView = symbol
                    addSubview(glass)
                    glassSurface = glass
                }
                let colored = isControlEnabled && isColorVisible
                let color = glassTintColor(colored: colored)
                if glass.tintColor != color { glass.tintColor = color }
                glass.alphaValue = isControlEnabled ? 1 : 0.55
                glass.contentView?.needsDisplay = true
                layoutGlassSurface()
            } else {
                glassSurface?.removeFromSuperview()
                glassSurface = nil
            }
        }
        #endif
        needsDisplay = true
    }

    private func glassTintColor(colored: Bool) -> NSColor {
        guard colored else { return inactiveControlColor().withAlphaComponent(0.48) }
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        // A glass tint isn't a flat fill: Dark Aqua makes the old saturated
        // RGBs much deeper than native lights. Calibrate the optical input in
        // each appearance, keeping the familiar solid palette for other styles.
        let base = action == .zoom
            ? NSColor(srgbRed: 0.25, green: 0.78431, blue: 0.15686, alpha: 1)
            : color(for: action)
        let whiteMix: CGFloat
        var opacity: CGFloat
        switch action {
        case .close:
            whiteMix = dark ? 0.98 : 0.02
            opacity = dark ? 0.82 : 0.78
        case .minimize:
            whiteMix = dark ? 0.85 : 0.02
            opacity = dark ? 0.90 : 0.78
        case .zoom:
            whiteMix = dark ? 0.85 : 0.10
            opacity = 0.78
        }
        // Hover keeps the same color. A press only gently dims the material;
        // increasing saturation and adding black made the old buttons jump.
        if isPressed { opacity += dark ? -0.04 : 0.04 }
        return NSColor(
            srgbRed: base.redComponent + (1 - base.redComponent) * whiteMix,
            green: base.greenComponent + (1 - base.greenComponent) * whiteMix,
            blue: base.blueComponent + (1 - base.blueComponent) * whiteMix,
            alpha: opacity
        )
    }

    private func layoutGlassSurface() {
        guard let glassSurface else { return }
        let rect = bounds.width > 2 && bounds.height > 2 ? bounds.insetBy(dx: 1, dy: 1) : .zero
        if glassSurface.frame != rect { glassSurface.frame = rect }
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), let glass = glassSurface as? NSGlassEffectView {
            let radius = min(rect.width, rect.height) / 2
            if glass.cornerRadius != radius { glass.cornerRadius = radius }
        }
        #endif
        glassSurface.layoutSubtreeIfNeeded()
    }

    private var shouldDrawGlassSymbol: Bool {
        isColorVisible || isPointerHighlightVisible || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    /// Older systems and Reduce Transparency retain a legible solid control.
    /// On macOS 26+, the colored body and its highlights are system glass.
    private func drawGlassFallback(in rect: NSRect) {
        guard rect.width > 2, rect.height > 2 else { return }
        let circleRect = rect.insetBy(dx: 1, dy: 1)
        let circle = NSBezierPath(ovalIn: circleRect)
        let base = isControlEnabled && isColorVisible ? color(for: action) : inactiveControlColor()
        let shade: CGFloat = isPressed ? 0.19 : (isHovered ? 0.06 : 0)
        let fill = base.blended(withFraction: shade, of: .black) ?? base
        fill.setFill()
        circle.fill()

        if !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            NSGradient(
                starting: NSColor.white.withAlphaComponent(isPressed ? 0.04 : 0.20),
                ending: NSColor.white.withAlphaComponent(0.015)
            )?.draw(in: circle, angle: 90)
        }
        let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        NSColor.black.withAlphaComponent(highContrast ? 0.48 : 0.13).setStroke()
        circle.lineWidth = highContrast ? 1.25 : 0.65
        circle.stroke()

        let lightPath = CGPath(ellipseIn: circleRect, transform: nil)
        if fallbackLightGeometry?.path != lightPath { fallbackLightGeometry = GlassLightGeometry(path: lightPath) }
        if let fallbackLightGeometry { drawPointerLight(in: self, geometry: fallbackLightGeometry) }

        if shouldDrawGlassSymbol {
            drawSymbol(in: rect)
        }
    }

    private func updateLocalizedMetadata() {
        let title = behavior.title(language: language)
        toolTip = title
        setAccessibilityLabel(title)
    }

    private func edgeSquarePath(in rect: NSRect) -> NSBezierPath {
        let radius = min(8, rect.height * 0.22)
        let path = NSBezierPath()

        switch action {
        case .close:
            path.move(to: NSPoint(x: rect.minX + radius, y: rect.minY))
            path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
            path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
            path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
            path.line(to: NSPoint(x: rect.minX, y: rect.minY + radius))
            path.curve(
                to: NSPoint(x: rect.minX + radius, y: rect.minY),
                controlPoint1: NSPoint(x: rect.minX, y: rect.minY + radius * 0.45),
                controlPoint2: NSPoint(x: rect.minX + radius * 0.45, y: rect.minY)
            )
        case .minimize, .zoom:
            path.appendRect(rect)
        }
        path.close()
        return path
    }

    private func color(for action: WindowAction) -> NSColor {
        switch action {
        case .close:
            return NSColor(srgbRed: 1.0, green: 0.37255, blue: 0.34118, alpha: 1.0)
        case .minimize:
            return NSColor(srgbRed: 0.99608, green: 0.73725, blue: 0.18039, alpha: 1.0)
        case .zoom:
            return NSColor(srgbRed: 0.15686, green: 0.78431, blue: 0.25098, alpha: 1.0)
        }
    }

    private func inactiveControlColor() -> NSColor {
        switch effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
        case .darkAqua:
            // Sampled from the center of a native inactive traffic-light button.
            return NSColor(srgbRed: 0.37647, green: 0.37647, blue: 0.37255, alpha: 1.0)
        default:
            return NSColor(srgbRed: 0.74510, green: 0.74510, blue: 0.73725, alpha: 1.0)
        }
    }

    private func drawSymbol(in rect: NSRect) {
        guard let symbolRect = Self.symbolRect(in: rect, style: style) else { return }
        let visualSize = min(rect.width, rect.height)
        let path = NSBezierPath()
        path.lineWidth = max(1.0, visualSize * 0.055)
        path.lineCapStyle = .round

        let symbolColor = style == .liquidGlass
            ? NSColor.black.withAlphaComponent(isControlEnabled ? 0.76 : 0.32)
            : NSColor.labelColor.withAlphaComponent(isControlEnabled ? 0.82 : 0.36)
        symbolColor.setStroke()

        switch behavior {
        case .closeWindow, .quitApplication:
            path.move(to: NSPoint(x: symbolRect.minX, y: symbolRect.minY))
            path.line(to: NSPoint(x: symbolRect.maxX, y: symbolRect.maxY))
            path.move(to: NSPoint(x: symbolRect.maxX, y: symbolRect.minY))
            path.line(to: NSPoint(x: symbolRect.minX, y: symbolRect.maxY))
        case .minimizeWindow, .hideApplication:
            path.move(to: NSPoint(x: symbolRect.minX, y: symbolRect.midY))
            path.line(to: NSPoint(x: symbolRect.maxX, y: symbolRect.midY))
        case .zoomWindow:
            if style == .liquidGlass {
                // Two outward arrowheads, matching the native fullscreen
                // affordance; keep legacy styles' drawing unchanged.
                let length = min(symbolRect.width, symbolRect.height) * 0.59
                path.move(to: NSPoint(x: symbolRect.maxX - length, y: symbolRect.minY))
                path.line(to: NSPoint(x: symbolRect.maxX, y: symbolRect.minY))
                path.line(to: NSPoint(x: symbolRect.maxX, y: symbolRect.minY + length))
                path.close()
                path.move(to: NSPoint(x: symbolRect.minX + length, y: symbolRect.maxY))
                path.line(to: NSPoint(x: symbolRect.minX, y: symbolRect.maxY))
                path.line(to: NSPoint(x: symbolRect.minX, y: symbolRect.maxY - length))
                path.close()
                symbolColor.setFill()
                path.fill()
                return
            }
            path.move(to: NSPoint(x: symbolRect.minX, y: symbolRect.maxY))
            path.line(to: NSPoint(x: symbolRect.maxX, y: symbolRect.minY))
        case .doNothing:
            return
        }
        path.stroke()
    }

    static func symbolRect(in rect: NSRect, style: ControlStyle) -> NSRect? {
        let visualSize = min(rect.width, rect.height)
        guard visualSize.isFinite, visualSize > 2,
              rect.minX.isFinite, rect.minY.isFinite else { return nil }
        let inset = visualSize * (style == .macOS ? 0.31 : 0.32)
        let symbolRect = rect.insetBy(dx: inset, dy: inset)
        guard !symbolRect.isNull,
              symbolRect.minX.isFinite, symbolRect.minY.isFinite,
              symbolRect.width.isFinite, symbolRect.height.isFinite,
              symbolRect.width > 0, symbolRect.height > 0 else { return nil }
        return symbolRect
    }
}

#if compiler(>=6.2)
@available(macOS 26.0, *)
private final class GlassControlMaterialView: NSGlassEffectView {
    // OverlayButtonView remains the sole input and accessibility target.
    // The nested optical surface must not consume mouse-down/up or hover.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class GlassControlSymbolView: NSView {
    var drawSymbol: ((NSRect) -> Void)?
    var drawLight: ((GlassLightGeometry) -> Void)?
    private var lightGeometry: GlassLightGeometry?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSGraphicsContext.current?.cgContext.clear(dirtyRect)
        if lightGeometry?.bounds != bounds { lightGeometry = GlassLightGeometry(path: CGPath(ellipseIn: bounds, transform: nil)) }
        if let lightGeometry { drawLight?(lightGeometry) }
        drawSymbol?(bounds)
    }
}
#endif

final class OverlayPanel: NSPanel {
    let overlayView: OverlayButtonView

    init(action: WindowAction) {
        overlayView = OverlayButtonView(action: action)
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        contentView = overlayView
        overlayView.frame = contentView?.bounds ?? .zero
        overlayView.autoresizingMask = [.width, .height]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
    }
}

import AppKit

struct ZoomMenuPlacement {
    static let bodySize = CGSize(width: 252, height: 244)
    static let arrowHeight: CGFloat = 9
    let frame: CGRect
    let arrowX: CGFloat
    let belowAnchor: Bool

    init(anchor: CGRect, visibleScreen: CGRect) {
        let size = CGSize(width: Self.bodySize.width, height: Self.bodySize.height + Self.arrowHeight)
        let below = anchor.minY - 3 - size.height
        belowAnchor = below >= visibleScreen.minY + 4 || anchor.maxY + 3 + size.height > visibleScreen.maxY - 4
        let wantedY = belowAnchor ? below : anchor.maxY + 3
        let x = min(max(anchor.midX - 38, visibleScreen.minX + 4), visibleScreen.maxX - size.width - 4)
        let y = min(max(wantedY, visibleScreen.minY + 4), visibleScreen.maxY - size.height - 4)
        frame = CGRect(origin: CGPoint(x: floor(x), y: floor(y)), size: size)
        arrowX = min(size.width - 24, max(24, anchor.midX - frame.minX))
    }

    var path: CGPath {
        let w = Self.bodySize.width, h = Self.bodySize.height, r: CGFloat = 14
        let path = CGMutablePath()
        path.move(to: CGPoint(x: r, y: 0))
        path.addLine(to: CGPoint(x: w - r, y: 0))
        path.addQuadCurve(to: CGPoint(x: w, y: r), control: CGPoint(x: w, y: 0))
        path.addLine(to: CGPoint(x: w, y: h - r))
        path.addQuadCurve(to: CGPoint(x: w - r, y: h), control: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: arrowX + 10, y: h))
        path.addQuadCurve(to: CGPoint(x: arrowX + 5, y: h + 5), control: CGPoint(x: arrowX + 7, y: h))
        path.addQuadCurve(to: CGPoint(x: arrowX, y: h + 9), control: CGPoint(x: arrowX + 2, y: h + 9))
        path.addQuadCurve(to: CGPoint(x: arrowX - 5, y: h + 5), control: CGPoint(x: arrowX - 2, y: h + 9))
        path.addQuadCurve(to: CGPoint(x: arrowX - 10, y: h), control: CGPoint(x: arrowX - 7, y: h))
        path.addLine(to: CGPoint(x: r, y: h))
        path.addQuadCurve(to: CGPoint(x: 0, y: h - r), control: CGPoint(x: 0, y: h))
        path.addLine(to: CGPoint(x: 0, y: r))
        path.addQuadCurve(to: CGPoint(x: r, y: 0), control: .zero)
        path.closeSubpath()
        guard !belowAnchor else { return path }
        var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: frame.height)
        return path.copy(using: &flip)!
    }

    func containsMenu(_ point: CGPoint) -> Bool {
        path.contains(CGPoint(x: point.x - frame.minX, y: point.y - frame.minY))
    }

    func containsMenuEdge(_ point: CGPoint, padding: CGFloat) -> Bool {
        path.copy(strokingWithWidth: padding * 2, lineCap: .round, lineJoin: .round, miterLimit: 1)
            .contains(CGPoint(x: point.x - frame.minX, y: point.y - frame.minY))
    }

    func containsApproach(_ point: CGPoint, source: CGRect) -> Bool {
        // A broad funnel permits diagonal entry anywhere along the near menu
        // edge. Direction and a finite deadline limit its lifetime; other
        // traffic-light hit targets are explicitly excluded by the owner.
        let edgeY = belowAnchor ? frame.maxY - Self.arrowHeight : frame.minY + Self.arrowHeight
        let startY = source.midY + (belowAnchor ? 4 : -4)
        let corridor = CGMutablePath()
        corridor.move(to: CGPoint(x: source.minX - 6, y: startY))
        corridor.addLine(to: CGPoint(x: source.maxX + 6, y: startY))
        corridor.addLine(to: CGPoint(x: frame.maxX + 6, y: edgeY))
        corridor.addLine(to: CGPoint(x: frame.minX - 6, y: edgeY))
        corridor.closeSubpath()
        return corridor.contains(point)
    }
}

/// A fixed, nonactivating menu. Its arrow is captured once from the visible
/// control, so neither cursor motion nor subsequent button layout can move it.
final class ZoomMenuPanel: NSPanel {
    static let shadowInset: CGFloat = 32
    var onCommand: ((WindowMenuCommand) -> Void)?
    var onDismiss: (() -> Void)?
    var sourceFrameProvider: (() -> CGRect?)?
    var otherControlsContain: ((CGPoint) -> Bool)?
    var pointerLocation: () -> CGPoint = { NSEvent.mouseLocation }
    let anchorFrame: CGRect
    let placement: ZoomMenuPlacement
    private let snapshot: WindowMenuSnapshot
    private let language: AppLanguage
    private var firstRow: [WindowLayoutButton] = []
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var hoverProtection = ZoomMenuHoverProtection()
    private var protectionExpiry: DispatchWorkItem?
    private var scheduledProtectionDeadline: TimeInterval?

    init(anchor: CGRect, visibleScreen: CGRect, snapshot: WindowMenuSnapshot, language: AppLanguage, appearance: NSAppearance?) {
        anchorFrame = anchor
        placement = ZoomMenuPlacement(anchor: anchor, visibleScreen: visibleScreen)
        self.snapshot = snapshot
        self.language = language
        super.init(contentRect: placement.frame.insetBy(dx: -Self.shadowInset, dy: -Self.shadowInset), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        level = .popUpMenu
        self.appearance = appearance
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        animationBehavior = .none
        let content = NSView(frame: CGRect(origin: .zero, size: frame.size))
        let bodyOffset = placement.belowAnchor ? 0 : ZoomMenuPlacement.arrowHeight
        let controls = NSView(frame: CGRect(x: Self.shadowInset, y: Self.shadowInset + bodyOffset, width: ZoomMenuPlacement.bodySize.width, height: ZoomMenuPlacement.bodySize.height))
        makeControls(in: controls)
        var nativeMaterial: NSView?
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            let glassContent = NSView(frame: content.bounds)
            glassContent.addSubview(controls)
            let glass = MorphingGlassSurface(buttonContent: glassContent, materialInset: Self.shadowInset)
            glass.frame = content.bounds
            glass.updateGeometry(path: placement.path)
            nativeMaterial = glass
        }
        #endif
        if let nativeMaterial {
            content.addSubview(nativeMaterial)
        } else {
            let material = NSVisualEffectView(frame: content.bounds.insetBy(dx: Self.shadowInset, dy: Self.shadowInset))
            material.material = .popover
            material.state = .active
            material.blendingMode = .behindWindow
            material.wantsLayer = true
            if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
                material.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            }
            let mask = CAShapeLayer()
            mask.path = placement.path
            material.layer?.mask = mask
            content.addSubview(material)
            content.addSubview(controls)
        }
        contentView = content
        setAccessibilityTitle(AppLocalization.string(.windowMenuTitle, language: language))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        // Placement constrains the visible menu, while its transparent shadow
        // can overlap the menu-bar margin without shifting the anchor/hit map.
        frameRect
    }
    @objc(_hasActiveAppearance) private func glassHasActiveAppearance() -> Bool { true }

    deinit {
        protectionExpiry?.cancel()
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }

    func present() {
        hoverProtection.reset(at: pointerLocation())
        updateOptionKey(NSEvent.modifierFlags.contains(.option))
        updateMousePassThrough()
        orderFrontRegardless()
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .flagsChanged, .scrollWheel]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in self?.observe(event) }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.observe(event)
            return event
        }
    }

    func dismiss() {
        cancelProtectionExpiry()
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        let wasVisible = isVisible
        orderOut(nil)
        if wasVisible { onDismiss?() }
    }

    private func observe(_ event: NSEvent) {
        guard isVisible else { return }
        switch event.type {
        case .flagsChanged:
            updateOptionKey(event.modifierFlags.contains(.option))
        case .mouseMoved:
            updatePointerLocation(pointerLocation())
        case .keyDown:
            dismiss()
        case .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel:
            if event.window !== self { dismiss() }
        default: break
        }
    }

    private func updateMousePassThrough() {
        // The window reserves clear space for the native shadow. That space
        // must not intercept clicks on the green button underneath it.
        ignoresMouseEvents = !receivesMouse(at: pointerLocation())
    }

    func updatePointerLocation(_ point: CGPoint) {
        guard isVisible else { return }
        ignoresMouseEvents = !receivesMouse(at: point)
        let source = sourceFrameProvider?() ?? anchorFrame
        let now = ProcessInfo.processInfo.systemUptime
        guard hoverProtection.retain(at: point, source: source, placement: placement,
            overOtherControl: otherControlsContain?(point) == true, now: now) else {
            dismiss()
            return
        }
        guard let deadline = hoverProtection.deadline else {
            cancelProtectionExpiry()
            return
        }
        guard scheduledProtectionDeadline != deadline else { return }
        cancelProtectionExpiry()
        scheduledProtectionDeadline = deadline
        let expiry = DispatchWorkItem { [weak self] in
            guard let self, self.isVisible, self.scheduledProtectionDeadline == deadline else { return }
            self.updatePointerLocation(self.pointerLocation())
        }
        protectionExpiry = expiry
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, deadline - now), execute: expiry)
    }

    private func cancelProtectionExpiry() {
        protectionExpiry?.cancel()
        protectionExpiry = nil
        scheduledProtectionDeadline = nil
    }

    func receivesMouse(at screenPoint: CGPoint) -> Bool {
        placement.containsMenu(screenPoint)
    }

    private func makeControls(in view: NSView) {
        for (key, y) in [(AppString.windowMenuMoveResize, CGFloat(214)), (.windowMenuArrange, 136), (.windowMenuFullScreen, 58)] {
            let label = NSTextField(labelWithString: AppLocalization.string(key, language: language))
            label.font = .systemFont(ofSize: 13, weight: .semibold)
            label.textColor = .secondaryLabelColor
            label.frame = CGRect(x: 16, y: y, width: 220, height: 18)
            view.addSubview(label)
        }
        for y: CGFloat in [160, 82] {
            let separator = NSBox(frame: CGRect(x: 16, y: y, width: 220, height: 1))
            separator.boxType = .separator
            view.addSubview(separator)
        }
        for (row, y) in [(WindowMenuCommand.halvesRow, CGFloat(170)), (WindowMenuCommand.arrangementRow, 92), (WindowMenuCommand.fullScreenRow, 14)] {
            let pitch = 220 / CGFloat(row.count)
            for (index, command) in row.enumerated() {
                let button = WindowLayoutButton(frame: CGRect(x: 16 + CGFloat(index) * pitch, y: y, width: pitch, height: 36))
                configure(button, command: command)
                button.target = self
                button.action = #selector(selectCommand(_:))
                view.addSubview(button)
                if y == 170 { firstRow.append(button) }
            }
        }
    }

    private func configure(_ button: WindowLayoutButton, command: WindowMenuCommand) {
        button.command = command
        button.title = command.title(language: language, isFullScreen: snapshot.isFullScreen)
        button.isEnabled = snapshot.enabled.contains(command)
        button.toolTip = button.title + (button.isEnabled ? "" : " — " + AppLocalization.string(.windowMenuUnsupported, language: language))
        button.setAccessibilityLabel(button.title)
        button.needsDisplay = true
    }

    private func updateOptionKey(_ pressed: Bool) {
        for (button, command) in zip(firstRow, pressed ? WindowMenuCommand.cornersRow : WindowMenuCommand.halvesRow) {
            configure(button, command: command)
        }
    }

    @objc private func selectCommand(_ sender: WindowLayoutButton) {
        guard sender.isEnabled else { return }
        let handler = onCommand
        let command = sender.command
        dismiss()
        handler?(command)
    }
}

private final class WindowLayoutButton: NSButton {
    var command = WindowMenuCommand.left
    private var hovered = false
    private var tracking: NSTrackingArea?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        if isEnabled && (hovered || isHighlighted) {
            NSColor.controlAccentColor.withAlphaComponent(isHighlighted ? 0.28 : 0.15).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 0), xRadius: 6, yRadius: 6).fill()
        }
        let color = isEnabled ? NSColor.labelColor : NSColor.disabledControlTextColor
        color.setFill(); color.setStroke()
        let rect = CGRect(x: bounds.midX - 13, y: bounds.midY - 10, width: 26, height: 20)
        if command == .fullScreen {
            let p = NSBezierPath()
            for sign: CGFloat in [-1, 1] {
                let end = CGPoint(x: bounds.midX + sign * 9, y: bounds.midY + sign * 9)
                p.move(to: CGPoint(x: bounds.midX + sign * 2, y: bounds.midY + sign * 2)); p.line(to: end)
                p.move(to: CGPoint(x: end.x - sign * 7, y: end.y)); p.line(to: end); p.line(to: CGPoint(x: end.x, y: end.y - sign * 7))
            }
            p.lineWidth = 2; p.lineCapStyle = .round; p.lineJoinStyle = .round; p.stroke()
            return
        }
        let outline = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        outline.lineWidth = 1.8; outline.stroke()
        let inner = rect.insetBy(dx: 4, dy: 4)
        let parts: [CGRect]
        switch command {
        case .halves: parts = [CGRect(x: 0, y: 0, width: 0.5, height: 1), CGRect(x: 0.5, y: 0, width: 0.5, height: 1)]
        case .threeWindows: parts = [CGRect(x: 0, y: 0, width: 0.5, height: 0.5), CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5), CGRect(x: 0.5, y: 0, width: 0.5, height: 1)]
        case .quarters: parts = WindowMenuCommand.cornersRow.compactMap(\.frameFraction)
        case .fullScreenLeft: parts = [WindowMenuCommand.left.frameFraction!]
        case .fullScreenRight: parts = [WindowMenuCommand.right.frameFraction!]
        default: parts = command.frameFraction.map { [$0] } ?? []
        }
        for part in parts {
            let y = isFlipped ? inner.minY + part.minY * inner.height : inner.maxY - part.maxY * inner.height
            let region = CGRect(x: inner.minX + part.minX * inner.width, y: y,
                                width: part.width * inner.width, height: part.height * inner.height)
                .insetBy(dx: parts.count > 1 ? 0.6 : 0, dy: parts.count > 1 ? 0.6 : 0)
            NSBezierPath(roundedRect: region, xRadius: 0.8, yRadius: 0.8).fill()
        }
    }
}

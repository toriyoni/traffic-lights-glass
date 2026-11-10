import AppKit

/// A single, nonactivating surface for all three window controls. Geometry and
/// animation progress come from WindowOverlay, so the capsule and its controls
/// can never start independent reveal animations.
final class GlassGroupPanel: NSPanel {
    let buttonViews: [WindowAction: OverlayButtonView]
    private(set) var presentedCapsuleFrame: NSRect?

    private let buttonContentView = NSView(frame: .zero)
    private var materialView: NSView?
    private var nativeLightMask: NativeLightMaskView?
    private var usesOpaqueMaterial = false

    init(actions: [WindowAction] = WindowAction.allCases) {
        buttonViews = Dictionary(uniqueKeysWithValues: actions.map {
            ($0, OverlayButtonView(action: $0))
        })
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
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

        for view in buttonViews.values {
            view.style = .liquidGlass
            buttonContentView.addSubview(view)
        }
        installMaterial()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityAppearanceDidChange(_:)),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // This panel deliberately never takes keyboard focus. AppKit otherwise
    // treats its NSGlassEffectView as inactive and suppresses the native rim
    // highlight, even while the window underneath is active. This appearance-
    // only AppKit hook keeps the system glass fully rendered without making
    // the panel key/main or drawing a replacement border. It is undocumented:
    // if AppKit stops consulting it, the normal inactive material remains.
    @objc(_hasActiveAppearance)
    private func glassHasActiveAppearance() -> Bool { true }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    /// All input rectangles use global AppKit coordinates (origin at the bottom
    /// left). The content view is deliberately not flipped; only each button's
    /// drawing coordinates are flipped.
    func present(
        buttonFrames: [WindowAction: NSRect],
        nativeButtonFrames: [NSRect],
        capsuleFrame: NSRect,
        progress: CGFloat,
        containerFrame: NSRect? = nil
    ) {
        guard progress.isFinite, progress > 0,
              Self.isValid(capsuleFrame), !buttonFrames.isEmpty else {
            presentedCapsuleFrame = nil
            orderOut(nil)
            return
        }

        let visibleProgress = min(1, max(0, progress))
        // AppKit rounds top-level window frames. Resizing that window on every
        // animation frame shifts the visible center by up to a point, even when
        // the requested center is constant. Animate views in a stationary host.
        let hostFrame = containerFrame.flatMap { Self.isValid($0) ? $0 : nil } ?? capsuleFrame
        let integralHost = hostFrame.union(capsuleFrame).integral
        if frame != integralHost { setFrame(integralHost, display: false) }
        presentedCapsuleFrame = capsuleFrame
        let localFrame = capsuleFrame.offsetBy(dx: -frame.minX, dy: -frame.minY)
        materialView?.frame = localFrame
        if let nativeLightMask {
            let localFrames = nativeButtonFrames.filter(Self.isValid).map {
                $0.offsetBy(dx: -capsuleFrame.minX, dy: -capsuleFrame.minY)
            }
            if nativeLightMask.frame != localFrame || nativeLightMask.buttonFrames != localFrames {
                nativeLightMask.frame = localFrame
                nativeLightMask.buttonFrames = localFrames
                nativeLightMask.needsDisplay = true
            }
        }
        layoutMaterialContent()

        var hasVisibleButton = false
        for (action, view) in buttonViews {
            guard let buttonFrame = buttonFrames[action], Self.isValid(buttonFrame) else {
                view.isHidden = true
                view.resetInteractionState()
                continue
            }
            view.isHidden = false
            view.frame = buttonFrame.offsetBy(dx: -capsuleFrame.minX, dy: -capsuleFrame.minY)
            view.controlSize = min(buttonFrame.width, buttonFrame.height)
            hasVisibleButton = true
        }

        guard hasVisibleButton else {
            orderOut(nil)
            return
        }
        (materialView as? RoundedMaterialView)?.updateCornerRadius()
        // One fade for the whole surface. Individual controls never cross-fade
        // independently or leave separate colored ghosts during expansion.
        alphaValue = min(1, visibleProgress * 4)
        if !isVisible { orderFrontRegardless() }
    }

    @objc private func accessibilityAppearanceDidChange(_ notification: Notification) {
        if Thread.isMainThread {
            refreshAccessibilityAppearance()
        } else {
            DispatchQueue.main.async { [weak self] in self?.refreshAccessibilityAppearance() }
        }
    }

    private func refreshAccessibilityAppearance() {
        let shouldBeOpaque = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        if shouldBeOpaque != usesOpaqueMaterial { installMaterial() }
        materialView?.needsDisplay = true
        buttonViews.values.forEach { $0.needsDisplay = true }
    }

    private func installMaterial() {
        usesOpaqueMaterial = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        nativeLightMask = nil
        buttonContentView.removeFromSuperview()
        buttonContentView.translatesAutoresizingMaskIntoConstraints = true
        buttonContentView.autoresizingMask = [.width, .height]

        let surface: NSView
        if usesOpaqueMaterial {
            let opaque = OpaqueCapsuleView(frame: .zero)
            opaque.addSubview(buttonContentView)
            surface = opaque
        } else {
            surface = makeGlassMaterial()
        }
        surface.frame = presentedCapsuleFrame?.offsetBy(dx: -frame.minX, dy: -frame.minY)
            ?? NSRect(origin: .zero, size: frame.size)
        surface.autoresizingMask = []
        materialView = surface
        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        if let nativeLightMask {
            nativeLightMask.frame = surface.frame
            container.addSubview(nativeLightMask)
        }
        container.addSubview(surface)
        contentView = container
        layoutMaterialContent()
        (surface as? RoundedMaterialView)?.updateCornerRadius()
    }

    private func layoutMaterialContent() {
        guard let materialView, !materialView.bounds.isEmpty else { return }
        // NSGlassEffectView supplies the content view's edge constraints.
        // Do not mix manual frame writes with that layout. The fallback views
        // have no constraints, so their content follows the material bounds.
        if buttonContentView.translatesAutoresizingMaskIntoConstraints {
            buttonContentView.frame = materialView.bounds
        }
        materialView.layoutSubtreeIfNeeded()
    }

    private func makeGlassMaterial() -> NSView {
        // Native Liquid Glass requires the macOS 26 SDK (Xcode 26 / matching
        // Command Line Tools or newer). The compiler guard keeps ordinary older
        // Apple toolchains on the material fallback; runtime availability alone
        // cannot make an unknown SDK symbol compile.
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = 999
            glass.tintColor = nil
            // Apple's glass compositor expects content here, not in a sibling.
            buttonContentView.translatesAutoresizingMaskIntoConstraints = false
            buttonContentView.autoresizingMask = []
            glass.contentView = buttonContentView
            nativeLightMask = NativeLightMaskView(frame: .zero)
            return glass
        }
        #endif

        let material = RoundedMaterialView(frame: .zero)
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        material.addSubview(buttonContentView)
        return material
    }

    private static func isValid(_ rect: NSRect) -> Bool {
        rect.minX.isFinite && rect.minY.isFinite
            && rect.width.isFinite && rect.height.isFinite
            && rect.width > 0 && rect.height > 0
    }
}

/// Cover only the original lights so the system glass samples a neutral
/// backdrop there. The glass still samples the surrounding title bar.
private final class NativeLightMaskView: NSView {
    var buttonFrames: [NSRect] = []

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard !buttonFrames.isEmpty else { return }
        let radius = min(bounds.width, bounds.height) / 2
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).addClip()
        NSColor.windowBackgroundColor.setFill()
        for frame in buttonFrames {
            NSBezierPath(ovalIn: frame.insetBy(dx: -1, dy: -1)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// Pre-Tahoe fallback, intentionally one rounded material rather than three
/// independently blurred windows. Native Liquid Glass is selected above on 26+.
private final class RoundedMaterialView: NSVisualEffectView {
    func updateCornerRadius() {
        wantsLayer = true
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
        layer?.masksToBounds = true
    }

    override func layout() {
        super.layout()
        updateCornerRadius()
    }
}

private final class OpaqueCapsuleView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let radius = min(bounds.width, bounds.height) / 2
        let capsule = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        NSColor.windowBackgroundColor.setFill()
        capsule.fill()
        if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            NSColor.labelColor.withAlphaComponent(0.5).setStroke()
            capsule.lineWidth = 1
            capsule.stroke()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

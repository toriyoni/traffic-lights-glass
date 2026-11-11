import AppKit

#if compiler(>=6.2)
/// Merge a capsule bridge and three variable-radius lobes using Apple's glass
/// compositor. Keep the colored button glass outside this merging container:
/// nesting it inside the lobes prevents AppKit from merging their outlines.
@available(macOS 26.0, *)
final class MorphingGlassSurface: NSView {
    private let glassContainer = GlassBackgroundContainer()
    private let glassContent = NSView()
    private let bridge = NSGlassEffectView()
    private let lobes: [WindowAction: NSGlassEffectView]

    init(buttonContent: NSView) {
        lobes = Dictionary(uniqueKeysWithValues: WindowAction.allCases.map { ($0, NSGlassEffectView()) })
        super.init(frame: .zero)
        glassContainer.contentView = glassContent
        for glass in [bridge] + Array(lobes.values) {
            glass.style = .regular
            glass.cornerRadius = 999
            glass.tintColor = nil
            glass.setAccessibilityElement(false)
            glassContent.addSubview(glass)
        }
        addSubview(glassContainer)
        // The button views still own the exact visible and clickable frames.
        addSubview(buttonContent)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        glassContainer.frame = bounds
    }

    func updateGeometry(buttonFrames: [WindowAction: CGRect], padding: CGFloat) {
        glassContainer.frame = bounds
        glassContainer.spacing = padding * 2
        glassContainer.layoutSubtreeIfNeeded()
        let frames = buttonFrames.values.filter { !$0.isEmpty && !$0.isInfinite && !$0.isNull }
        guard let union = GlassGroupLayout.capsuleFrame(buttonFrames: buttonFrames, padding: 0),
              let shortest = frames.map(\.height).min() else { return }

        // At rest the bridge makes one smooth pill. A larger lobe extends out
        // of it locally; the container supplies the joined rim and refraction.
        let height = shortest + padding * 2
        bridge.frame = CGRect(
            x: union.minX - padding, y: union.midY - height / 2,
            width: union.width + padding * 2, height: height
        )
        for (action, glass) in lobes {
            guard let frame = buttonFrames[action] else {
                glass.isHidden = true
                continue
            }
            glass.isHidden = false
            glass.frame = frame.insetBy(dx: -padding, dy: -padding)
        }
    }
}

@available(macOS 26.0, *)
private final class GlassBackgroundContainer: NSGlassEffectContainerView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
#endif

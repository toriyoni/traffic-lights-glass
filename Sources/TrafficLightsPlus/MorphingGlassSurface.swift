import AppKit
import SwiftUI

#if compiler(>=6.2)
/// SwiftUI's native glass accepts a custom Shape, unlike AppKit's corner-radius
/// API. Only the outer contour is ours: material, refraction and rim stay native.
@available(macOS 26.0, *)
final class MorphingGlassSurface: NSView {
    private let glass = GlassHostingView(rootView: BubbleMaterial(path: Path()))
    private let materialInset: CGFloat
    private var lastPath: CGPath?

    init(buttonContent: NSView? = nil, materialInset: CGFloat = 0) {
        self.materialInset = materialInset
        super.init(frame: .zero)
        glass.sizingOptions = []
        glass.safeAreaRegions = []
        glass.setAccessibilityElement(false)
        addSubview(glass)
        // Keep the existing button material and hit targets above the background.
        if let buttonContent { addSubview(buttonContent) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        glass.frame = bounds
    }

    func updateGeometry(path: CGPath) {
        if glass.frame != bounds { glass.frame = bounds }
        if lastPath != path {
            lastPath = path
            glass.rootView = BubbleMaterial(path: Path(path), inset: materialInset)
        }
        // Use the same presentation frame as the AppKit buttons. A second
        // implicit animation would let the glass trail behind its hit targets.
        glass.layoutSubtreeIfNeeded()
    }
}

@available(macOS 26.0, *)
private final class GlassHostingView: NSHostingView<BubbleMaterial> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@available(macOS 26.0, *)
private struct BubbleMaterial: View {
    let path: Path
    var inset: CGFloat = 0

    var body: some View {
        Color.clear
            .glassEffect(.regular, in: BubbleShape(outline: path))
            .padding(inset)
            .environment(\.controlActiveState, .key)
            .allowsHitTesting(false)
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
    }
}

@available(macOS 26.0, *)
private struct BubbleShape: Shape {
    let outline: Path

    func path(in rect: CGRect) -> Path {
        // AppKit geometry is bottom-up; the SwiftUI shape is top-down.
        outline.applying(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: rect.height))
    }
}
#endif

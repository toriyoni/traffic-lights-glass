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
    private var lastCanvasHeight: CGFloat?

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
        let height = max(0, bounds.height - materialInset * 2)
        if lastPath != path || lastCanvasHeight != height {
            lastPath = path
            lastCanvasHeight = height
            // Use the known AppKit canvas height, not a transient SwiftUI
            // proposal from the first layout pass of a newly shown window.
            let flipped = Path(path).applying(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: height))
            glass.rootView = BubbleMaterial(path: flipped, inset: materialInset)
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
        outline
    }
}
#endif

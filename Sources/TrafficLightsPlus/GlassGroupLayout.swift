import CoreGraphics
import Foundation

/// Geometry is in the caller's coordinate space. Expanded frames use the
/// window-server space, whose origin is at the top-left of each window.
struct GlassGroupLayout {
    static let padding: CGFloat = 8
    static let gap: CGFloat = 8
    static let activationPadding: CGFloat = 10
    static let retentionPadding: CGFloat = 8
    private static let windowInset: CGFloat = 4

    static func expandedFrames(
        nativeFrames: [WindowAction: CGRect],
        controlSize: CGFloat,
        windowFrame: CGRect
    ) -> [WindowAction: CGRect] {
        guard isUsable(windowFrame) else { return [:] }
        let actions = WindowAction.allCases.filter {
            nativeFrames[$0].map(isUsable) == true
        }
        guard !actions.isEmpty,
              let nativeUnion = capsuleFrame(buttonFrames: nativeFrames, padding: 0) else { return [:] }

        // A small preference must never shrink an unusually large native button.
        let nativeDiameter = actions.compactMap { nativeFrames[$0] }
            .map { max($0.width, $0.height) }.max() ?? 0
        let diameter = max(ControlLayout.effectiveSize(preferred: Double(controlSize)), nativeDiameter)
        let groupWidth = CGFloat(actions.count) * diameter + CGFloat(actions.count - 1) * gap
        let edgeInset = windowInset + padding
        var left = max(nativeUnion.midX - groupWidth / 2, windowFrame.minX + edgeInset)
        var top = max(nativeUnion.midY - diameter / 2, windowFrame.minY + edgeInset)

        // Keep the capsule inside a normal window without compressing the
        // buttons into each other in the rare case of a very narrow window.
        if windowFrame.width >= groupWidth + edgeInset * 2 {
            left = min(left, windowFrame.maxX - edgeInset - groupWidth)
        }
        if windowFrame.height >= diameter + edgeInset * 2 {
            top = min(top, windowFrame.maxY - edgeInset - diameter)
        }

        return Dictionary(uniqueKeysWithValues: actions.enumerated().map { index, action in
            (action, CGRect(
                x: left + CGFloat(index) * (diameter + gap),
                y: top,
                width: diameter,
                height: diameter
            ))
        })
    }

    static func capsuleFrame(
        buttonFrames: [WindowAction: CGRect],
        padding: CGFloat = GlassGroupLayout.padding
    ) -> CGRect? {
        let frames = buttonFrames.values.filter(isUsable)
        guard var union = frames.first else { return nil }
        for frame in frames.dropFirst() { union = union.union(frame) }
        let safePadding = padding.isFinite ? max(padding, 0) : Self.padding
        return union.insetBy(dx: -safePadding, dy: -safePadding)
    }

    struct Presentation {
        let buttonFrames: [WindowAction: CGRect]
        let capsuleFrame: CGRect
    }

    /// Interpolate position and size together so every button travels directly
    /// toward its target. Timing is eased once by GlassGroupRevealState.
    static func presentation(
        nativeFrames: [WindowAction: CGRect],
        expandedFrames: [WindowAction: CGRect],
        progress: CGFloat,
        windowFrame: CGRect
    ) -> Presentation? {
        guard isUsable(windowFrame), progress.isFinite else { return nil }
        let amount = min(1, max(0, progress))
        var result: [WindowAction: CGRect] = [:]
        for (action, expanded) in expandedFrames {
            guard let native = nativeFrames[action], isUsable(native), isUsable(expanded) else { continue }
            result[action] = CGRect(
                x: native.minX + (expanded.minX - native.minX) * amount,
                y: native.minY + (expanded.minY - native.minY) * amount,
                width: native.width + (expanded.width - native.width) * amount,
                height: native.height + (expanded.height - native.height) * amount
            )
        }
        guard let capsule = capsuleFrame(buttonFrames: result, padding: padding * amount) else { return nil }
        var offset = CGPoint.zero

        // Keep the group inside a normal window without squashing its buttons.
        if capsule.width <= windowFrame.width {
            offset.x = min(max(capsule.minX, windowFrame.minX), windowFrame.maxX - capsule.width) - capsule.minX
        }
        if capsule.height <= windowFrame.height {
            offset.y = min(max(capsule.minY, windowFrame.minY), windowFrame.maxY - capsule.height) - capsule.minY
        }
        return Presentation(
            buttonFrames: result.mapValues { $0.offsetBy(dx: offset.x, dy: offset.y) },
            capsuleFrame: capsule.offsetBy(dx: offset.x, dy: offset.y)
        )
    }

    /// A stationary host for the entire animation, also used for occlusion.
    static func presentationEnvelope(
        nativeFrames: [WindowAction: CGRect],
        expandedFrames: [WindowAction: CGRect],
        windowFrame: CGRect
    ) -> CGRect? {
        guard isUsable(windowFrame), let resting = capsuleFrame(buttonFrames: expandedFrames) else { return nil }
        let native = capsuleFrame(buttonFrames: nativeFrames) ?? resting
        return resting.union(native)
    }

    private static func isUsable(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isInfinite &&
            frame.minX.isFinite && frame.minY.isFinite &&
            frame.width.isFinite && frame.height.isFinite &&
            frame.width > 0 && frame.height > 0
    }
}

/// One ease-out drives the glass and all buttons. Retargeting starts at the
/// current position; a short exit grace avoids collapse near an edge.
struct GlassGroupRevealState {
    static let exitGrace: TimeInterval = 0.10
    static let expandDuration: TimeInterval = 0.24
    static let collapseDuration: TimeInterval = 0.18

    private(set) var progress: CGFloat = 0
    private(set) var velocity: CGFloat = 0
    private var target: CGFloat = 0
    private var startProgress: CGFloat = 0
    private var animationElapsed: TimeInterval = 0
    private var animationDuration: TimeInterval = 0
    private(set) var isEngaged = false
    private(set) var exitStartedAt: TimeInterval?

    var isWaitingToCollapse: Bool { exitStartedAt != nil }
    var isAnimating: Bool { progress != target || velocity != 0 }

    mutating func desiredVisibility(
        pointer: CGPoint,
        nativeRegion: CGRect?,
        expandedRegion: CGRect?,
        now: TimeInterval
    ) -> Bool {
        guard let nativeRegion else {
            isEngaged = false
            exitStartedAt = nil
            return false
        }

        // While any part of the capsule is still visible, re-entering it
        // reverses the animation without requiring a trip to the native lights.
        let retentionRegion = expandedRegion.map { nativeRegion.union($0) } ?? nativeRegion
        if !isEngaged {
            guard nativeRegion.contains(pointer) ||
                    (progress > 0 && retentionRegion.contains(pointer)) else { return false }
            isEngaged = true
            exitStartedAt = nil
            return true
        }

        // Regions already include their caller-selected padding. The union
        // also keeps the path from the native controls to the capsule active.
        if retentionRegion.contains(pointer) {
            exitStartedAt = nil
            return true
        }

        if exitStartedAt == nil { exitStartedAt = now }
        if let exitStartedAt, now - exitStartedAt >= Self.exitGrace {
            isEngaged = false
            self.exitStartedAt = nil
            return false
        }
        return true
    }

    mutating func advance(
        visible: Bool,
        elapsed: TimeInterval,
        reduceMotion: Bool,
        alwaysVisible: Bool = false
    ) {
        let nextTarget: CGFloat = alwaysVisible || visible ? 1 : 0
        if nextTarget != target {
            target = nextTarget
            startProgress = progress
            animationElapsed = 0
            // Short reversals should not replay the full duration. Start from
            // the visible size and immediately head toward the new target.
            let distance = abs(target - progress)
            animationDuration = (visible ? Self.expandDuration : Self.collapseDuration) * sqrt(Double(distance))
            velocity = animationDuration > 0 ? 3 * (target - progress) / CGFloat(animationDuration) : 0
        }
        if alwaysVisible {
            isEngaged = false
            exitStartedAt = nil
        }
        if alwaysVisible || reduceMotion {
            progress = target
            velocity = 0
            animationElapsed = animationDuration
            return
        }
        guard elapsed.isFinite, elapsed > 0, isAnimating else { return }
        animationElapsed = min(animationElapsed + elapsed, animationDuration)
        guard animationDuration > 0, animationElapsed < animationDuration else {
            progress = target
            velocity = 0
            return
        }

        // Cubic ease-out: fast initial response, continuously decreasing speed,
        // and exactly zero speed at the endpoint. No overshoot or oscillation.
        let remaining = CGFloat(1 - animationElapsed / animationDuration)
        progress = target + (startProgress - target) * remaining * remaining * remaining
        velocity = 3 * (target - startProgress) * remaining * remaining / CGFloat(animationDuration)
    }

    mutating func reset() {
        progress = 0
        velocity = 0
        target = 0
        startProgress = 0
        animationElapsed = 0
        animationDuration = 0
        isEngaged = false
        exitStartedAt = nil
    }
}

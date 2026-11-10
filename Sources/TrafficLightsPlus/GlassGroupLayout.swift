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

    /// The spring can travel past the resting size. Keep that overshoot in the
    /// geometry instead of using the classic controls' clamped interpolation.
    static func presentationFrames(
        nativeFrames: [WindowAction: CGRect],
        expandedFrames: [WindowAction: CGRect],
        progress: CGFloat,
        windowFrame: CGRect
    ) -> [WindowAction: CGRect] {
        guard isUsable(windowFrame), progress.isFinite else { return [:] }
        let amount = min(GlassGroupRevealState.maximumProgress, max(0, progress))
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
        guard let capsule = capsuleFrame(buttonFrames: result, padding: padding * amount) else { return [:] }

        // Move the entire group together if its bounce reaches a window edge.
        // Never squash individual buttons or change the gaps to make it fit.
        var offset = CGPoint.zero
        if capsule.width <= windowFrame.width {
            offset.x = min(max(capsule.minX, windowFrame.minX), windowFrame.maxX - capsule.width) - capsule.minX
        }
        if capsule.height <= windowFrame.height {
            offset.y = min(max(capsule.minY, windowFrame.minY), windowFrame.maxY - capsule.height) - capsule.minY
        }
        return result.mapValues { $0.offsetBy(dx: offset.x, dy: offset.y) }
    }

    private static func isUsable(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isInfinite &&
            frame.minX.isFinite && frame.minY.isFinite &&
            frame.width.isFinite && frame.height.isFinite &&
            frame.width > 0 && frame.height > 0
    }
}

/// One spring drives the glass and all buttons. Reversing direction preserves
/// position and velocity; a short exit grace avoids collapse near an edge.
struct GlassGroupRevealState {
    static let exitGrace: TimeInterval = 0.10
    static let maximumProgress: CGFloat = 1.24

    private(set) var progress: CGFloat = 0
    private(set) var velocity: CGFloat = 0
    private var target: CGFloat = 0
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
        target = alwaysVisible || visible ? 1 : 0
        if alwaysVisible {
            isEngaged = false
            exitStartedAt = nil
        }
        if alwaysVisible || reduceMotion {
            progress = target
            velocity = 0
            return
        }
        guard elapsed.isFinite, elapsed > 0, isAnimating else { return }
        if elapsed >= 1 {
            progress = target
            velocity = 0
            return
        }

        let time = CGFloat(elapsed)
        let displacement = progress - target
        let nextDisplacement: CGFloat
        if visible {
            // An underdamped reveal peaks at about 165 ms, then softly settles.
            // Solve the spring analytically so dropped frames don't change it.
            let frequency: CGFloat = 22
            let decay = frequency * 0.5
            let dampedFrequency = sqrt(frequency * frequency - decay * decay)
            let envelope = exp(-decay * time)
            let cosine = cos(dampedFrequency * time)
            let sine = sin(dampedFrequency * time)
            nextDisplacement = envelope * (
                displacement * cosine + (velocity + decay * displacement) / dampedFrequency * sine
            )
            velocity = envelope * (
                velocity * cosine - (decay * velocity + frequency * frequency * displacement) / dampedFrequency * sine
            )
        } else {
            // A critically damped return feels quick and doesn't bounce back
            // into view. Retargeting still carries the current momentum.
            let frequency: CGFloat = 30
            let coefficient = velocity + frequency * displacement
            let envelope = exp(-frequency * time)
            nextDisplacement = (displacement + coefficient * time) * envelope
            velocity = (velocity - frequency * coefficient * time) * envelope
        }
        progress = target + nextDisplacement
        if progress <= 0 {
            progress = 0
            velocity = max(0, velocity)
        } else if progress >= Self.maximumProgress {
            progress = Self.maximumProgress
            velocity = min(0, velocity)
        }
        // Check speed as well as distance: crossing the resting size is not
        // the end of the bounce. Snap only the imperceptible remaining tail.
        if abs(progress - target) < 0.001, abs(velocity) < 0.02 {
            progress = target
            velocity = 0
        }
    }

    mutating func reset() {
        progress = 0
        velocity = 0
        target = 0
        isEngaged = false
        exitStartedAt = nil
    }
}

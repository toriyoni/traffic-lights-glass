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

    /// Size may overshoot, but the center finishes its approach before the
    /// bounce. Returning below 1 during settling must not move the center again.
    static func presentation(
        nativeFrames: [WindowAction: CGRect],
        expandedFrames: [WindowAction: CGRect],
        progress: CGFloat,
        windowFrame: CGRect
    ) -> Presentation? {
        guard isUsable(windowFrame), progress.isFinite else { return nil }
        let expanded = expandedFrames.filter { action, frame in
            isUsable(frame) && nativeFrames[action].map(isUsable) == true
        }
        let native = nativeFrames.filter { expanded[$0.key] != nil }
        guard let start = capsuleFrame(buttonFrames: native, padding: 0),
              let end = capsuleFrame(buttonFrames: expanded) else { return nil }
        var amount = min(GlassGroupRevealState.maximumProgress, max(0, progress))

        // Near a window edge, ease the overshoot toward the space available
        // around the resting center. Pushing the capsule sideways each frame
        // would reintroduce the very wobble that anchoring is meant to prevent.
        if amount > 1 {
            let horizontalRoom = 2 * min(end.midX - windowFrame.minX, windowFrame.maxX - end.midX)
            let verticalRoom = 2 * min(end.midY - windowFrame.minY, windowFrame.maxY - end.midY)
            let widthGrowth = end.width - start.width
            let heightGrowth = end.height - start.height
            var limit = CGFloat.infinity
            if widthGrowth > 0 { limit = min(limit, max(0, horizontalRoom - end.width) / widthGrowth) }
            if heightGrowth > 0 { limit = min(limit, max(0, verticalRoom - end.height) / heightGrowth) }
            if limit == 0 {
                amount = 1
            } else if limit.isFinite, amount - 1 > limit * 0.75 {
                let shoulder = limit * 0.75
                let remaining = limit - shoulder
                amount = 1 + shoulder + remaining * tanh((amount - 1 - shoulder) / remaining)
            }
        }

        let approach = min(amount / 0.9, 1)
        let placement = approach * approach * (3 - 2 * approach)
        let center = CGPoint(
            x: start.midX + (end.midX - start.midX) * placement,
            y: start.midY + (end.midY - start.midY) * placement
        )
        var result: [WindowAction: CGRect] = [:]
        for (action, expanded) in expanded {
            guard let native = nativeFrames[action], isUsable(native), isUsable(expanded) else { continue }
            result[action] = CGRect(
                x: native.minX + (expanded.minX - native.minX) * amount,
                y: native.minY + (expanded.minY - native.minY) * amount,
                width: native.width + (expanded.width - native.width) * amount,
                height: native.height + (expanded.height - native.height) * amount
            )
        }
        guard let interpolated = capsuleFrame(buttonFrames: result, padding: padding * amount) else { return nil }
        var offset = CGPoint(x: center.x - interpolated.midX, y: center.y - interpolated.midY)
        let centered = interpolated.offsetBy(dx: offset.x, dy: offset.y)

        // Keep the initial approach inside the window as well. Once the center
        // is at rest, the limited overshoot above already fits without shifting.
        if centered.width <= windowFrame.width {
            offset.x += min(max(centered.minX, windowFrame.minX), windowFrame.maxX - centered.width) - centered.minX
        }
        if centered.height <= windowFrame.height {
            offset.y += min(max(centered.minY, windowFrame.minY), windowFrame.maxY - centered.height) - centered.minY
        }
        return Presentation(
            buttonFrames: result.mapValues { $0.offsetBy(dx: offset.x, dy: offset.y) },
            capsuleFrame: interpolated.offsetBy(dx: offset.x, dy: offset.y)
        )
    }

    /// A stationary host for the entire animation, also used for occlusion.
    static func presentationEnvelope(
        nativeFrames: [WindowAction: CGRect],
        expandedFrames: [WindowAction: CGRect],
        windowFrame: CGRect
    ) -> CGRect? {
        guard let resting = capsuleFrame(buttonFrames: expandedFrames) else { return nil }
        let native = capsuleFrame(buttonFrames: nativeFrames) ?? resting
        let peak = presentation(
            nativeFrames: nativeFrames, expandedFrames: expandedFrames,
            progress: GlassGroupRevealState.maximumProgress, windowFrame: windowFrame
        )?.capsuleFrame ?? resting
        return resting.union(native).union(peak)
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

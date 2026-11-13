import CoreGraphics
import Foundation

/// Geometry is in the caller's coordinate space. Expanded frames use the
/// window-server space, whose origin is at the top-left of each window.
struct GlassGroupLayout {
    static let padding: CGFloat = 8
    static let gap: CGFloat = 8
    static let activationPadding: CGFloat = 10
    static let retentionPadding: CGFloat = 8
    static let maximumMagnification: CGFloat = 1.45
    static let maximumAttraction: CGFloat = 2
    static let capsuleAttraction: CGFloat = 0.25
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

    /// Enter a light's actual circular surface to select it. Gaps and capsule
    /// padding have no target, and distance never partially enlarges a neighbor.
    static func magnificationWeights(
        buttonFrames: [WindowAction: CGRect], pointer: CGPoint
    ) -> [WindowAction: CGFloat] {
        guard pointer.x.isFinite, pointer.y.isFinite else { return [:] }
        let selected = WindowAction.allCases.first { action in
            buttonFrames[action].map { contains(pointer, in: $0) } == true
        }
        return Dictionary(uniqueKeysWithValues: buttonFrames.keys.map { ($0, $0 == selected ? 1 : 0) })
    }

    static func contains(_ pointer: CGPoint, in frame: CGRect) -> Bool {
        guard isUsable(frame), pointer.x.isFinite, pointer.y.isFinite else { return false }
        return hypot((pointer.x - frame.midX) / (frame.width / 2),
                     (pointer.y - frame.midY) / (frame.height / 2)) <= 1
    }

    /// Measure against the selected state's unmagnetized target, not last
    /// frame's moving center. This prevents attraction from feeding itself.
    static func magneticOffsets(
        buttonFrames: [WindowAction: CGRect], weights: [WindowAction: CGFloat], pointer: CGPoint
    ) -> [WindowAction: CGPoint] {
        guard pointer.x.isFinite, pointer.y.isFinite else { return [:] }
        return Dictionary(uniqueKeysWithValues: buttonFrames.compactMap { action, frame in
            guard isUsable(frame), (weights[action] ?? 0) > 0 else { return nil }
            let dx = (pointer.x - frame.midX) / (frame.width / 2)
            let dy = (pointer.y - frame.midY) / (frame.height / 2)
            let scale = maximumAttraction / max(1, hypot(dx, dy))
            return (action, CGPoint(x: dx * scale, y: dy * scale))
        })
    }

    static func magnifiedFrames(
        restingFrames: [WindowAction: CGRect],
        weights: [WindowAction: CGFloat],
        windowFrame: CGRect,
        attractions: [WindowAction: CGPoint] = [:]
    ) -> [WindowAction: CGRect] {
        magnifiedPresentation(restingFrames: restingFrames, weights: weights,
                              windowFrame: windowFrame, attractions: attractions)?.buttonFrames ?? [:]
    }

    static func magnifiedPresentation(
        restingFrames: [WindowAction: CGRect], weights: [WindowAction: CGFloat],
        windowFrame: CGRect, attractions: [WindowAction: CGPoint] = [:]
    ) -> Presentation? {
        guard isUsable(windowFrame),
              let resting = capsuleFrame(buttonFrames: restingFrames) else { return nil }
        let actions = WindowAction.allCases.filter { restingFrames[$0].map(isUsable) == true }
        let growth = actions.map { action -> CGFloat in
            let frame = restingFrames[action]!
            let weight = weights[action].flatMap { $0.isFinite ? min(1, max(0, $0)) : nil } ?? 0
            return max(frame.width, frame.height) * (maximumMagnification - 1) * weight
        }
        let middle = actions.count / 2
        let odd = !actions.count.isMultiple(of: 2)
        let unmagnetized = Dictionary(uniqueKeysWithValues: actions.enumerated().map { index, action in
            let frame = restingFrames[action]!
            let diameter = max(frame.width, frame.height) + growth[index]
            let shift: CGFloat
            if odd && index == middle {
                shift = 0
            } else if index < middle {
                shift = -(growth[index] / 2 + growth[(index + 1)..<middle].reduce(0, +)
                          + (odd ? growth[middle] / 2 : 0))
            } else {
                let start = odd ? middle + 1 : middle
                shift = growth[index] / 2 + growth[start..<index].reduce(0, +)
                    + (odd ? growth[middle] / 2 : 0)
            }
            return (action, CGRect(x: frame.midX + shift - diameter / 2,
                                   y: frame.midY - diameter / 2, width: diameter, height: diameter))
        })
        let offsets = attractions.mapValues(clampedAttraction)
        let frames = unmagnetized.map { action, frame in
            let offset = offsets[action] ?? .zero
            return (action, frame.offsetBy(dx: offset.x, dy: offset.y))
        }
        let bodyOffset = offsets.filter { actions.contains($0.key) }.values.reduce(CGPoint.zero) {
            CGPoint(x: $0.x + $1.x * capsuleAttraction, y: $0.y + $1.y * capsuleAttraction)
        }
        guard let horizontal = capsuleFrame(buttonFrames: unmagnetized) else { return nil }
        let centerY = resting.midY + bodyOffset.y
        // Retain a real, symmetric capsule. Only a little extra height is needed
        // for the larger light; no local bulge or tapered side is constructed.
        let height = frames.reduce(resting.height + (growth.max() ?? 0) * 0.35) {
            max($0, 2 * (abs($1.1.midY - centerY) + $1.1.height / 2 + 4))
        }
        let capsule = CGRect(x: horizontal.minX + bodyOffset.x, y: centerY - height / 2,
                             width: horizontal.width, height: height)
        let inset = windowFrame.insetBy(dx: windowInset, dy: windowInset)
        let dx = capsule.width <= inset.width
            ? min(max(capsule.minX, inset.minX), inset.maxX - capsule.width) - capsule.minX : 0
        let dy = capsule.height <= inset.height
            ? min(max(capsule.minY, inset.minY), inset.maxY - capsule.height) - capsule.minY : 0
        return Presentation(buttonFrames: Dictionary(uniqueKeysWithValues: frames.map {
            ($0.0, $0.1.offsetBy(dx: dx, dy: dy))
        }), capsuleFrame: capsule.offsetBy(dx: dx, dy: dy))
    }

    /// Interpolate position and size together so every button travels directly
    /// toward its target. Timing is eased once by GlassGroupRevealState.
    static func presentation(
        nativeFrames: [WindowAction: CGRect],
        expandedFrames: [WindowAction: CGRect],
        progress: CGFloat,
        windowFrame: CGRect,
        magnification: [WindowAction: CGFloat] = [:],
        attractions: [WindowAction: CGPoint] = [:]
    ) -> Presentation? {
        guard isUsable(windowFrame), progress.isFinite else { return nil }
        let amount = min(1, max(0, progress))
        var result: [WindowAction: CGRect] = [:]
        guard let target = magnifiedPresentation(restingFrames: expandedFrames, weights: magnification,
                windowFrame: windowFrame, attractions: attractions),
              let nativeCapsule = capsuleFrame(buttonFrames: nativeFrames, padding: 0) else { return nil }
        for (action, expanded) in target.buttonFrames {
            guard let native = nativeFrames[action], isUsable(native), isUsable(expanded) else { continue }
            result[action] = CGRect(
                x: native.minX + (expanded.minX - native.minX) * amount,
                y: native.minY + (expanded.minY - native.minY) * amount,
                width: native.width + (expanded.width - native.width) * amount,
                height: native.height + (expanded.height - native.height) * amount
            )
        }
        let capsule = CGRect(
            x: nativeCapsule.minX + (target.capsuleFrame.minX - nativeCapsule.minX) * amount,
            y: nativeCapsule.minY + (target.capsuleFrame.minY - nativeCapsule.minY) * amount,
            width: nativeCapsule.width + (target.capsuleFrame.width - nativeCapsule.width) * amount,
            height: nativeCapsule.height + (target.capsuleFrame.height - nativeCapsule.height) * amount
        )
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

    /// Reserve the maximum magnified size once, so the host never rounds or
    /// shifts as different buttons grow. Only the views inside it deform.
    static func presentationEnvelope(
        nativeFrames: [WindowAction: CGRect],
        expandedFrames: [WindowAction: CGRect],
        windowFrame: CGRect
    ) -> CGRect? {
        guard isUsable(windowFrame), let resting = capsuleFrame(buttonFrames: expandedFrames) else { return nil }
        let native = capsuleFrame(buttonFrames: nativeFrames) ?? resting
        let maximum = magnifiedPresentation(
            restingFrames: expandedFrames,
            weights: Dictionary(uniqueKeysWithValues: expandedFrames.keys.map { ($0, CGFloat(1)) }),
            windowFrame: windowFrame
        )
        return resting.union(native).union(maximum?.capsuleFrame ?? resting)
            .insetBy(dx: -maximumAttraction * 3, dy: -maximumAttraction * 3)
    }

    static func clampedAttraction(_ point: CGPoint) -> CGPoint {
        guard point.x.isFinite, point.y.isFinite else { return .zero }
        let scale = min(1, maximumAttraction / max(0.0001, hypot(point.x, point.y)))
        return CGPoint(x: point.x * scale, y: point.y * scale)
    }

    private static func isUsable(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isInfinite &&
            frame.minX.isFinite && frame.minY.isFinite &&
            frame.width.isFinite && frame.height.isFinite &&
            frame.width > 0 && frame.height > 0
    }
}

/// Frame-rate independent ease-out between discrete hover states.
/// Each step stays between the current and target values: no momentum, overshoot
/// or rebound when the pointer changes direction. Exact settling releases timers.
struct GlassMagnificationState {
    static let responseTime: TimeInterval = 0.045
    private static let settlingTolerance: CGFloat = 0.0001
    private(set) var weights: [WindowAction: CGFloat] = [:]
    private(set) var attractions: [WindowAction: CGPoint] = [:]
    private var targets: [WindowAction: CGFloat] = [:]
    private var targetAttractions: [WindowAction: CGPoint] = [:]

    var isAnimating: Bool {
        WindowAction.allCases.contains { (weights[$0] ?? 0) != (targets[$0] ?? 0) }
            || WindowAction.allCases.contains { (attractions[$0] ?? .zero) != (targetAttractions[$0] ?? .zero) }
    }
    var isMagnified: Bool { weights.values.contains { $0 > 0 } }

    mutating func advance(
        targetWeights: [WindowAction: CGFloat], elapsed: TimeInterval, reduceMotion: Bool,
        targetAttractions: [WindowAction: CGPoint] = [:]
    ) {
        targets = Dictionary(uniqueKeysWithValues: WindowAction.allCases.map { action in
            let value = targetWeights[action].flatMap { $0.isFinite ? min(1, max(0, $0)) : nil } ?? 0
            return (action, value)
        })
        self.targetAttractions = Dictionary(uniqueKeysWithValues: WindowAction.allCases.map { action in
            (action, (targets[action] ?? 0) > 0
                ? GlassGroupLayout.clampedAttraction(targetAttractions[action] ?? .zero) : .zero)
        })
        if reduceMotion {
            weights = targets
            attractions = self.targetAttractions
            return
        }
        guard elapsed.isFinite, elapsed > 0 else { return }
        let blend = CGFloat(-expm1(-elapsed / Self.responseTime))
        for action in WindowAction.allCases {
            let target = targets[action] ?? 0
            let current = weights[action] ?? 0
            let next = current + (target - current) * blend
            weights[action] = abs(next - target) < Self.settlingTolerance ? target : next
            let position = attractions[action] ?? .zero
            let goal = self.targetAttractions[action] ?? .zero
            let moved = CGPoint(x: position.x + (goal.x - position.x) * blend,
                                y: position.y + (goal.y - position.y) * blend)
            attractions[action] = hypot(moved.x - goal.x, moved.y - goal.y) < 0.001 ? goal : moved
        }
    }

    mutating func reset() {
        weights.removeAll(keepingCapacity: true)
        targets.removeAll(keepingCapacity: true)
        attractions.removeAll(keepingCapacity: true)
        targetAttractions.removeAll(keepingCapacity: true)
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

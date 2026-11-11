import CoreGraphics
import Foundation

/// One convex glass envelope, rather than a union of circular lobes. Supporting
/// tangents join the padded buttons and a single pressure point; a smooth maximum
/// rounds their transitions without introducing a waist between the lights.
struct GlassBubbleOutline {
    // The pressure offset, extra radius and smoothing together stay below this
    // allowance. Reserve it in the stationary host, never resize that host on hover.
    static let maximumOutset: CGFloat = GlassGroupLayout.padding * 0.5

    let path: CGPath
    var bounds: CGRect { path.boundingBoxOfPath }

    init(
        buttonFrames: [WindowAction: CGRect],
        capsuleFrame: CGRect,
        padding: CGFloat,
        pointer: CGPoint?,
        strength: CGFloat
    ) {
        let amount = strength.isFinite ? min(1, max(0, strength)) : 0
        let pad = padding.isFinite ? min(GlassGroupLayout.padding, max(0, padding)) : 0
        let frames = WindowAction.allCases.compactMap { buttonFrames[$0] }.filter {
            !$0.isEmpty && !$0.isInfinite && !$0.isNull
        }
        guard amount > 0, pad > 0, let pointer,
              pointer.x.isFinite, pointer.y.isFinite,
              let first = frames.first, let last = frames.last else {
            let radius = min(capsuleFrame.width, capsuleFrame.height) / 2
            path = CGPath(roundedRect: capsuleFrame, cornerWidth: radius, cornerHeight: radius, transform: nil)
            return
        }

        // Work near the origin to keep the tangent intersections precise even
        // on distant displays. Each disk includes the button's clear padding.
        let origin = CGPoint(x: capsuleFrame.midX, y: capsuleFrame.midY)
        var disks = frames.map {
            Disk(center: CGPoint(x: $0.midX - origin.x, y: $0.midY - origin.y),
                 radius: max($0.width, $0.height) / 2 + pad)
        }
        let centerY = frames.reduce(CGFloat(0)) { $0 + $1.midY } / CGFloat(frames.count)
        let pressure = CGPoint(
            x: min(max(pointer.x, first.midX), last.midX) - origin.x,
            y: centerY - origin.y + min(pad, max(-pad, pointer.y - centerY)) * 0.20 * amount
        )
        disks.append(Disk(center: pressure, radius: disks.map(\.radius).max()! + pad * 0.12 * amount))
        let softness = pad * 0.09 * amount

        // Intersect successive supporting lines, then round the resulting convex
        // polygon with tangent-continuous quadratics. This stays smooth at the
        // joins, including where the largest light changes as the pointer moves.
        let samples = 128
        let step = 2 * CGFloat.pi / CGFloat(samples)
        let normals = (0..<samples).map { index in
            CGPoint(x: cos(CGFloat(index) * step), y: sin(CGFloat(index) * step))
        }
        let supports = normals.map { normal -> CGFloat in
            let values = disks.map { $0.center.x * normal.x + $0.center.y * normal.y + $0.radius }
            let largest = values.max()!
            return largest + softness * log(values.reduce(CGFloat(0)) { $0 + exp(($1 - largest) / softness) })
        }
        let vertices = (0..<samples).map { index -> CGPoint in
            let next = (index + 1) % samples
            let a = normals[index], b = normals[next]
            let determinant = a.x * b.y - a.y * b.x
            return CGPoint(
                x: (supports[index] * b.y - supports[next] * a.y) / determinant + origin.x,
                y: (supports[next] * a.x - supports[index] * b.x) / determinant + origin.y
            )
        }
        let outline = CGMutablePath()
        outline.move(to: Self.midpoint(vertices.last!, vertices[0]))
        for index in 0..<samples {
            outline.addQuadCurve(to: Self.midpoint(vertices[index], vertices[(index + 1) % samples]),
                                 control: vertices[index])
        }
        outline.closeSubpath()
        path = outline
    }

    private struct Disk {
        let center: CGPoint
        let radius: CGFloat
    }

    private static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }
}

import CoreGraphics
import Foundation

/// A true capsule swept between the two end-light centers. Moving one end
/// tilts the capsule very slightly, without changing either circular endcap.
struct GlassCapsuleGeometry {
    let start: CGPoint
    let end: CGPoint
    let radius: CGFloat

    var frame: CGRect {
        CGRect(x: min(start.x, end.x) - radius, y: min(start.y, end.y) - radius,
               width: abs(end.x - start.x) + radius * 2,
               height: abs(end.y - start.y) + radius * 2)
    }

    var path: CGPath {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length = hypot(end.x - start.x, end.y - start.y)
        var transform = CGAffineTransform(a: cos(angle), b: sin(angle), c: -sin(angle), d: cos(angle),
                                          tx: start.x, ty: start.y)
        return CGPath(roundedRect: CGRect(x: -radius, y: -radius, width: length + radius * 2, height: radius * 2),
                      cornerWidth: radius, cornerHeight: radius, transform: &transform)
    }

    func offsetBy(dx: CGFloat, dy: CGFloat) -> Self {
        Self(start: CGPoint(x: start.x + dx, y: start.y + dy),
             end: CGPoint(x: end.x + dx, y: end.y + dy), radius: radius)
    }
}

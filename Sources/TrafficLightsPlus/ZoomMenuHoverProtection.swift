import AppKit

/// Retention only: these regions never become clickable window content.
struct ZoomMenuHoverProtection {
    static let approachDuration: TimeInterval = 0.35
    static let edgeDuration: TimeInterval = 0.18
    static let edgePadding: CGFloat = 6

    private enum Departure { case approach, edge }
    private var previousPoint: CGPoint?
    private var lastSafePointWasInMenu = false
    private var departure: Departure?
    private(set) var deadline: TimeInterval?

    mutating func reset(at point: CGPoint) {
        self = Self()
        previousPoint = point
    }

    mutating func retain(
        at point: CGPoint, source: CGRect, placement: ZoomMenuPlacement,
        overOtherControl: Bool, now: TimeInterval
    ) -> Bool {
        defer { previousPoint = point }
        if overOtherControl { deadline = nil; return false }
        let inMenu = placement.containsMenu(point)
        if inMenu || GlassGroupLayout.contains(point, in: source) {
            deadline = nil
            departure = nil
            lastSafePointWasInMenu = inMenu
            return true
        }
        guard let previousPoint else { return false }

        if lastSafePointWasInMenu && placement.containsMenuEdge(point, padding: Self.edgePadding) {
            if departure != .edge {
                departure = .edge
                deadline = now + Self.edgeDuration
            }
            return now < (deadline ?? now)
        }

        let towardMenu = placement.belowAnchor ? previousPoint.y - point.y : point.y - previousPoint.y
        let inApproach = placement.containsApproach(point, source: source)
            || (departure == .approach && placement.containsMenuEdge(point, padding: Self.edgePadding))
        if inApproach, towardMenu >= -1.5,
           towardMenu > 0.3 || departure == .approach {
            if departure != .approach {
                departure = .approach
                deadline = now + Self.approachDuration
            }
            // Do not renew on every mouse event: stopping in empty space or
            // oscillating near the edge must not leave a permanent popup.
            return now < (deadline ?? now)
        }
        deadline = nil
        return false
    }
}

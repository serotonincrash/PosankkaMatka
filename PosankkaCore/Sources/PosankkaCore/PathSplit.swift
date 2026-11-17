import Foundation
import FoliBusAPI

extension Array where Element == Foli.Coordinate {
    /// Splits at the point on the line nearest `coordinate`; that point ends
    /// `travelled` and starts `remaining`. Segments before `start` are skipped,
    /// so a loop's earlier pass isn't chosen.
    public func split(
        at coordinate: Foli.Coordinate,
        searchingFrom start: Int = 0
    ) -> (travelled: [Foli.Coordinate], remaining: [Foli.Coordinate]) {
        guard let hit = nearestSegment(to: coordinate, searchingFrom: start) else {
            return ([], self)
        }
        return (Array(self[...hit.index]) + [hit.point], [hit.point] + self[(hit.index + 1)...])
    }

    /// Nearest segment (from `index` to `index + 1`) and the projected point.
    /// Planar with longitude scaled by latitude: fine at city scale.
    func nearestSegment(
        to coordinate: Foli.Coordinate,
        searchingFrom start: Int = 0
    ) -> (index: Int, point: Foli.Coordinate)? {
        guard count >= 2 else { return nil }
        let scale = cos(coordinate.latitude * .pi / 180)
        let px = coordinate.longitude * scale, py = coordinate.latitude
        var best: (index: Int, point: Foli.Coordinate, distance: Double)?
        for i in Swift.min(Swift.max(0, start), count - 2)..<(count - 1) {
            let a = self[i], b = self[i + 1]
            let ax = a.longitude * scale, ay = a.latitude
            let dx = b.longitude * scale - ax, dy = b.latitude - ay
            let lengthSquared = dx * dx + dy * dy
            let t = lengthSquared == 0 ? 0 : Swift.min(1, Swift.max(0, ((px - ax) * dx + (py - ay) * dy) / lengthSquared))
            let qx = ax + t * dx, qy = ay + t * dy
            let distance = (px - qx) * (px - qx) + (py - qy) * (py - qy)
            if distance < (best?.distance ?? .infinity) {
                let point = Foli.Coordinate(
                    latitude: a.latitude + t * (b.latitude - a.latitude),
                    longitude: a.longitude + t * (b.longitude - a.longitude)
                )
                best = (i, point, distance)
            }
        }
        return best.map { ($0.index, $0.point) }
    }
}

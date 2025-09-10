import Foundation
import MapKit

@MainActor
extension RoutingViewModel {
    var etaString: String {
        guard let seconds = route?.expectedTravelTime else { return "--" }
        let minutes = Int(ceil(seconds/60))
        return "\(minutes)m"
    }

    func calculateConsideringReports(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D, avoid reports: [TrafficReport]) async {
        await calculateRoute(from: start, to: end)
        guard let base = route else { return }
        if intersectsIncident(route: base, reports: reports) {
            // Try two simple detours: offset midpoint perpendicular by ~300m
            let mid = midpoint(of: base.polyline)
            let offsets = detourPoints(around: mid, meters: 300)
            var best: MKRoute? = base
            for detour in offsets {
                let first = await calc(from: start, to: detour)
                let second = await calc(from: detour, to: end)
                if let f = first, let s = second {
                    let combinedTime = f.expectedTravelTime + s.expectedTravelTime
                    if combinedTime < (best?.expectedTravelTime ?? .greatestFiniteMagnitude) {
                        best = mergeRoutes([f, s])
                    }
                }
            }
            await MainActor.run { self.route = best }
        }
    }

    private func calc(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async -> MKRoute? {
        let req = MKDirections.Request()
        req.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        req.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        req.transportType = .automobile
        do { return try await MKDirections(request: req).calculate().routes.first } catch { return nil }
    }

    private func intersectsIncident(route: MKRoute, reports: [TrafficReport]) -> Bool {
        let coords = route.polyline.toCoordinates()
        for r in reports where r.type == .closed || r.type == .crash {
            for c in coords {
                if CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude).distance(to: r.coordinate) < 50 {
                    return true
                }
            }
        }
        return false
    }

    private func midpoint(of polyline: MKPolyline) -> CLLocationCoordinate2D {
        let coords = polyline.toCoordinates()
        guard let first = coords.first, let last = coords.last else { return kCLLocationCoordinate2DInvalid }
        return CLLocationCoordinate2D(latitude: (first.latitude + last.latitude)/2, longitude: (first.longitude + last.longitude)/2)
    }

    private func detourPoints(around coordinate: CLLocationCoordinate2D, meters: CLLocationDistance) -> [CLLocationCoordinate2D] {
        // Roughly convert meters to degrees
        let latDelta = meters / 111_000
        let lonDelta = meters / (111_000 * cos(coordinate.latitude * .pi / 180))
        return [
            CLLocationCoordinate2D(latitude: coordinate.latitude + latDelta, longitude: coordinate.longitude + lonDelta),
            CLLocationCoordinate2D(latitude: coordinate.latitude - latDelta, longitude: coordinate.longitude - lonDelta)
        ]
    }

    private func mergeRoutes(_ routes: [MKRoute]) -> MKRoute? {
        // Simple pick the last as carrier; in UI we only use polyline and expected time
        return routes.last
    }
}


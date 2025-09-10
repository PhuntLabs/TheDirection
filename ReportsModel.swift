import SwiftUI
import MapKit

enum ReportType: String, CaseIterable, Identifiable {
    case police = "Police Officer"
    case sideCar = "Car on side"
    case crash = "Crash"
    case closed = "Closed Road"
    var id: String { rawValue }

    var color: Color {
        switch self {
        case .police: return .blue
        case .sideCar: return .orange
        case .crash: return .red
        case .closed: return .purple
        }
    }

    var symbol: String {
        switch self {
        case .police: return "light.beacon.max"
        case .sideCar: return "car.side"
        case .crash: return "car.rear"
        case .closed: return "road.lanes"
        }
    }
}

struct TrafficReport: Identifiable, Equatable {
    let id: UUID
    let type: ReportType
    let coordinate: CLLocationCoordinate2D
    let createdAt: Date
    var confirmations: Int
    var denials: Int
    var expiresAt: Date

    var isActive: Bool { Date() < expiresAt }
}

@MainActor
final class ReportsManager: ObservableObject {
    @Published private(set) var reports: [TrafficReport] = []
    private var cleanupTimer: Timer?

    init() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.purgeExpired()
        }
    }

    func addReport(type: ReportType, at coordinate: CLLocationCoordinate2D) {
        let now = Date()
        let report = TrafficReport(id: UUID(), type: type, coordinate: coordinate, createdAt: now, confirmations: 0, denials: 0, expiresAt: now.addingTimeInterval(60*30))
        reports.append(report)
    }

    func confirm(report: TrafficReport, isTrue: Bool, settings: AppSettings) {
        guard let index = reports.firstIndex(of: report) else { return }
        if isTrue {
            reports[index].confirmations += 1
            // extend expiry when confirmed
            reports[index].expiresAt = Date().addingTimeInterval(60*30)
            settings.reputationScore += 2
        } else {
            reports[index].denials += 1
            settings.reputationScore = max(0, settings.reputationScore - 1)
            // if too many denials, expire immediately
            if reports[index].denials >= 2 {
                reports[index].expiresAt = Date().addingTimeInterval(-1)
            }
        }
        purgeExpired()
    }

    func purgeExpired() {
        reports.removeAll { !$0.isActive }
    }
}

extension CLLocationCoordinate2D {
    func distance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        let a = CLLocation(latitude: latitude, longitude: longitude)
        let b = CLLocation(latitude: other.latitude, longitude: other.longitude)
        return a.distance(from: b)
    }
}


import SwiftUI
import MapKit

struct ReportsView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var locationManager = LocationManager()
    @EnvironmentObject private var reports: ReportsManager

    var body: some View {
        NavigationView {
            List {
                Section(header: Text(settings.localized(.trafficReports))) {
                    ForEach(reports.reports) { report in
                        HStack(spacing: 12) {
                            Image(systemName: report.type.symbol).foregroundStyle(report.type.color)
                            VStack(alignment: .leading) {
                                Text(report.type.rawValue)
                                Text("Conf: \(report.confirmations)  •  No: \(report.denials)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let user = locationManager.currentLocation?.coordinate {
                                let d = user.distance(to: report.coordinate)
                                Text("\(Int(d)) m").font(.caption)
                            }
                        }
                    }
                }
            }
            .navigationTitle(settings.localized(.reportsTab))
        }
    }
}


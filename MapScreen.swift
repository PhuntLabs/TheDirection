import SwiftUI
import MapKit

struct MapScreen: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var locationManager = LocationManager()
    @StateObject private var searchVM = SearchViewModel()
    @StateObject private var routingVM = RoutingViewModel()
    @EnvironmentObject private var reports: ReportsManager

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var wavePhase: CGFloat = 0
    @State private var showingNearbySheet: Bool = false
    @State private var showingReportSheet: Bool = false
    @State private var newReportType: ReportType = .police
    @State private var selectedReport: TrafficReport? = nil
    @State private var etaTimer: Timer? = nil

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.black, Color(red: 0.06, green: 0.02, blue: 0.10)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            Map(position: $cameraPosition, interactionModes: [.all]) {
                if let coord = locationManager.currentLocation?.coordinate {
                    MapAnnotation(coordinate: coord) { PulsingDot() }
                }

                ForEach(searchVM.nearbyMapItems, id: \.
self) { item in
                    if let coordinate = item.placemark.location?.coordinate {
                        MapAnnotation(coordinate: coordinate) {
                            CategoryMarkerView(category: searchVM.selectedCategory, title: item.name ?? "")
                                .onTapGesture {
                                    Task { @MainActor in
                                        searchVM.selectedDestination = item
                                        if let user = locationManager.currentLocation?.coordinate {
                                            await routingVM.calculateConsideringReports(from: user, to: coordinate, avoid: visibleReports())
                                        }
                                    }
                                }
                        }
                    }
                }

                if let destination = searchVM.selectedDestination, let coordinate = destination.placemark.location?.coordinate {
                    MapAnnotation(coordinate: coordinate) { DestinationMarkerView(title: destination.name ?? "Destination") }
                }

                // Traffic reports nearby (within ~0.5 miles)
                ForEach(visibleReports()) { report in
                    MapAnnotation(coordinate: report.coordinate) {
                        VStack(spacing: 4) {
                            Image(systemName: report.type.symbol)
                                .foregroundStyle(report.type.color)
                                .padding(6)
                                .background(.ultraThinMaterial, in: Circle())
                                .shadow(color: report.type.color.opacity(0.8), radius: 6)
                                .onTapGesture { selectedReport = report }
                            Text(report.type.rawValue).font(.caption2)
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .ignoresSafeArea()
            .onChange(of: locationManager.currentLocation) { _, newLoc in
                guard let c = newLoc?.coordinate else { return }
                withAnimation(.easeInOut(duration: 0.8)) {
                    cameraPosition = .region(MKCoordinateRegion(center: c, latitudinalMeters: 1200, longitudinalMeters: 1200))
                }
            }
            .onChange(of: searchVM.selectedDestination) { _, dest in
                // Start/stop ETA timer based on whether a destination is active
                etaTimer?.invalidate()
                guard dest != nil else { return }
                etaTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in
                    Task { @MainActor in
                        guard let destCoord = searchVM.selectedDestination?.placemark.location?.coordinate,
                              let user = locationManager.currentLocation?.coordinate else { return }
                        await routingVM.calculateConsideringReports(from: user, to: destCoord, avoid: visibleReports())
                    }
                }
            }

            VStack(spacing: 0) {
                SineWave(phase: wavePhase, amplitude: 10, frequency: 2)
                    .stroke(LinearGradient(colors: [Color.cyan, Color.purple], startPoint: .leading, endPoint: .trailing), lineWidth: 3)
                    .frame(height: 40)
                    .blur(radius: 0.5)
                    .shadow(color: Color.cyan.opacity(0.9), radius: 4)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .onAppear { withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) { wavePhase = .pi * 2 } }
                Spacer()
            }

            VStack(spacing: 12) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Color.cyan)
                        TextField(settings.localized(.searchPlaceholder), text: $searchVM.searchText)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .onChange(of: searchVM.searchText) { _, text in searchVM.updateCompletions(for: text) }
                        if !searchVM.searchText.isEmpty {
                            Button(action: { searchVM.searchText = ""; searchVM.completions = [] }) {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(LinearGradient(colors: [Color.purple.opacity(0.8), Color.cyan.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1).shadow(color: Color.cyan.opacity(0.5), radius: 3) }

                    Button { showingNearbySheet = true } label: {
                        Image(systemName: "location.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .font(.title3)
                            .foregroundStyle(Color.purple)
                            .shadow(color: Color.purple.opacity(0.8), radius: 6)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

                if !searchVM.completions.isEmpty {
                    AutocompleteList(completions: searchVM.completions) { completion in
                        Task { @MainActor in
                            if let item = await searchVM.performAutocompleteSelection(completion), let coord = item.placemark.location?.coordinate {
                                withAnimation(.spring(response: 0.6, dampingFraction: 0.9)) {
                                    cameraPosition = .region(MKCoordinateRegion(center: coord, latitudinalMeters: 1500, longitudinalMeters: 1500))
                                }
                                if let user = locationManager.currentLocation?.coordinate {
                                    await routingVM.calculateConsideringReports(from: user, to: coord, avoid: visibleReports())
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                Spacer()
            }

            if let polyline = routingVM.route?.polyline {
                GlowingRoute(coordinates: polyline.toCoordinates()).allowsHitTesting(false).padding(16)
                // ETA badge
                VStack { HStack { Spacer(); Text("\(settings.localized(.eta)): \(routingVM.etaString)")
                        .padding(8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.trailing, 16)
                    }
                    Spacer() }
                    .allowsHitTesting(false)
            }

            if let sr = selectedReport {
                VStack {
                    Spacer()
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(settings.localized(.confirmStillThere)).font(.headline)
                            HStack(spacing: 12) {
                                Button(settings.localized(.yes)) { reports.confirm(report: sr, isTrue: true, settings: settings); selectedReport = nil }
                                    .buttonStyle(.borderedProminent)
                                Button(settings.localized(.no)) { reports.confirm(report: sr, isTrue: false, settings: settings); selectedReport = nil }
                                    .buttonStyle(.bordered)
                            }
                        }
                        Spacer()
                        Button(action: { selectedReport = nil }) { Image(systemName: "xmark.circle.fill").font(.title2) }
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            VStack {
                Spacer()
                HStack {
                    Button {
                        showingReportSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus"); Text(settings.localized(.submitReport))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
        }
        .sheet(isPresented: $showingNearbySheet) {
            NearbySheetView(selected: searchVM.selectedCategory) { category in
                if let user = locationManager.currentLocation?.coordinate { Task { await searchVM.fetchNearby(for: category, around: user) } }
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showingReportSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text(settings.localized(.trafficReports)).font(.headline)
                Picker("Type", selection: $newReportType) {
                    ForEach(ReportType.allCases) { t in Text(t.rawValue).tag(t) }
                }.pickerStyle(.wheel)
                Button(settings.localized(.submitReport)) {
                    if let user = locationManager.currentLocation?.coordinate { reports.addReport(type: newReportType, at: user) }
                    settings.reputationScore += 3
                    showingReportSheet = false
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }
            .padding()
            .presentationDetents([.medium])
        }
        .task(id: searchVM.selectedDestination) {
            guard let dest = searchVM.selectedDestination?.placemark.location?.coordinate, let user = locationManager.currentLocation?.coordinate else { return }
            await routingVM.calculateConsideringReports(from: user, to: dest, avoid: visibleReports())
        }
        .onChange(of: reports.reports) { _, _ in
            // Recompute if there is an active destination when reports change (dynamic ETA & detours)
            Task { @MainActor in
                guard let dest = searchVM.selectedDestination?.placemark.location?.coordinate,
                      let user = locationManager.currentLocation?.coordinate else { return }
                await routingVM.calculateConsideringReports(from: user, to: dest, avoid: visibleReports())
            }
        }
        .onDisappear {
            etaTimer?.invalidate(); etaTimer = nil
        }
    }

    private func visibleReports() -> [TrafficReport] {
        guard let user = locationManager.currentLocation?.coordinate else { return [] }
        return reports.reports.filter { $0.isActive && $0.coordinate.distance(to: user) <= 804.67 }
    }
}


import SwiftUI
import MapKit
import CoreLocation

// ContentView.swift
// Single-file SwiftUI prototype implementing:
// PHASE 1: Base Map + Wave Animation Demo
// PHASE 2: Search + Nearby Places (autocomplete + categories + animated markers)
// PHASE 3: Wave-Like Directions (routing + glowing animated route + bottom sheet)

// MARK: - Location Manager (User Authorization + Updates)
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        // Request When-In-Use; the app should add NSLocationWhenInUseUsageDescription in Info.plist
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            self.manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        currentLocation = loc
    }
}

// MARK: - Phase 1 Wave Demo Shape
struct SineWave: Shape {
    // Animated phase to create traveling wave effect
    var phase: CGFloat
    // Wave height (amplitude) and frequency
    var amplitude: CGFloat
    var frequency: CGFloat

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        let width = rect.width
        path.move(to: CGPoint(x: 0, y: midY))
        let step: CGFloat = 2
        for x in stride(from: 0 as CGFloat, to: width + 1, by: step) {
            let relativeX = x / width
            let y = midY + sin((relativeX * .pi * 2 * frequency) + phase) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
        }
        return path
    }
}

// MARK: - Category Model for Nearby Places
enum POICategory: String, CaseIterable, Identifiable {
    case restaurants = "Restaurants"
    case cafes = "Cafes"
    case parks = "Parks"
    case gas = "Gas Stations"
    var id: String { rawValue }

    // Unique color per category (vibrant for dark mode)
    var color: Color {
        switch self {
        case .restaurants: return Color(red: 0.20, green: 0.90, blue: 0.80) // electric aqua
        case .cafes: return Color(red: 0.85, green: 0.40, blue: 1.00) // deep purple/magenta
        case .parks: return Color(red: 0.30, green: 0.95, blue: 0.50) // neon green
        case .gas: return Color(red: 1.00, green: 0.55, blue: 0.35) // neon orange
        }
    }

    // Native MapKit category when available; fallback to query
    var mkCategory: MKPointOfInterestCategory? {
        switch self {
        case .restaurants: return .restaurant
        case .cafes: return .cafe
        case .parks: return .park
        case .gas: return .gasStation
        }
    }

    var query: String {
        switch self {
        case .restaurants: return "restaurants"
        case .cafes: return "cafes"
        case .parks: return "parks"
        case .gas: return "gas stations"
        }
    }
}

// MARK: - Search + Nearby ViewModel
@MainActor
final class SearchViewModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var searchText: String = ""
    @Published var completions: [MKLocalSearchCompletion] = []
    @Published var isShowingNearbySheet: Bool = false
    @Published var selectedCategory: POICategory? = nil
    @Published var nearbyMapItems: [MKMapItem] = []
    @Published var selectedDestination: MKMapItem? = nil

    private let completer: MKLocalSearchCompleter = MKLocalSearchCompleter()
    private var searchTask: Task<Void, Never>? = nil

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func updateCompletions(for text: String) {
        // Debounce updates to avoid spamming the completer
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.completer.queryFragment = text
            }
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        completions = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        // On error, clear results
        completions = []
    }

    func performAutocompleteSelection(_ completion: MKLocalSearchCompletion) async -> MKMapItem? {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            // Choose the first result as the destination
            let item = response.mapItems.first
            await MainActor.run { self.selectedDestination = item }
            return item
        } catch {
            return nil
        }
    }

    func fetchNearby(for category: POICategory, around coordinate: CLLocationCoordinate2D) async {
        selectedCategory = category
        // Prefer PointsOfInterestRequest when category is available
        if let mkCat = category.mkCategory {
            let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: 3000)
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: [mkCat])
            do {
                let response = try await MKLocalSearch(request: MKLocalSearch.Request(pointsOfInterestRequest: request)).start()
                await MainActor.run { self.nearbyMapItems = response.mapItems }
                return
            } catch {
                // Fallback to query below
            }
        }

        // Fallback: plain text search
        var region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 5000, longitudinalMeters: 5000)
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = category.query
        request.resultTypes = [.pointOfInterest]
        request.region = region
        do {
            let response = try await MKLocalSearch(request: request).start()
            await MainActor.run { self.nearbyMapItems = response.mapItems }
        } catch {
            await MainActor.run { self.nearbyMapItems = [] }
        }
    }
}

// MARK: - Routing ViewModel (Phase 3)
@MainActor
final class RoutingViewModel: ObservableObject {
    @Published var route: MKRoute? = nil
    @Published var steps: [MKRoute.Step] = []
    @Published var isShowingDirectionsSheet: Bool = false

    func calculateRoute(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) async {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
        request.transportType = .automobile
        do {
            let response = try await MKDirections(request: request).calculate()
            let route = response.routes.first
            await MainActor.run {
                self.route = route
                self.steps = route?.steps.filter { !$0.instructions.isEmpty } ?? []
                self.isShowingDirectionsSheet = route != nil
            }
        } catch {
            await MainActor.run {
                self.route = nil
                self.steps = []
                self.isShowingDirectionsSheet = false
            }
        }
    }
}

// MARK: - Animated Pulsing Dot for Current Location
struct PulsingDot: View {
    var color: Color = Color(red: 0.20, green: 0.90, blue: 0.80)
    @State private var pulse: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.25))
                .frame(width: 80, height: 80)
                .scaleEffect(pulse ? 1.2 : 0.8)
                .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: pulse)
            Circle()
                .stroke(color.opacity(0.8), lineWidth: 2)
                .blur(radius: 2)
                .frame(width: 34, height: 34)
                .shadow(color: color.opacity(0.9), radius: 8, x: 0, y: 0)
            Circle()
                .fill(Color.white)
                .frame(width: 10, height: 10)
        }
        .onAppear { pulse = true }
    }
}

// MARK: - Animated Glowing Route Shape (Phase 3)
struct GlowingRoute: View {
    let coordinates: [CLLocationCoordinate2D]
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let path = routePath(in: proxy.frame(in: .local))
            // Base blurred glow stroke
            path
                .stroke(LinearGradient(colors: [Color.purple, Color.cyan], startPoint: .leading, endPoint: .trailing), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                .blur(radius: 6)
                .opacity(0.6)
            // Animated wave overlay using dashed phase shift
            path
                .trim(from: 0, to: 1)
                .stroke(AngularGradient(colors: [Color.cyan, Color.purple, Color.cyan], center: .center), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: [12, 10], dashPhase: phase))
                .shadow(color: Color.cyan.opacity(0.8), radius: 6)
                .onAppear {
                    withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                        phase = 22
                    }
                }
        }
    }

    private func routePath(in rect: CGRect) -> Path {
        // Convert geo coordinates into a simple local path by normalizing to bounds
        guard let first = coordinates.first else { return Path() }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for c in coordinates {
            minLat = min(minLat, c.latitude)
            maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude)
            maxLon = max(maxLon, c.longitude)
        }
        let latSpan = max(maxLat - minLat, 0.000001)
        let lonSpan = max(maxLon - minLon, 0.000001)

        func point(for coord: CLLocationCoordinate2D) -> CGPoint {
            let x = CGFloat((coord.longitude - minLon) / lonSpan) * rect.width
            let y = rect.height - CGFloat((coord.latitude - minLat) / latSpan) * rect.height
            return CGPoint(x: x, y: y)
        }

        var path = Path()
        var isFirst = true
        for c in coordinates {
            let p = point(for: c)
            if isFirst {
                path.move(to: p)
                isFirst = false
            } else {
                path.addLine(to: p)
            }
        }
        return path
    }
}

// MARK: - Main ContentView
struct ContentView: View {
    // Managers / ViewModels
    @StateObject private var locationManager = LocationManager()
    @StateObject private var searchVM = SearchViewModel()
    @StateObject private var routingVM = RoutingViewModel()

    // Map camera state (iOS 17+) to control camera programmatically
    @State private var cameraPosition: MapCameraPosition = .automatic

    // Wave animation state
    @State private var wavePhase: CGFloat = 0

    // Map annotations (nearby + destination)
    @State private var showUserPulse: Bool = true

    var body: some View {
        ZStack {
            // Dark gradient background
            LinearGradient(colors: [Color.black, Color(red: 0.06, green: 0.02, blue: 0.10)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            // MARK: Map with user location + annotations
            Map(position: $cameraPosition, interactionModes: [.all]) {
                // Show user's current location with a custom pulsing dot
                if let coord = locationManager.currentLocation?.coordinate {
                    // Invisible annotation anchor, we overlay PulsingDot via MapAnnotation
                    MapAnnotation(coordinate: coord) {
                        PulsingDot()
                    }
                }

                // Nearby POIs annotations with category-based color and gentle pulse
                ForEach(searchVM.nearbyMapItems, id: \.
self) { item in
                    if let coordinate = item.placemark.location?.coordinate {
                        MapAnnotation(coordinate: coordinate) {
                            CategoryMarkerView(category: searchVM.selectedCategory, title: item.name ?? "")
                                .onTapGesture {
                                    Task { @MainActor in
                                        searchVM.selectedDestination = item
                                        if let user = locationManager.currentLocation?.coordinate {
                                            await routingVM.calculateRoute(from: user, to: coordinate)
                                        }
                                    }
                                }
                        }
                    }
                }

                // Destination marker (from search)
                if let destination = searchVM.selectedDestination, let coordinate = destination.placemark.location?.coordinate {
                    MapAnnotation(coordinate: coordinate) {
                        DestinationMarkerView(title: destination.name ?? "Destination")
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .ignoresSafeArea()
            .onChange(of: locationManager.currentLocation) { _, newLoc in
                // Center camera on user when location updates the first few times
                guard let c = newLoc?.coordinate else { return }
                withAnimation(.easeInOut(duration: 0.8)) {
                    cameraPosition = .region(MKCoordinateRegion(center: c, latitudinalMeters: 1200, longitudinalMeters: 1200))
                }
            }

            // Overlay: Wave demo (Phase 1) near the top as a decorative element
            VStack(spacing: 0) {
                SineWave(phase: wavePhase, amplitude: 10, frequency: 2)
                    .stroke(LinearGradient(colors: [Color.cyan, Color.purple], startPoint: .leading, endPoint: .trailing), lineWidth: 3)
                    .frame(height: 40)
                    .blur(radius: 0.5)
                    .shadow(color: Color.cyan.opacity(0.9), radius: 4)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .onAppear {
                        withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                            wavePhase = .pi * 2
                        }
                    }
                Spacer()
            }

            // Overlay: Search bar + results (Phase 2)
            VStack(spacing: 12) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(Color.cyan)
                        TextField("Search address or place", text: $searchVM.searchText)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .onChange(of: searchVM.searchText) { _, text in
                                searchVM.updateCompletions(for: text)
                            }
                        if !searchVM.searchText.isEmpty {
                            Button(action: { searchVM.searchText = ""; searchVM.completions = [] }) {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(LinearGradient(colors: [Color.purple.opacity(0.8), Color.cyan.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                            .shadow(color: Color.cyan.opacity(0.5), radius: 3)
                    }

                    Button {
                        searchVM.isShowingNearbySheet = true
                    } label: {
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

                // Autocomplete results with subtle wave slide-in
                if !searchVM.completions.isEmpty {
                    AutocompleteList(completions: searchVM.completions) { completion in
                        Task { @MainActor in
                            if let item = await searchVM.performAutocompleteSelection(completion) {
                                if let coord = item.placemark.location?.coordinate {
                                    withAnimation(.spring(response: 0.6, dampingFraction: 0.9)) {
                                        cameraPosition = .region(MKCoordinateRegion(center: coord, latitudinalMeters: 1500, longitudinalMeters: 1500))
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                Spacer()
            }

            // Overlay: Animated route if available (Phase 3)
            if let polyline = routingVM.route?.polyline {
                GlowingRoute(coordinates: polyline.toCoordinates())
                    .allowsHitTesting(false)
                    .padding(16)
            }

            // Bottom sheet for turn-by-turn (Phase 3)
            if routingVM.isShowingDirectionsSheet {
                DirectionsSheet(steps: routingVM.steps) {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
                        routingVM.isShowingDirectionsSheet = false
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .preferredColorScheme(.dark) // Force dark theme
        .task(id: searchVM.selectedDestination) {
            // When destination changes, request a route
            guard let dest = searchVM.selectedDestination?.placemark.location?.coordinate,
                  let user = locationManager.currentLocation?.coordinate else { return }
            await routingVM.calculateRoute(from: user, to: dest)
        }
        .sheet(isPresented: $searchVM.isShowingNearbySheet) {
            NearbySheetView(selected: searchVM.selectedCategory) { category in
                if let user = locationManager.currentLocation?.coordinate {
                    Task { await searchVM.fetchNearby(for: category, around: user) }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(.ultraThinMaterial)
        }
    }
}

// MARK: - Autocomplete Results List
struct AutocompleteList: View {
    let completions: [MKLocalSearchCompletion]
    let onSelect: (MKLocalSearchCompletion) -> Void
    @State private var animateIn: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(completions.enumerated()), id: \.offset) { index, completion in
                Button {
                    onSelect(completion)
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: "waveform.path")
                            .foregroundStyle(Color.cyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(completion.title)
                                .font(.headline)
                            Text(completion.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(LinearGradient(colors: [Color.cyan.opacity(0.7), Color.purple.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .offset(x: animateIn ? 0 : -20)
                .opacity(animateIn ? 1 : 0)
                .animation(.interpolatingSpring(mass: 0.4, stiffness: 120, damping: 14).delay(Double(index) * 0.04), value: animateIn)
            }
        }
        .onAppear { animateIn = true }
    }
}

// MARK: - Category Marker View (Animated)
struct CategoryMarkerView: View {
    let category: POICategory?
    let title: String
    @State private var pulse: Bool = false

    var body: some View {
        let color = category?.color ?? Color.cyan
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial, in: Capsule())
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 36, height: 36)
                    .scaleEffect(pulse ? 1.2 : 0.9)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)
                Circle()
                    .fill(color)
                    .frame(width: 18, height: 18)
                    .shadow(color: color.opacity(0.9), radius: 6)
            }
        }
        .onAppear { pulse = true }
    }
}

// MARK: - Destination Marker View
struct DestinationMarkerView: View {
    let title: String
    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial, in: Capsule())
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(colors: [Color.purple, Color.cyan], startPoint: .top, endPoint: .bottom))
                    .frame(width: 16, height: 16)
                    .rotationEffect(.degrees(45))
                    .shadow(color: Color.cyan.opacity(0.7), radius: 6)
            }
        }
    }
}

// MARK: - Nearby Categories Bottom Sheet
struct NearbySheetView: View {
    let selected: POICategory?
    let onSelect: (POICategory) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Nearby Places")
                    .font(.title3).bold()
                Spacer()
            }
            .padding(.top, 6)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(POICategory.allCases) { category in
                    Button {
                        onSelect(category)
                    } label: {
                        HStack {
                            Circle().fill(category.color.opacity(0.8)).frame(width: 10, height: 10)
                            Text(category.rawValue).font(.headline)
                            Spacer()
                        }
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(LinearGradient(colors: [category.color.opacity(0.8), Color.white.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Tap a category to load animated markers near you.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
        .background(LinearGradient(colors: [Color.black.opacity(0.7), Color(red: 0.06, green: 0.02, blue: 0.10).opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

// MARK: - Directions Bottom Sheet
struct DirectionsSheet: View {
    let steps: [MKRoute.Step]
    let onClose: () -> Void
    @State private var expanded: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color.secondary.opacity(0.6)).frame(width: 40, height: 5).padding(.top, 8)
            HStack {
                Text("Directions")
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill").font(.title3)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            if expanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "waveform")
                                    .foregroundStyle(Color.cyan)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Step \(index + 1)").font(.caption).foregroundStyle(.secondary)
                                    Text(step.instructions)
                                        .font(.subheadline)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                }
                .transition(.opacity)
            }

            Button {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(expanded ? "Collapse" : "Expand")
                    Image(systemName: expanded ? "chevron.down" : "chevron.up")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .padding(.bottom, 10)
        }
        .background(LinearGradient(colors: [Color.black.opacity(0.9), Color(red: 0.06, green: 0.02, blue: 0.10)], startPoint: .top, endPoint: .bottom))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.cyan.opacity(0.4), radius: 12)
        .padding(.horizontal)
        .padding(.bottom, 10)
    }
}

// MARK: - Utilities
extension MKPolyline {
    func toCoordinates() -> [CLLocationCoordinate2D] {
        var coords: [CLLocationCoordinate2D] = Array(repeating: kCLLocationCoordinate2DInvalid, count: Int(pointCount))
        getCoordinates(&coords, range: NSRange(location: 0, length: Int(pointCount)))
        return coords
    }
}

// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .previewDisplayName("Map + Wave + Search + Directions")
    }
}

import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("Hello, world!")
            .padding()
    }
}

#Preview {
    ContentView()
}

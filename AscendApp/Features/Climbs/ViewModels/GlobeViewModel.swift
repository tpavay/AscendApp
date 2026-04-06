import MapKit
import Observation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class GlobeViewModel {
    var cameraPosition: MapCameraPosition = .camera(GlobeViewModel.defaultCamera)
    var visibleClimbs: [Climb] = []
    var activeSummary: ActiveClimbSummary?
    var lastCompletedSummary: CompletedClimbSummary?
    var homeCardState: ClimbHomeCardState = .neverClimbed(totalClimbs: 0)
    var previewSummary: ClimbPreviewSummary?
    var completedClimbIds: Set<String> = []
    var searchQuery: String = ""
    var loadErrorMessage: String?
    var featuredClimbId: String?
    var catalogSource: ClimbCatalogSource = .bootstrap
    var isRefreshingCatalog = false

    private let climbService: ClimbService
    private let autoSpinResumeDelay: TimeInterval = 6
    private let overviewCameraDistance: CLLocationDistance = GlobeViewModel.defaultOverviewCameraDistance
    private var hasLoaded = false
    private var currentLatitude = GlobeViewModel.defaultLatitude
    private var currentLongitude = GlobeViewModel.defaultLongitude
    private var suppressCameraInteraction = false
    private var lastUserInteractionAt = Date.distantPast

    init(climbService: ClimbService = .shared) {
        self.climbService = climbService
    }

    var climbCount: Int {
        visibleClimbs.count
    }

    var firstFeaturedClimb: Climb? {
        if let featuredClimbId,
           let featuredClimb = visibleClimbs.first(where: { $0.id == featuredClimbId }) {
            return featuredClimb
        }

        return visibleClimbs.sorted { lhs, rhs in
            if lhs.tier == rhs.tier {
                return lhs.name < rhs.name
            }
            return lhs.tier > rhs.tier
        }.first
    }

    var searchSuggestions: [Climb] {
        let normalizedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return [] }

        return visibleClimbs
            .compactMap { climb -> (climb: Climb, rank: Int)? in
                guard let rank = searchRank(for: climb, query: normalizedQuery) else { return nil }
                return (climb, rank)
            }
            .sorted { lhs, rhs in
                if lhs.rank == rhs.rank {
                    return lhs.climb.name < rhs.climb.name
                }
                return lhs.rank < rhs.rank
            }
            .map(\.climb)
            .prefix(8)
            .map { $0 }
    }

    func loadIfNeeded(modelContext: ModelContext) {
        guard !hasLoaded else {
            reloadCatalog(modelContext: modelContext)
            refreshCatalogInBackground()
            return
        }

        do {
            visibleClimbs = try climbService.loadClimbs()
            featuredClimbId = climbService.featuredClimbId
            catalogSource = climbService.catalogSource
            refresh(modelContext: modelContext)
            loadErrorMessage = nil
            hasLoaded = true
            refreshCatalogInBackground()
        } catch {
            visibleClimbs = []
            loadErrorMessage = error.localizedDescription
        }
    }

    func reloadCatalog(modelContext: ModelContext) {
        do {
            visibleClimbs = try climbService.loadClimbs()
            featuredClimbId = climbService.featuredClimbId
            catalogSource = climbService.catalogSource
            refresh(modelContext: modelContext)
            loadErrorMessage = nil
        } catch {
            visibleClimbs = []
            loadErrorMessage = error.localizedDescription
        }
    }

    func refresh(modelContext: ModelContext) {
        completedClimbIds = climbService.completedClimbIds(modelContext: modelContext)
        activeSummary = try? climbService.activeSummary(modelContext: modelContext)
        lastCompletedSummary = try? climbService.lastCompletedSummary(modelContext: modelContext)
        homeCardState = (try? climbService.homeCardState(modelContext: modelContext)) ?? .neverClimbed(totalClimbs: visibleClimbs.count)

        if let previewSummary {
            let previewClimb = (try? climbService.climb(for: previewSummary.climb.id)) ?? previewSummary.climb
            self.previewSummary = climbService.previewSummary(for: previewClimb, modelContext: modelContext)
        }
    }

    func selectPreview(_ climb: Climb, modelContext: ModelContext) {
        previewSummary = climbService.previewSummary(for: climb, modelContext: modelContext)
        focus(on: climb, distance: climb.browsePreviewCameraDistance)
        userDidInteract()
    }

    func isCompleted(_ climb: Climb) -> Bool {
        completedClimbIds.contains(climb.id)
    }

    func isActive(_ climb: Climb) -> Bool {
        activeSummary?.climb.id == climb.id
    }

    func dismissPreview() {
        previewSummary = nil
        setCamera(latitude: currentLatitude, longitude: currentLongitude, distance: overviewCameraDistance)
        userDidInteract()
    }

    func prepareForBrowseEntry() {
        searchQuery = ""
        previewSummary = nil
        resetOverviewCamera()
        userDidInteract()
    }

    func clearSearchAndResetCamera() {
        searchQuery = ""
        previewSummary = nil
        resetOverviewCamera()
    }

    func selectSuggestion(_ climb: Climb, modelContext: ModelContext) {
        searchQuery = climb.name
        selectPreview(climb, modelContext: modelContext)
    }

    func mapCameraDidChange(_ context: MapCameraUpdateContext) {
        mapCameraDidChange(
            latitude: context.camera.centerCoordinate.latitude,
            longitude: context.camera.centerCoordinate.longitude
        )
    }

    func mapCameraDidChange(latitude: Double, longitude: Double) {
        currentLatitude = latitude
        currentLongitude = wrappedLongitude(longitude)

        if suppressCameraInteraction {
            suppressCameraInteraction = false
            return
        }

        lastUserInteractionAt = Date()
    }

    func userDidInteract() {
        lastUserInteractionAt = Date()
    }

    func tickAutoSpin() {
        guard hasLoaded,
              searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              previewSummary == nil,
              Date().timeIntervalSince(lastUserInteractionAt) > autoSpinResumeDelay else {
            return
        }

        currentLongitude = wrappedLongitude(currentLongitude + 0.12)
        setCamera(latitude: currentLatitude, longitude: currentLongitude, distance: overviewCameraDistance)
    }

    func resetOverviewCamera() {
        currentLatitude = GlobeViewModel.defaultLatitude
        currentLongitude = GlobeViewModel.defaultLongitude
        setCamera(latitude: currentLatitude, longitude: currentLongitude, distance: overviewCameraDistance)
    }

    private func focus(on climb: Climb, distance: CLLocationDistance) {
        currentLatitude = min(max(climb.latitude, -42), 58)
        currentLongitude = climb.longitude
        setCamera(latitude: currentLatitude, longitude: currentLongitude, distance: distance)
    }

    private func setCamera(latitude: Double, longitude: Double, distance: CLLocationDistance) {
        suppressCameraInteraction = true
        cameraPosition = .camera(
            MapCamera(
                centerCoordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                distance: distance,
                heading: 0,
                pitch: 0
            )
        )
    }

    private func wrappedLongitude(_ longitude: Double) -> Double {
        var value = longitude
        while value > 180 {
            value -= 360
        }
        while value < -180 {
            value += 360
        }
        return value
    }

    private func searchRank(for climb: Climb, query: String) -> Int? {
        let normalizedQuery = query.lowercased()
        let name = climb.name.lowercased()
        let city = climb.city.lowercased()
        let country = climb.country.lowercased()

        if name == normalizedQuery {
            return 0
        }

        if name.hasPrefix(normalizedQuery) {
            return 1
        }

        if city == normalizedQuery || country == normalizedQuery {
            return 2
        }

        if climb.name.localizedStandardContains(query) {
            return 3
        }

        if climb.city.localizedStandardContains(query) {
            return 4
        }

        if climb.country.localizedStandardContains(query) {
            return 5
        }

        if climb.tags.contains(where: { $0.localizedStandardContains(query) }) {
            return 6
        }

        return nil
    }

    private func refreshCatalogInBackground() {
        guard !isRefreshingCatalog else { return }
        isRefreshingCatalog = true

        Task { [weak self] in
            await self?.performCatalogRefresh()
        }
    }

    private func performCatalogRefresh() async {
        defer {
            isRefreshingCatalog = false
        }

        do {
            _ = try await climbService.refreshCatalogIfNeeded()
        } catch {
            if visibleClimbs.isEmpty {
                loadErrorMessage = error.localizedDescription
            }
        }
    }

    private static let defaultLatitude = 18.0
    private static let defaultLongitude = 8.0
    private static let defaultOverviewCameraDistance: CLLocationDistance = 28_000_000

    private static func makeCamera(latitude: Double, longitude: Double, distance: CLLocationDistance) -> MapCamera {
        MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            distance: distance,
            heading: 0,
            pitch: 0
        )
    }

    private static let defaultCamera = makeCamera(
        latitude: defaultLatitude,
        longitude: defaultLongitude,
        distance: defaultOverviewCameraDistance
    )
}

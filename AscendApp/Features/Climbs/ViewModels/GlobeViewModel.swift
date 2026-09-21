import MapKit
import Observation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class GlobeViewModel {
    var cameraPosition: MapCameraPosition = GlobeViewModel.defaultOverviewPosition
    var visibleClimbs: [Climb] = []
    var lastCompletedSummary: CompletedClimbSummary?
    var homeCardState: ClimbHomeCardState = .neverClimbed(totalClimbs: 0)
    var dailyRecommendedClimb: Climb?
    var previewSummary: ClimbPreviewSummary?
    var completedClimbIds: Set<String> = []
    var searchQuery: String = ""
    var loadErrorMessage: String?
    var featuredClimbId: String?
    var catalogSource: ClimbCatalogSource = .bootstrap
    var isRefreshingCatalog = false
    var liveClimbCommunitySummary: LiveClimbCommunitySummary = .empty
    var todayClimbStakeLine: TodayClimbStakeLine = .unavailable
    /// The zoom band the camera last reported. Drives clustering, names and map
    /// detail; it changes once per band crossing, never per frame.
    private(set) var cameraZoomBand: ClimbMapZoomBand = .world
    /// The counts the open card shows for its climb, once fetched.
    private(set) var previewCounts: ClimbCommunityCounts?

    private let climbService: ClimbService
    private let communityStatsService: LiveClimbCommunityStatsServicing
    private let leaderboardService: LiveReplayLeaderboardServicing
    private let autoSpinResumeDelay: TimeInterval = 6
    private let overviewCameraDistance: CLLocationDistance = GlobeViewModel.defaultOverviewCameraDistance
    private var hasLoaded = false
    private var currentLatitude = GlobeViewModel.defaultLatitude
    private var currentLongitude = GlobeViewModel.defaultLongitude
    private var suppressCameraInteraction = false
    private var lastUserInteractionAt = Date.distantPast

    init(
        climbService: ClimbService = .shared,
        communityStatsService: LiveClimbCommunityStatsServicing = FirestoreLiveClimbCommunityStatsService.shared,
        leaderboardService: LiveReplayLeaderboardServicing = LiveReplayLeaderboardService.shared
    ) {
        self.climbService = climbService
        self.communityStatsService = communityStatsService
        self.leaderboardService = leaderboardService
    }

    var climbCount: Int {
        availableClimbs.count
    }

    var availableClimbs: [Climb] {
        visibleClimbs.filter(\.isAvailable)
    }

    var comingSoonClimbs: [Climb] {
        visibleClimbs.filter(\.isComingSoon)
    }

    var liveClimbCommunityCompletedUserCount: Int {
        max(liveClimbCommunitySummary.uniqueCompletedUserCount, completedClimbIds.isEmpty ? 0 : 1)
    }

    var firstFeaturedClimb: Climb? {
        if let featuredClimbId,
           let featuredClimb = availableClimbs.first(where: { $0.id == featuredClimbId }) {
            return featuredClimb
        }

        return availableClimbs.sorted { lhs, rhs in
            if lhs.tier == rhs.tier {
                return lhs.name < rhs.name
            }
            return lhs.tier > rhs.tier
        }.first
    }

    var searchSuggestions: [Climb] {
        let normalizedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return [] }

        return availableClimbs
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
            visibleClimbs = try climbService.loadVisibleClimbs()
            featuredClimbId = climbService.featuredClimbId
            catalogSource = climbService.catalogSource
            refresh(modelContext: modelContext)
            loadErrorMessage = nil
            hasLoaded = true
            refreshCatalogInBackground()
        } catch {
            visibleClimbs = []
            dailyRecommendedClimb = nil
            loadErrorMessage = error.localizedDescription
        }
    }

    func reloadCatalog(modelContext: ModelContext) {
        do {
            visibleClimbs = try climbService.loadVisibleClimbs()
            featuredClimbId = climbService.featuredClimbId
            catalogSource = climbService.catalogSource
            refresh(modelContext: modelContext)
            loadErrorMessage = nil
        } catch {
            visibleClimbs = []
            dailyRecommendedClimb = nil
            loadErrorMessage = error.localizedDescription
        }
    }

    func refresh(modelContext: ModelContext) {
        // The globe's claimed set is the repository's one completed-set
        // definition (server-authoritative after refresh), not a raw cache read.
        completedClimbIds = ClimbCompletionRepository.completedClimbSet(modelContext: modelContext)
            .completedClimbIds
        lastCompletedSummary = try? climbService.lastCompletedSummary(modelContext: modelContext)
        homeCardState = (try? climbService.homeCardState(modelContext: modelContext)) ?? .neverClimbed(totalClimbs: availableClimbs.count)
        refreshDailyRecommendedClimb()

        if let previewSummary {
            let previewClimb = (try? climbService.climb(for: previewSummary.climb.id)) ?? previewSummary.climb
            self.previewSummary = climbService.previewSummary(for: previewClimb, modelContext: modelContext)
        }
    }

    func refreshLiveClimbCommunityStats() async {
        do {
            liveClimbCommunitySummary = try await communityStatsService.fetchSummary()
        } catch {
            liveClimbCommunitySummary = .empty
        }
    }

    func refreshTodayClimbStake(
        modelContext: ModelContext,
        currentUserId: String?
    ) async {
        guard let climb = dailyRecommendedClimb else {
            todayClimbStakeLine = .unavailable
            return
        }

        let localHistory = climbService.historySummary(for: climb, modelContext: modelContext)
        todayClimbStakeLine = Self.stakeLine(
            summary: nil,
            finisherStatus: nil,
            localHistory: localHistory,
            currentUserId: currentUserId
        )

        let context = LiveReplayLeaderboardContext.liveClimb(
            climbId: climb.id,
            targetSteps: climb.referenceStepCount
        )

        async let fetchedSummary = leaderboardService.fetchSummary(context: context)
        async let fetchedFinisherStatus = leaderboardService.fetchCurrentUserFinisherStatus(context: context)

        let summary = try? await fetchedSummary
        let finisherStatus = try? await fetchedFinisherStatus

        guard dailyRecommendedClimb?.id == climb.id else { return }

        if let finisherStatus {
            try? climbService.mirrorFinisherStatus(
                finisherStatus,
                for: climb,
                modelContext: modelContext
            )
        }

        let refreshedHistory = climbService.historySummary(for: climb, modelContext: modelContext)
        todayClimbStakeLine = Self.stakeLine(
            summary: summary,
            finisherStatus: finisherStatus,
            localHistory: refreshedHistory,
            currentUserId: currentUserId
        )
    }

    func selectPreview(_ climb: Climb, modelContext: ModelContext) {
        if previewSummary?.climb.id != climb.id {
            previewCounts = nil
        }
        previewSummary = climbService.previewSummary(for: climb, modelContext: modelContext)
        // Fly down to the landmark itself (close, pitched 3D framing) rather
        // than the far top-down preview distance.
        currentLatitude = climb.latitude
        currentLongitude = climb.longitude
        setCamera(
            latitude: climb.latitude,
            longitude: climb.longitude,
            distance: ClimbCameraFraming.distance(for: climb),
            pitch: ClimbCameraFraming.pitch(for: climb)
        )
        userDidInteract()
    }

    func isCompleted(_ climb: Climb) -> Bool {
        completedClimbIds.contains(climb.id)
    }

    func dismissPreview() {
        previewSummary = nil
        previewCounts = nil
        setOverviewCamera()
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

    func clearSearch() {
        searchQuery = ""
        previewSummary = nil
    }

    func selectSuggestion(_ climb: Climb) {
        searchQuery = climb.name
        previewSummary = nil
        userDidInteract()
    }

    func mapCameraDidChange(_ context: MapCameraUpdateContext) {
        mapCameraDidChange(
            latitude: context.camera.centerCoordinate.latitude,
            longitude: context.camera.centerCoordinate.longitude,
            distance: context.camera.distance
        )
    }

    func mapCameraDidChange(latitude: Double, longitude: Double, distance: CLLocationDistance? = nil) {
        currentLatitude = latitude
        currentLongitude = wrappedLongitude(longitude)
        if let distance {
            let band = ClimbMapZoomBand(cameraDistance: distance)
            if band != cameraZoomBand {
                cameraZoomBand = band
            }
        }

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
        setOverviewCamera()
    }

    /// Flies in far enough for a cluster's members to draw as their own pins.
    func focusOnCluster(_ cluster: AscendMapCluster) {
        currentLatitude = cluster.coordinate.latitude
        currentLongitude = cluster.coordinate.longitude
        setCamera(
            latitude: cluster.coordinate.latitude,
            longitude: cluster.coordinate.longitude,
            distance: cameraZoomBand.clusterFocusDistance
        )
        userDidInteract()
    }

    /// Home's opening frame: continent altitude, centred on Today's Climb. Falls back
    /// to the default overview when no climb is recommended yet.
    func prepareForHomeEntry() {
        searchQuery = ""
        previewSummary = nil
        previewCounts = nil
        guard let climb = dailyRecommendedClimb else {
            resetOverviewCamera()
            return
        }
        currentLatitude = climb.latitude
        currentLongitude = climb.longitude
        setCamera(
            latitude: climb.latitude,
            longitude: climb.longitude,
            distance: ClimbMapZoomBand.homeEntryCameraDistance
        )
    }

    /// Loads the counts the open card shows: how many climbers have completed the
    /// climb and how many completions the board holds, the same two numbers Climb
    /// Detail reads. Cleared when the card closes; a stale answer never lands on a
    /// different climb's card.
    func refreshPreviewCounts() async {
        guard let climb = previewSummary?.climb, climb.isAvailable else {
            previewCounts = nil
            return
        }
        let context = LiveReplayLeaderboardContext.liveClimb(
            climbId: climb.id,
            targetSteps: climb.referenceStepCount
        )
        async let fetchedSummary = leaderboardService.fetchSummary(context: context)
        async let fetchedBoard = leaderboardService.fetchCompletionLeaderboard(context: context, limit: 1)
        let summary = try? await fetchedSummary
        let board = try? await fetchedBoard
        guard previewSummary?.climb.id == climb.id else { return }
        guard summary != nil || board != nil else {
            previewCounts = nil
            return
        }
        previewCounts = ClimbCommunityCounts(
            completedClimbers: max(summary?.completedCount ?? 0, summary?.firstAscent == nil ? 0 : 1),
            completions: max(board?.completedCount ?? 0, summary?.completedCount ?? 0)
        )
    }

    private func setOverviewCamera() {
        suppressCameraInteraction = true
        cameraPosition = GlobeViewModel.defaultOverviewPosition
    }

    private func setCamera(latitude: Double, longitude: Double, distance: CLLocationDistance, pitch: CGFloat = 0) {
        suppressCameraInteraction = true
        cameraPosition = .camera(
            MapCamera(
                centerCoordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                distance: distance,
                heading: 0,
                pitch: pitch
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

    private static func stakeLine(
        summary: LiveReplayLeaderboardSummary?,
        finisherStatus: LiveReplayFinisherStatus?,
        localHistory: ClimbHistorySummary,
        currentUserId: String?
    ) -> TodayClimbStakeLine {
        let bestDurationSeconds = localHistory.bestCompletionDurationSeconds ??
            finisherStatus?.bestCompletionDurationSeconds.map { Int($0.rounded()) }
        let globalCompletionOrder = finisherStatus?.globalCompletionOrder ??
            localHistory.globalCompletionOrder
        let currentUserHoldsFirstAscent = summary?.firstAscent?.userId != nil &&
            summary?.firstAscent?.userId == currentUserId

        if currentUserHoldsFirstAscent, let bestDurationSeconds {
            return .firstAscent(bestDurationSeconds: bestDurationSeconds)
        }

        if localHistory.completionsCount > 0 || finisherStatus != nil {
            if let bestDurationSeconds, let globalCompletionOrder {
                return .completed(
                    bestDurationSeconds: bestDurationSeconds,
                    globalCompletionOrder: globalCompletionOrder
                )
            }

            if let bestDurationSeconds {
                return .completedPendingOrdinal(bestDurationSeconds: bestDurationSeconds)
            }
        }

        guard let summary else {
            return .unavailable
        }

        let completedCount = max(
            summary.completedCount,
            summary.firstAscent == nil ? 0 : 1
        )

        guard completedCount > 0 else {
            return .openFirstAscent
        }

        if completedCount < 100 {
            return .nextFinisher(completedCount + 1)
        }

        return .joinFinishers(completedCount)
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

    private func nextDailyRecommendedClimb() -> Climb? {
        DailyClimbRecommendationPolicy.recommendation(
            from: availableClimbs,
            completedClimbIds: completedClimbIds
        )
    }

    private func refreshDailyRecommendedClimb() {
        guard !availableClimbs.isEmpty else {
            dailyRecommendedClimb = nil
            return
        }

        let defaults = UserDefaults.standard
        let todayKey = Self.dailyRecommendationDayKey

        if defaults.string(forKey: Self.dailyRecommendationDayDefaultsKey) == todayKey,
           let storedClimbId = defaults.string(forKey: Self.dailyRecommendationClimbDefaultsKey),
           let storedClimb = availableClimbs.first(where: { $0.id == storedClimbId }) {
            dailyRecommendedClimb = storedClimb
            return
        }

        let climb = nextDailyRecommendedClimb()
        defaults.set(todayKey, forKey: Self.dailyRecommendationDayDefaultsKey)
        if let climb {
            defaults.set(climb.id, forKey: Self.dailyRecommendationClimbDefaultsKey)
        } else {
            defaults.removeObject(forKey: Self.dailyRecommendationClimbDefaultsKey)
        }
        dailyRecommendedClimb = climb
    }

    private static var dailyRecommendationDayKey: String {
        DailyClimbRecommendationPolicy.dayKey()
    }

    private static let dailyRecommendationDayDefaultsKey = "liveClimbDailyRecommendationDay"
    private static let dailyRecommendationClimbDefaultsKey = "liveClimbDailyRecommendationClimbId"

    private static let defaultLatitude = 8.0
    private static let defaultLongitude = -76.0
    private static let defaultOverviewCameraDistance: CLLocationDistance = 28_000_000
    private static let defaultOverviewPosition = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: defaultLatitude, longitude: defaultLongitude),
            span: MKCoordinateSpan(latitudeDelta: 138, longitudeDelta: 150)
        )
    )

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

#if DEBUG || STAGING
extension GlobeViewModel {
    static func debugDailyRecommendedClimbId() -> String? {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: dailyRecommendationDayDefaultsKey) == dailyRecommendationDayKey else {
            return nil
        }
        return defaults.string(forKey: dailyRecommendationClimbDefaultsKey)
    }

    static func debugSetDailyRecommendedClimbId(_ climbId: String) {
        let defaults = UserDefaults.standard
        defaults.set(dailyRecommendationDayKey, forKey: dailyRecommendationDayDefaultsKey)
        defaults.set(climbId, forKey: dailyRecommendationClimbDefaultsKey)
        NotificationCenter.default.post(name: .climbStateDidChange, object: nil)
    }

    static func debugClearDailyRecommendedClimbId() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: dailyRecommendationDayDefaultsKey)
        defaults.removeObject(forKey: dailyRecommendationClimbDefaultsKey)
        NotificationCenter.default.post(name: .climbStateDidChange, object: nil)
    }
}
#endif

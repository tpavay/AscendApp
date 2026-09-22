import Foundation

/// Engine-agnostic description of WHAT the climb map shows: the landmarks, how each
/// reads on the map, and the zoom band that decides whether names show. A
/// *renderer* turns this into pixels (MapKit today; Mapbox / MapLibre / a custom
/// globe later) and groups markers that would overlap on its own screen through
/// `ClimbMapClustering`.
///
/// This is deliberately pure data: no MapKit, no SwiftUI. That keeps the business
/// layer (`GlobeViewModel`) independent of any specific map engine and makes the
/// map's content unit-testable. Swapping engines means writing a new renderer that
/// consumes this same scene, not rewriting the globe's data flow or the view model.
/// See `ClimbMapKitRenderer` for the current renderer and the migration notes there.
struct AscendMapScene {
    var landmarks: [AscendMapLandmark]
    var zoomBand: ClimbMapZoomBand

    var showsNames: Bool {
        zoomBand.showsNames
    }

    /// The step-range legend lists only the tiers on the globe.
    var legendTiers: [ClimbTier] {
        let present = Set(landmarks.map(\.climb.tier))
        return ClimbTier.allCases.filter { present.contains($0) }
    }
}

/// One placed landmark on the map: the climb plus how it should read on the map.
struct AscendMapLandmark: Identifiable {
    enum State {
        case available
        /// Available and nobody has finished it yet: the First Ascent is still open.
        case firstAscentOpen
        case comingSoon
        case completed
    }

    let climb: Climb
    var state: State
    var isHighlighted: Bool
    /// Distinct climbers who have completed it, or nil until the boards have answered.
    var completedClimberCount: Int? = nil

    var id: String { climb.id }
}

extension GlobeViewModel {
    /// The current map content as an engine-agnostic scene. Renderers read this
    /// instead of reaching into the view model's individual properties, so the
    /// "what to draw" contract lives in one place.
    var mapScene: AscendMapScene {
        AscendMapScene(
            landmarks: visibleClimbs.map { climb in
                AscendMapLandmark(
                    climb: climb,
                    state: landmarkState(for: climb),
                    isHighlighted: previewSummary?.climb.id == climb.id,
                    completedClimberCount: completedClimberCount(for: climb)
                )
            },
            zoomBand: cameraZoomBand
        )
    }

    private func landmarkState(for climb: Climb) -> AscendMapLandmark.State {
        if isCompleted(climb) { return .completed }
        if climb.isComingSoon { return .comingSoon }
        // Only once the boards have answered: an unread count marks nothing as open,
        // so the globe never claims a First Ascent is available before it knows.
        if isFirstAscentOpen(climb) {
            return .firstAscentOpen
        }
        return .available
    }
}

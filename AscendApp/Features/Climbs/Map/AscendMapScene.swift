import Foundation

/// Engine-agnostic description of WHAT the climb map shows — the landmarks and
/// their map-facing state. A *renderer* turns this into pixels (MapKit today;
/// Mapbox / MapLibre / a custom globe later).
///
/// This is deliberately pure data: no MapKit, no SwiftUI. That keeps the
/// business layer (`GlobeViewModel`) independent of any specific map engine and
/// makes the map's content unit-testable. Swapping engines means writing a new
/// renderer that consumes this same scene — not rewriting the globe's data flow
/// or the view model. See `ClimbMapKitRenderer` for the current renderer and the
/// migration notes there.
struct AscendMapScene {
    var landmarks: [AscendMapLandmark]
}

/// One placed landmark on the map: the climb plus how it should read on the map.
struct AscendMapLandmark: Identifiable {
    enum State {
        case available
        case comingSoon
        case completed
    }

    let climb: Climb
    var state: State
    var isHighlighted: Bool

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
                    isHighlighted: previewSummary?.climb.id == climb.id
                )
            }
        )
    }

    private func landmarkState(for climb: Climb) -> AscendMapLandmark.State {
        if isCompleted(climb) { return .completed }
        return climb.isComingSoon ? .comingSoon : .available
    }
}

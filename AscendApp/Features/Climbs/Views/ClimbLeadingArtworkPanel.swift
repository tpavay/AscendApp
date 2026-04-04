import SwiftUI

struct ClimbLeadingArtworkPanel: View {
    let climb: Climb
    let variant: ClimbImageVariant

    init(climb: Climb, variant: ClimbImageVariant = .card) {
        self.climb = climb
        self.variant = variant
    }

    var body: some View {
        ZStack {
            ClimbArtworkView(climb: climb, variant: variant)
                .overlay {
                    LinearGradient(
                        colors: [
                            .black.opacity(0.04),
                            .black.opacity(0.12),
                            .black.opacity(0.28)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }

            LinearGradient(
                colors: [
                    .clear,
                    .black.opacity(0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .clipped()
    }
}

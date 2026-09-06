import SwiftUI

/// The row of measurements a Live Activity draws: steps, the standing, and time.
///
/// The standing column is the one whose height moves - two lines for a plain
/// rank, three when a rank carries the climber's own history beneath it, a title
/// over a single small line where nobody else has finished - so the row is
/// aligned on its top edge. Centred, the `Rank` or `Field` title floated a few
/// points above or below `Steps` and `Time` depending purely on which state the
/// climber happened to be in.
struct LiveClimbActivityMetricsRow: View {
    enum Surface {
        /// Steps lead on the Lock Screen, where the standing sits between the two
        /// session numbers.
        case lockScreen
        /// The standing leads in the expanded Dynamic Island, beside the controls.
        case expandedIsland

        var spacing: CGFloat {
            switch self {
            case .lockScreen:
                return 16
            case .expandedIsland:
                return 12
            }
        }
    }

    let state: LiveClimbActivityAttributes.ContentState
    let surface: Surface

    var body: some View {
        HStack(alignment: .top, spacing: surface.spacing) {
            switch surface {
            case .lockScreen:
                stepsColumn
                standingColumn
                timeColumn
            case .expandedIsland:
                standingColumn
                timeColumn
                stepsColumn
            }
        }
    }

    private var stepsColumn: some View {
        LiveClimbMetricColumn(title: "Steps", value: state.steps.formatted())
    }

    private var standingColumn: some View {
        LiveClimbMetricColumn(
            title: state.standingTitle,
            value: state.standingDetailLabel,
            secondary: state.standingSecondaryLabel
        )
    }

    private var timeColumn: some View {
        LiveClimbMetricColumn(title: "Time", value: state.durationLabel)
    }
}

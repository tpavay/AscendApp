import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct AscendLiveActivityWidgetsBundle: WidgetBundle {
    var body: some Widget {
        LiveClimbActivityWidget()
    }
}

struct LiveClimbActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveClimbActivityAttributes.self) { context in
            LiveClimbLockScreenView(context: context)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.ascendAccent)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LiveClimbExpandedTitleView(context: context)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    LiveClimbPhotoView(urlString: context.state.climbPhotoURLString)
                        .frame(width: 48, height: 48)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    LiveClimbExpandedBottomView(context: context)
                }
            } compactLeading: {
                LiveClimbCompactMetricView(
                    value: context.state.rankLabel,
                    label: "rank"
                )
            } compactTrailing: {
                LiveClimbCompactMetricView(
                    value: context.state.compactStepsLabel,
                    label: "steps"
                )
            } minimal: {
                LiveClimbMinimalView(
                    progress: context.state.clampedProgress,
                    stepsLabel: context.state.minimalStepsLabel
                )
            }
            .keylineTint(.ascendAccent)
        }
    }
}

private struct LiveClimbLockScreenView: View {
    let context: ActivityViewContext<LiveClimbActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            LiveClimbPhotoView(urlString: context.state.climbPhotoURLString)
                .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 8) {
                LiveClimbExpandedTitleView(context: context)

                HStack(spacing: 16) {
                    LiveClimbMetricColumn(title: "Steps", value: context.state.steps.formatted())
                    LiveClimbMetricColumn(title: "Rank", value: context.state.rankDetailLabel)
                    LiveClimbMetricColumn(title: "Time", value: context.state.durationLabel)
                }
            }

            Spacer(minLength: 0)

            LiveClimbControlButtons()
        }
        .padding(16)
        .foregroundStyle(.white)
    }
}

private struct LiveClimbExpandedTitleView: View {
    let context: ActivityViewContext<LiveClimbActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(context.attributes.climbName)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(context.attributes.climbLocation)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .foregroundStyle(.white)
    }
}

private struct LiveClimbExpandedBottomView: View {
    let context: ActivityViewContext<LiveClimbActivityAttributes>

    var body: some View {
        VStack(spacing: 12) {
            if context.attributes.targetSteps > 0 {
                ProgressView(value: context.state.clampedProgress)
                    .progressViewStyle(.linear)
                    .tint(.ascendAccent)
                    .background(.white.opacity(0.12), in: Capsule())
            } else {
                Capsule()
                    .fill(.white.opacity(0.12))
                    .frame(height: 4)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Color.ascendAccent)
                            .frame(width: 42)
                    }
            }

            HStack(spacing: 12) {
                LiveClimbMetricColumn(title: "Rank", value: context.state.rankDetailLabel)
                LiveClimbMetricColumn(title: "Time", value: context.state.durationLabel)
                LiveClimbMetricColumn(title: "Steps", value: context.state.steps.formatted())

                Spacer(minLength: 0)

                LiveClimbControlButtons()
            }
        }
        .foregroundStyle(.white)
    }
}

private struct LiveClimbCompactMetricView: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.62)

            Text(label)
                .font(.system(size: 7, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
    }
}

private struct LiveClimbMinimalView: View {
    let progress: Double
    let stepsLabel: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.20), lineWidth: 2)

            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(Color.ascendAccent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Text(stepsLabel)
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(.white)
        }
        .frame(width: 20, height: 20)
    }
}

private struct LiveClimbMetricColumn: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))
                .lineLimit(1)

            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }
}

private struct LiveClimbControlButtons: View {
    var body: some View {
        HStack(spacing: 9) {
            Button(intent: StopLiveClimbIntent()) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(.red.opacity(0.86)))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
    }
}

private struct LiveClimbPhotoView: View {
    let urlString: String?

    var body: some View {
        ZStack {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty, .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var url: URL? {
        urlString.flatMap(URL.init(string:))
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    .ascendAccent.opacity(0.82),
                    Color(red: 0.04, green: 0.07, blue: 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: "building.2.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.black.opacity(0.74))
        }
    }
}

private extension Color {
    static let ascendAccent = Color(red: 0.706, green: 0.800, blue: 0.000)
}

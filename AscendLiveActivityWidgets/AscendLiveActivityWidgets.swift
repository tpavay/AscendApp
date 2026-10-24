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
                .widgetURL(context.attributes.deepLinkURL)
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
                if context.isStale && context.state.status == .recording {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.2))
                } else {
                    LiveClimbCompactMetricView(
                        value: context.state.standingValue,
                        label: context.state.standingCaption
                    )
                }
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
            .widgetURL(context.attributes.deepLinkURL)
        }
    }
}

private struct LiveClimbLockScreenView: View {
    let context: ActivityViewContext<LiveClimbActivityAttributes>

    var body: some View {
        if context.isStale && context.state.status == .recording {
            LiveClimbStaleLockScreenView(context: context)
        } else {
            liveBody
        }
    }

    private var liveBody: some View {
        HStack(spacing: 14) {
            LiveClimbPhotoView(urlString: context.state.climbPhotoURLString)
                .frame(width: 58, height: 58)

            // The column takes the slack itself rather than handing it to a spacer: a spacer
            // is one more child, so it cost a second 14-point gap before the stop control even
            // when it had collapsed to nothing - width the metrics row needs on a compact
            // phone now that floors sit under the step count.
            VStack(alignment: .leading, spacing: 8) {
                LiveClimbExpandedTitleView(context: context)

                LiveClimbActivityMetricsRow(state: context.state, surface: .lockScreen)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            LiveClimbControlButtons()
        }
        .padding(16)
        .foregroundStyle(.white)
    }
}

/// What the Lock Screen says once no update has arrived inside the stale window: the process
/// that was counting is gone, and the only way to get the steps back is to open Ascend. The tap
/// goes through the same deep link, which lands on the automatic resume.
struct LiveClimbStaleLockScreenView: View {
    let context: ActivityViewContext<LiveClimbActivityAttributes>

    static let title = "Ascend stopped counting"
    static let action = "Tap to resume"

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.2))
                .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 4) {
                Text(Self.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .lineLimit(1)

                Text("\(Self.action) \(context.attributes.climbName) at \(context.state.compactStepsLabel) steps, \(context.state.durationLabel).")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                LiveClimbActivityMetricsRow(state: context.state, surface: .expandedIsland)

                Spacer(minLength: 0)

                LiveClimbControlButtons()
            }
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

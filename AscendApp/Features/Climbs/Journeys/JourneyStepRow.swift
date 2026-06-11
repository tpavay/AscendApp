#if DEBUG
import SwiftUI

struct JourneyStepRow: View {
    let step: JourneyStep
    let accent: Color
    let isSelected: Bool
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            railMarker

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(step.climb.name)
                        .font(.montserratBold(size: 15))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Spacer(minLength: 8)

                    statusPill
                }

                Text(step.climb.displayLocation.uppercased())
                    .font(.montserratSemiBold(size: 10))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)

                HStack(spacing: 10) {
                    metricText("\(step.climb.referenceStepCount.formatted()) steps")
                    metricText(step.climb.tier.rawValue.uppercased())
                }
            }
            .padding(.vertical, 14)
        }
        .padding(.horizontal, 14)
        .background(isSelected ? accent.opacity(0.13) : .clear)
        .contentShape(Rectangle())
    }

    private var railMarker: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(markerFill)
                    .frame(width: 28, height: 28)

                Image(systemName: step.status.systemImageName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(markerContentColor)
            }
            .overlay {
                Circle()
                    .strokeBorder(markerBorder, lineWidth: 1.5)
            }
            .padding(.top, 13)

            if !isLast {
                Rectangle()
                    .fill(lineFill)
                    .frame(width: 2, height: 55)
            }
        }
        .frame(width: 30)
    }

    private var statusPill: some View {
        Text(step.status.label.uppercased())
            .font(.montserratBold(size: 9))
            .tracking(1)
            .foregroundStyle(statusTextColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(statusFill, in: Capsule())
    }

    private func metricText(_ text: String) -> some View {
        Text(text)
            .font(.montserratSemiBold(size: 10))
            .tracking(0.6)
            .foregroundStyle(.white.opacity(0.62))
    }

    private var markerFill: Color {
        switch step.status {
        case .completed, .current:
            accent
        case .locked:
            .black.opacity(0.8)
        }
    }

    private var markerBorder: Color {
        switch step.status {
        case .completed, .current:
            .white.opacity(0.82)
        case .locked:
            .white.opacity(0.2)
        }
    }

    private var markerContentColor: Color {
        switch step.status {
        case .completed, .current:
            .black.opacity(0.86)
        case .locked:
            .white.opacity(0.6)
        }
    }

    private var lineFill: Color {
        switch step.status {
        case .completed:
            accent.opacity(0.82)
        case .current, .locked:
            .white.opacity(0.16)
        }
    }

    private var statusFill: Color {
        switch step.status {
        case .completed, .current:
            accent
        case .locked:
            .white.opacity(0.09)
        }
    }

    private var statusTextColor: Color {
        switch step.status {
        case .completed, .current:
            .black.opacity(0.86)
        case .locked:
            .white.opacity(0.56)
        }
    }
}
#endif

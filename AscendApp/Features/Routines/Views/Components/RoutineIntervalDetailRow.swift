import SwiftUI

enum RoutineIntervalRowLeadingStyle {
    case accentBar
    case indexBadge(Int)
}

struct RoutineIntervalDetailRow: View {
    let interval: RoutineInterval
    let totalDuration: TimeInterval?
    let leadingStyle: RoutineIntervalRowLeadingStyle

    @Environment(\.colorScheme) private var colorScheme

    init(
        interval: RoutineInterval,
        totalDuration: TimeInterval? = nil,
        leadingStyle: RoutineIntervalRowLeadingStyle = .accentBar
    ) {
        self.interval = interval
        self.totalDuration = totalDuration
        self.leadingStyle = leadingStyle
    }

    var body: some View {
        HStack(spacing: 0) {
            leadingDecoration

            RoutineCardSurface(
                cornerRadius: 14,
                darkFillOpacity: 0.35,
                lightFillOpacity: 0.08,
                darkStrokeOpacity: 0,
                lightStrokeOpacity: 0
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Level \(interval.resolvedLevel)")
                                .font(.montserratSemiBold(size: 18))
                                .foregroundStyle(.white)

                            Text(subtitle)
                                .font(.montserratRegular(size: 12))
                                .foregroundStyle(Color.customGray)
                                .lineLimit(2)
                        }

                        Spacer()

                        Text(interval.durationFormatted)
                            .font(.montserratSemiBold(size: 14))
                            .foregroundStyle(Color.customGray)
                    }

                    RoutineCardSurface(
                        cornerRadius: 4,
                        darkFillOpacity: 0.18,
                        lightFillOpacity: 0.08,
                        darkStrokeOpacity: 0,
                        lightStrokeOpacity: 0
                    ) {
                        Rectangle()
                            .fill(.clear)
                            .frame(height: 4)
                            .overlay(alignment: .leading) {
                                GeometryReader { geometry in
                                    Rectangle()
                                        .fill(accentColor)
                                        .frame(width: geometry.size.width * progressRatio)
                                }
                            }
                    }
                }
                .padding(14)
            }
        }
        .clipShape(.rect(cornerRadius: 14))
    }

    @ViewBuilder
    private var leadingDecoration: some View {
        switch leadingStyle {
        case .accentBar:
            LeadingAccentStripe(color: accentColor, width: 4, cornerRadius: 14)

        case .indexBadge(let index):
            Text("\(index)")
                .font(.montserratSemiBold(size: 14))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(.accent)
                )
                .padding(.trailing, 12)
        }
    }

    private var subtitle: String {
        "\(interval.modifiers.stepTypeDescription) · \(interval.mappedStepsPerMinute) SPM"
    }

    private var accentColor: Color {
        RoutineIntervalScale.color(of: interval, colorScheme: colorScheme)
    }

    private var progressRatio: CGFloat {
        guard let totalDuration, totalDuration > 0 else { return 0 }
        return min(max(interval.duration / totalDuration, 0), 1)
    }
}

#Preview {
    VStack(spacing: 8) {
        RoutineIntervalDetailRow(
            interval: BuiltInRoutines.previewTemplates[0].intervals[0],
            totalDuration: BuiltInRoutines.previewTemplates[0].totalDuration
        )
        RoutineIntervalDetailRow(
            interval: BuiltInRoutines.previewTemplates[3].intervals[1],
            totalDuration: BuiltInRoutines.previewTemplates[3].totalDuration
        )
    }
    .padding(20)
    .preferredColorScheme(.dark)
}

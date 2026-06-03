import SwiftUI

struct HomeRecentPRsSection: View {
    let records: [HomeRecentPRRecord]
    let workouts: [Workout]

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("RECENT PERSONAL RECORDS")
                    .font(.montserratSemiBold(size: 11))
                    .tracking(1.2)
                    .foregroundStyle(Color.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer()

                NavigationLink {
                    BestEffortsListView(workouts: workouts)
                } label: {
                    HStack(spacing: 4) {
                        Text("VIEW ALL")
                            .font(.montserratSemiBold(size: 11))
                            .tracking(0.8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(Color.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View all personal records")
            }

            HStack(spacing: 12) {
                ForEach(records) { record in
                    NavigationLink {
                        BestEffortRecordDetailView(
                            metric: record.metric,
                            workouts: workouts
                        )
                    } label: {
                        HomePRCard(record: record)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct HomePRCard: View {
    let record: HomeRecentPRRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(record.label)
                .font(.montserratSemiBold(size: 9))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            valueText
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 74, maxHeight: 74, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hex: "111111"))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(record.label): \(record.value)\(record.isNew ? ", new personal record" : "")")
    }

    @ViewBuilder
    private var valueText: some View {
        switch record.metric {
        case .highestAverageSPM:
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(paceValueNumber)
                    .font(.montserratBold(size: 22))
                    .foregroundStyle(.white)

                Text(paceValueUnit)
                    .font(.montserratBold(size: 11))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        default:
            Text(record.value)
                .font(.montserratBold(size: 22))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var paceValueNumber: String {
        record.value.split(separator: " ", maxSplits: 1).first.map(String.init) ?? record.value
    }

    private var paceValueUnit: String {
        let parts = record.value.split(separator: " ", maxSplits: 1).map(String.init)
        return parts.dropFirst().first ?? "SPM"
    }
}

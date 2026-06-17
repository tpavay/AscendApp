import SwiftUI

/// Own-profile best-efforts list: personal records as a clean stat list (not a card grid). Each
/// row drills into its progression detail. Lifetime career totals now live in the inline stat
/// band under the hero, not here.
struct RecordBookSection: View {
    let records: ProfileRecordSummary
    let workouts: [Workout]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if records.personalRecords.isEmpty {
                Text("Finish a climb to set your first records.")
                    .font(.montserratMedium(size: 13))
                    .foregroundStyle(ProfileVisualStyle.secondaryText)
                    .padding(.horizontal, 2)
            } else {
                VStack(spacing: 0) {
                    ForEach(records.personalRecords) { record in
                        bestEffortRow(record)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("BEST EFFORTS")
                .font(.montserratBold(size: 16))
                .foregroundStyle(.white)
                .tracking(1.4)

            Spacer()

            if canOpenBestEfforts {
                NavigationLink {
                    BestEffortsListView(workouts: workouts)
                } label: {
                    Text("VIEW ALL")
                        .font(.montserratSemiBold(size: 11))
                        .foregroundStyle(Color.ascendAccent)
                        .tracking(1.2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private func bestEffortRow(_ record: ProfileRecordSummary.PersonalRecord) -> some View {
        if canOpenBestEfforts, let metric = bestEffortMetric(for: record.kind) {
            NavigationLink {
                BestEffortRecordDetailView(metric: metric, workouts: workouts)
            } label: {
                statRow(label: record.label, value: record.valueText ?? "—", isNavigable: true)
            }
            .buttonStyle(.plain)
        } else {
            statRow(label: record.label, value: record.valueText ?? "—", isNavigable: false)
        }
    }

    private func statRow(label: String, value: String, isNavigable: Bool) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.montserratMedium(size: 14))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 8)

            Text(value)
                .font(.montserratBold(size: 15))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if isNavigable {
                Image(systemName: "chevron.forward")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ProfileVisualStyle.tertiaryText)
            }
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
        .contentShape(Rectangle())
    }

    private var canOpenBestEfforts: Bool {
        !workouts.isEmpty
    }

    private func bestEffortMetric(for kind: ProfileRecordSummary.PersonalRecord.Kind) -> BestEffortMetric? {
        switch kind {
        case .mostSteps:
            return .mostSteps
        case .longestClimb:
            return .longestClimb
        case .fastestPace:
            return .highestAverageSPM
        }
    }
}

import SwiftUI

struct RecordsSection: View {
    let records: ProfileRecordSummary
    let totalClimbsCompleted: Int
    let workouts: [Workout]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(records.personalRecords) { record in
                    recordCard(record)
                }
            }

            if totalClimbsCompleted == 0 {
                Text("Set your first by finishing a climb.")
                    .font(.montserratMedium(size: 13))
                    .foregroundStyle(ProfileVisualStyle.secondaryText)
                    .padding(.horizontal, 2)
            }
        }
    }

    private var sectionHeader: some View {
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
                    Text("MORE RECORDS")
                        .font(.montserratSemiBold(size: 11))
                        .foregroundStyle(Color.accentColor)
                        .tracking(1.2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 2)
    }

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ]
    }

    @ViewBuilder
    private func recordCard(_ record: ProfileRecordSummary.PersonalRecord) -> some View {
        if canOpenBestEfforts, let metric = bestEffortMetric(for: record.kind) {
            NavigationLink {
                BestEffortRecordDetailView(
                    metric: metric,
                    workouts: workouts
                )
            } label: {
                recordCardContent(record)
            }
            .buttonStyle(.plain)
        } else {
            recordCardContent(record)
        }
    }

    private func recordCardContent(_ record: ProfileRecordSummary.PersonalRecord) -> some View {
        ProfileCardSurfaceView {
            VStack(alignment: .leading, spacing: 8) {
                Text(record.label)
                    .font(.montserratBold(size: 9))
                    .foregroundStyle(ProfileVisualStyle.secondaryText)
                    .tracking(1)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(record.valueText ?? "-")
                    .font(.montserratBold(size: 18))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)

                if let date = record.date {
                    Text(ProfileDateFormatters.shortDate(date).uppercased())
                        .font(.montserratMedium(size: 9))
                        .foregroundStyle(ProfileVisualStyle.tertiaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 98, alignment: .leading)
            .padding(10)
        }
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

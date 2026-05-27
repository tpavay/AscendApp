import SwiftUI

struct RecordsSection: View {
    let records: ProfileRecordSummary
    let totalClimbsCompleted: Int
    let workouts: [Workout]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProfileSectionHeaderView(title: "Records")

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
            } else if let effort = records.featuredBestEffort {
                bestEffortRow(effort)
            }
        }
    }

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ]
    }

    private func recordCard(_ record: ProfileRecordSummary.PersonalRecord) -> some View {
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

    private func bestEffortRow(_ effort: RankedBestEffort) -> some View {
        NavigationLink {
            BestEffortsListView(workouts: workouts)
        } label: {
            ProfileCardSurfaceView {
                HStack(spacing: 12) {
                    Image("best-effort-laurel-wreath")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 42, height: 38)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("BEST EFFORTS")
                            .font(.montserratBold(size: 11))
                            .foregroundStyle(ProfileVisualStyle.secondaryText)
                            .tracking(1.1)

                        Text("\(effort.metric.title) · \(effort.valueText)")
                            .font(.montserratSemiBold(size: 13))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }

                    Spacer()

                    Text("More records")
                        .font(.montserratSemiBold(size: 12))
                        .foregroundStyle(Color.accentColor)
                }
                .padding(12)
            }
        }
        .buttonStyle(.plain)
    }
}

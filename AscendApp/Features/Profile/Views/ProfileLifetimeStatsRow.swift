import SwiftUI

/// Strava-style inline lifetime stat band shown directly under the identity hero. These are the
/// at-a-glance career totals — they replace the Record Book's old lifetime list. Every stair
/// session counts as a climb, so "Climbs" is the total session count, not just landmark Climbs.
struct ProfileLifetimeStatsRow: View {
    let climbs: Int
    let steps: Int
    let durationSeconds: Int
    let averageStepsPerMinute: Double

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            stat(value: "\(climbs)", label: "Climbs")
            stat(value: Self.compact(steps), label: "Steps")
            stat(value: durationText, label: "Duration")
            stat(value: spmText, label: "Avg SPM")
        }
    }

    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.montserratMedium(size: 10))
                .foregroundStyle(ProfileVisualStyle.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(value)
                .font(.montserratBold(size: 14))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private var durationText: String {
        guard durationSeconds > 0 else { return "0h" }
        let hours = durationSeconds / 3600
        let minutes = (durationSeconds % 3600) / 60
        return hours > 0 ? "\(hours)h" : "\(minutes)m"
    }

    private var spmText: String {
        guard averageStepsPerMinute > 0 else { return "—" }
        return "\(Int(averageStepsPerMinute.rounded()))"
    }

    static func compact(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fk", Double(value) / 1_000)
        }
        return "\(value)"
    }
}

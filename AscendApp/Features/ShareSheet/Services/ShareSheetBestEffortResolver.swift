import Foundation

/// Turns a workout's ranked best efforts into the share sheet's one-line records.
///
/// A best effort is the climber's own top three for a measure, counted all-time and for this
/// year, so one measure can appear twice. Each measure counts once, at its best ranking, and the
/// list keeps the app's own significance order so the first entry is the one the finish screen
/// features.
enum ShareSheetBestEffortResolver {
    static func resolve(_ efforts: [RankedBestEffort]) -> [ShareSheetSubject.BestEffort] {
        var seen: [String: Int] = [:]
        var ordered: [ShareSheetSubject.BestEffort] = []

        for effort in efforts {
            let measureID = effort.metric.id
            let entry = ShareSheetSubject.BestEffort(
                id: measureID,
                rankText: BestEffortFormatting.ordinal(effort.rank).uppercased(),
                scopeText: effort.scope == .allTime ? "ALL-TIME" : "THIS YEAR",
                title: effort.metric.title.uppercased(),
                rank: effort.rank
            )

            if let index = seen[measureID] {
                if entry.rank < ordered[index].rank {
                    ordered[index] = entry
                }
            } else {
                seen[measureID] = ordered.count
                ordered.append(entry)
            }
        }

        return ordered
    }
}

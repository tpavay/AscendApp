import Foundation

enum ClimbEstimatedTimeFormatter {
    static func estimatedTimeText(for stepCount: Int, spm: Int) -> String {
        guard spm > 0 else { return "--" }

        let totalMinutes = max(Int((Double(stepCount) / Double(spm)).rounded()), 1)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return minutes == 0 ? "~\(hours)h" : "~\(hours)h \(minutes)m"
        }

        return "~\(totalMinutes) min"
    }
}

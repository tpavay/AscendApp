import SwiftUI

/// A routine drawn as one continuous topographic ridge - a smooth curve through the centre of
/// every interval, on the time axis, closed to the baseline unless only the ridge line is
/// wanted.
///
/// A path has no minimum width per interval, which is why the overview above the builder's
/// working window is this and not blocks: it holds forty intervals as easily as five. The
/// routine detail screen's hero draws the same curve, so one routine cannot have two shapes.
struct RoutineRidgeShape: Shape {
    let intervals: [RoutineInterval]
    let totalDuration: TimeInterval
    /// Only the ridge line, for stroking over the filled shape.
    var strokeOnly: Bool = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !intervals.isEmpty, totalDuration > 0 else { return path }

        let baseline = rect.maxY
        let availableHeight = rect.height

        // One point per interval, anchored at both edges so the ridge starts and ends level
        // with the intervals that own those edges rather than falling to the floor.
        var ridgePoints: [CGPoint] = []

        let firstY = baseline - CGFloat(RoutineIntervalScale.heightFraction(of: intervals[0])) * availableHeight
        ridgePoints.append(CGPoint(x: 0, y: firstY))

        var cumulativeTime: TimeInterval = 0
        for interval in intervals {
            let centerTime = cumulativeTime + interval.duration / 2
            let centerX = CGFloat(centerTime / totalDuration) * rect.width
            let y = baseline - CGFloat(RoutineIntervalScale.heightFraction(of: interval)) * availableHeight
            ridgePoints.append(CGPoint(x: centerX, y: y))
            cumulativeTime += interval.duration
        }

        let lastY = baseline
            - CGFloat(RoutineIntervalScale.heightFraction(of: intervals[intervals.count - 1])) * availableHeight
        ridgePoints.append(CGPoint(x: rect.width, y: lastY))

        if strokeOnly {
            path.move(to: ridgePoints[0])
        } else {
            path.move(to: CGPoint(x: 0, y: baseline))
            path.addLine(to: ridgePoints[0])
        }

        for index in 0..<ridgePoints.count - 1 {
            let current = ridgePoints[index]
            let next = ridgePoints[index + 1]
            // Control points level with each endpoint pull the curve into smooth,
            // horizontal-feeling transitions rather than a zigzag.
            let midX = (current.x + next.x) / 2
            path.addCurve(
                to: next,
                control1: CGPoint(x: midX, y: current.y),
                control2: CGPoint(x: midX, y: next.y)
            )
        }

        if !strokeOnly {
            path.addLine(to: CGPoint(x: rect.width, y: baseline))
            path.closeSubpath()
        }

        return path
    }
}

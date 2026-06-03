import SwiftUI

/// Hero-sized visualization of a routine's interval shape rendered as a continuous
/// topographic silhouette — the routine's primary visual identity per CLAUDE.md's
/// "Routines" guidance. Each interval becomes a peak or valley in a smoothly
/// curved mountain-ridge profile, on-brand with Ascend's climbing metaphor.
struct RoutineHeroVisualization: View {
    let intervals: [RoutineInterval]
    let totalDuration: TimeInterval
    var height: CGFloat = 200

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .bottom) {
            backgroundLayer

            silhouetteLayer
                .padding(.horizontal, 12)
                .padding(.top, 18)
                .padding(.bottom, 28)

            horizonLine
                .padding(.horizontal, 12)
                .padding(.bottom, 28)

            timelineLabels
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        ZStack {
            Color(hex: "0A0A0A")

            // Soft warm ambient from below — like horizon dawn light
            LinearGradient(
                colors: [
                    .clear,
                    accentColor.opacity(0.06),
                    accentColor.opacity(0.12)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // MARK: - Silhouette

    private var silhouetteLayer: some View {
        ZStack {
            // Filled ridge — gradient from accent at the top to transparent at base
            TopographicSilhouetteShape(intervals: intervals, totalDuration: totalDuration)
                .fill(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(0.85),
                            accentColor.opacity(0.35),
                            accentColor.opacity(0.05)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Crisp stroke along the ridge line itself
            TopographicSilhouetteShape(intervals: intervals, totalDuration: totalDuration, strokeOnly: true)
                .stroke(accentColor.opacity(0.95), lineWidth: 1.5)
                .shadow(color: accentColor.opacity(0.55), radius: 8, x: 0, y: 0)
        }
    }

    // MARK: - Horizon line (subtle ground indicator)

    private var horizonLine: some View {
        VStack {
            Spacer()
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            .clear,
                            .white.opacity(0.18),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
        }
    }

    // MARK: - Timeline labels

    private var timelineLabels: some View {
        HStack {
            Text("0:00")
            Spacer()
            Text(totalDurationLabel)
        }
        .font(.montserratRegular(size: 11))
        .foregroundStyle(Color.white.opacity(0.45))
    }

    // MARK: - Helpers

    private var accentColor: Color {
        Color(red: 0.706, green: 0.8, blue: 0)
    }

    private var totalDurationLabel: String {
        let totalSeconds = Int(totalDuration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(seconds.formatted(.number.precision(.integerLength(2))))"
    }
}

// MARK: - Topographic silhouette shape

/// Renders a smooth ridge profile through the center of each interval, with
/// curved transitions between peaks and valleys. Optionally renders only the
/// top ridge line (no closed bottom) for stroking on top of the filled shape.
private struct TopographicSilhouetteShape: Shape {
    let intervals: [RoutineInterval]
    let totalDuration: TimeInterval
    var strokeOnly: Bool = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !intervals.isEmpty, totalDuration > 0 else { return path }

        let baseline = rect.maxY
        let availableHeight = rect.height

        // Build ridge points: one per interval, plus boundary points at left/right edges
        var ridgePoints: [CGPoint] = []

        // Start anchor at left edge, height = first interval's height
        let firstY = baseline - CGFloat(intervals[0].intensityTier.heroHeightMultiplier) * availableHeight
        ridgePoints.append(CGPoint(x: 0, y: firstY))

        // Center point of each interval
        var cumulativeTime: TimeInterval = 0
        for interval in intervals {
            let centerTime = cumulativeTime + interval.duration / 2
            let xRatio = centerTime / totalDuration
            let centerX = CGFloat(xRatio) * rect.width
            let y = baseline - CGFloat(interval.intensityTier.heroHeightMultiplier) * availableHeight
            ridgePoints.append(CGPoint(x: centerX, y: y))
            cumulativeTime += interval.duration
        }

        // End anchor at right edge, height = last interval's height
        let lastY = baseline - CGFloat(intervals.last!.intensityTier.heroHeightMultiplier) * availableHeight
        ridgePoints.append(CGPoint(x: rect.width, y: lastY))

        // Draw the ridge — smooth cubic bezier curves between consecutive points
        if strokeOnly {
            path.move(to: ridgePoints[0])
        } else {
            // Filled version starts at bottom-left, goes up to ridge start
            path.move(to: CGPoint(x: 0, y: baseline))
            path.addLine(to: ridgePoints[0])
        }

        for i in 0..<ridgePoints.count - 1 {
            let current = ridgePoints[i]
            let next = ridgePoints[i + 1]
            // Horizontal-tangent control points create smooth flowing curves
            // (control points level with each endpoint pull the curve into smooth horizontal-feeling transitions)
            let midX = (current.x + next.x) / 2
            path.addCurve(
                to: next,
                control1: CGPoint(x: midX, y: current.y),
                control2: CGPoint(x: midX, y: next.y)
            )
        }

        if !strokeOnly {
            // Close back to the baseline
            path.addLine(to: CGPoint(x: rect.width, y: baseline))
            path.closeSubpath()
        }

        return path
    }
}

private extension IntensityTier {
    /// Height profile for the topographic silhouette. Slightly compressed at the
    /// low end so even "minimal" intervals have visible ground presence.
    var heroHeightMultiplier: Double {
        switch self {
        case .minimal:
            return 0.22
        case .light:
            return 0.40
        case .moderate:
            return 0.60
        case .high:
            return 0.80
        case .maximum:
            return 1.0
        }
    }
}

#Preview("Pyramid") {
    RoutineHeroVisualization(
        intervals: BuiltInRoutines.previewTemplates[0].intervals,
        totalDuration: BuiltInRoutines.previewTemplates[0].totalDuration
    )
    .padding(20)
    .background(Color.black)
    .preferredColorScheme(.dark)
}

#Preview("Mixed") {
    RoutineHeroVisualization(
        intervals: BuiltInRoutines.previewTemplates[5].intervals,
        totalDuration: BuiltInRoutines.previewTemplates[5].totalDuration
    )
    .padding(20)
    .background(Color.black)
    .preferredColorScheme(.dark)
}

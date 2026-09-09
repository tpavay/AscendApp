import SwiftUI

/// The Just Me tab's top-right heart-rate readout: a ring split into the three
/// live effort zones (`HeartRateZone`) with the current BPM centered inside,
/// colored to match. This is the only heart-rate surface Just Me draws - it
/// replaces `LiveHeartRateStatusChip` there entirely rather than sitting
/// alongside it. The Leaderboard tab is unaffected and keeps the chip.
struct LiveHeartRateZoneRingBadge: View {
    let status: LiveHeartRateStatus

    /// The ring spans 0%-105% of estimated max heart rate so the push zone's
    /// upper edge isn't flush against the ring's own end.
    private static let displayFractionCap = 1.05
    private static let segmentGap = 0.012

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 3))

            Circle()
                .stroke(ringGradient, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Circle()
                .fill(Color.black.opacity(0.74))
                .padding(4)

            content
        }
        .frame(width: 34, height: 34)
        .animation(.smooth(duration: 0.3), value: status)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.accessibilityText)
    }

    @ViewBuilder
    private var content: some View {
        switch status {
        case .connected(let beatsPerMinute, let zone):
            Text(beatsPerMinute.formatted())
                .font(.montserratBold(size: 11))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(zone.color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        case .connecting, .reconnecting:
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
        case .signalLost:
            Image(systemName: "heart.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
        case .failed:
            Image(systemName: "heart.slash.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    /// A neutral ring outside `.connected` - there is no zone to color it by.
    private var ringGradient: AngularGradient {
        guard case .connected = status else {
            return AngularGradient(colors: [.white.opacity(0.22)], center: .center)
        }

        let recoveryEnd = HeartRateZoneProfile.recoveryUpperFraction / Self.displayFractionCap
        let aerobicEnd = HeartRateZoneProfile.aerobicUpperFraction / Self.displayFractionCap
        let gap = Self.segmentGap

        return AngularGradient(gradient: Gradient(stops: [
            .init(color: HeartRateZone.recovery.color, location: 0),
            .init(color: HeartRateZone.recovery.color, location: recoveryEnd - gap),
            .init(color: HeartRateZone.aerobic.color, location: recoveryEnd + gap),
            .init(color: HeartRateZone.aerobic.color, location: aerobicEnd - gap),
            .init(color: HeartRateZone.push.color, location: aerobicEnd + gap),
            .init(color: HeartRateZone.push.color, location: 1),
        ]), center: .center)
    }
}

import SwiftUI

/// The heart-rate slot for a climb that has none yet.
///
/// Every phase says something. A climber who is waiting is told Ascend is still looking; one
/// who has never connected Health is offered the connection; one whose wearable never wrote
/// anything is told Ascend has stopped. The slot is never blank - a blank was the bug (#438).
///
/// The copy names no device. Heart rate reaches Ascend as Apple Health samples whoever wrote
/// them, so a Garmin, a Whoop, a Polar and an Apple Watch all arrive here identically, and
/// naming one of them tells the other three they are not supported.
struct WorkoutHeartRateRecoveryCard: View {
    let phase: AppleHealthEnrichmentService.Phase
    let message: String?
    let effectiveColorScheme: ColorScheme
    let onPrimaryAction: () -> Void

    private var primaryTextColor: Color {
        effectiveColorScheme == .dark ? .white : .black
    }

    private var secondaryTextColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.62) : .black.opacity(0.58)
    }

    private var cardFill: Color {
        effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06)
    }

    private var borderColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15)
    }

    private var isChecking: Bool {
        phase == .checking
    }

    private var title: String {
        switch phase {
        case .checking:
            return "Checking Apple Health"
        case .waiting:
            return "Waiting on your wearable"
        case .stoppedLooking:
            return "Stopped looking"
        case .connectionOffered:
            return "Connect Apple Health"
        case .accessRevoked:
            return "Apple Health access is off"
        case .unavailable:
            return "Apple Health unavailable"
        case .notApplicable:
            return "Heart rate"
        }
    }

    private var detail: String {
        if let message, !message.isEmpty {
            return message
        }

        switch phase {
        case .checking:
            return "Reading heart rate for this climb."
        case .waiting:
            return "Your watch, strap or band writes to Apple Health on its own schedule. Ascend keeps checking and adds your heart rate the moment it lands."
        case .stoppedLooking:
            return "Nothing reached Apple Health for this climb. Check one more time once your wearable has synced."
        case .connectionOffered:
            return "Ascend reads heart rate from Apple Health - whichever watch, strap or band you wear. Connect it to put heart rate on this climb."
        case .accessRevoked:
            return "Turn Ascend back on under Heart Rate in the Health app, then check again."
        case .unavailable:
            return "This device cannot read Apple Health data."
        case .notApplicable:
            return ""
        }
    }

    private var actionTitle: String? {
        switch phase {
        case .connectionOffered:
            return "Connect"
        case .waiting, .stoppedLooking, .checking:
            return "Check now"
        case .accessRevoked, .unavailable, .notApplicable:
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Heart Rate")
                    .font(.montserratSemiBold(size: 20))
                    .foregroundStyle(primaryTextColor)

                Spacer()

                if isChecking {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.red)
                }
            }

            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "heart")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(.red.opacity(effectiveColorScheme == .dark ? 0.16 : 0.1))
                    )

                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.montserratSemiBold(size: 15))
                        .foregroundStyle(primaryTextColor)

                    Text(detail)
                        .font(.montserratMedium(size: 12))
                        .foregroundStyle(secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)

                    if let actionTitle {
                        Button(action: onPrimaryAction) {
                            Label(actionTitle, systemImage: "arrow.clockwise")
                                .font(.montserratBold(size: 12))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 14)
                                .frame(height: 34)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.accent)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(isChecking)
                        .opacity(isChecking ? 0.62 : 1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(borderColor, lineWidth: 1)
                    )
            )
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            WorkoutHeartRateRecoveryCard(
                phase: .waiting(nextCheckAt: nil),
                message: nil,
                effectiveColorScheme: .dark,
                onPrimaryAction: {}
            )

            WorkoutHeartRateRecoveryCard(
                phase: .checking,
                message: nil,
                effectiveColorScheme: .dark,
                onPrimaryAction: {}
            )

            WorkoutHeartRateRecoveryCard(
                phase: .stoppedLooking,
                message: nil,
                effectiveColorScheme: .dark,
                onPrimaryAction: {}
            )

            WorkoutHeartRateRecoveryCard(
                phase: .connectionOffered,
                message: nil,
                effectiveColorScheme: .dark,
                onPrimaryAction: {}
            )

            WorkoutHeartRateRecoveryCard(
                phase: .accessRevoked,
                message: nil,
                effectiveColorScheme: .dark,
                onPrimaryAction: {}
            )
        }
        .padding(20)
    }
    .background(Color.black)
}

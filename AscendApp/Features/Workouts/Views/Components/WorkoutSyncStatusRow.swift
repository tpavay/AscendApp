import SwiftUI

/// One inline row saying whether this climb has reached the climber's account.
///
/// Every state is the same row in the same place; only the colour and whether there is something
/// to tap change. That is the whole design: the words never move through the failed states, because
/// `Couldn't sync this climb` is a statement about safety, and a retry that is running has not made
/// the climb any safer. Only the control changes.
///
/// The predecessor was a card gated on `remoteSyncStatus == .rejected || isRetrying`, which
/// unmounted the instant a climber tapped and again when the retry was refused. This one is driven
/// by `WorkoutSyncPresentation`, which asks only whether the climb is in the cloud.
struct WorkoutSyncStatusRow: View {
    let presentation: WorkoutSyncPresentation
    let effectiveColorScheme: ColorScheme
    let onRetry: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Rendering nothing is this row's own job, not its caller's, so the row can be mounted
    // unconditionally. A caller that wrapped it in `if presentation != .hidden` would have to read
    // the presentation in its own body, which is how the state driving one small row ends up
    // invalidating a whole screen.
    var body: some View {
        if presentation.showsRow {
            statusContent
        }
    }

    private var statusContent: some View {
        HStack(alignment: .center, spacing: 12) {
            if let iconName {
                Image(systemName: iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(textColor)
                    // The text already says it; a second announcement is noise.
                    .accessibilityHidden(true)
            }

            Text(statusText)
                .font(.montserratSemiBold(size: 13))
                .foregroundStyle(textColor)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            if presentation.showsRetryControl {
                retryControl
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    // Enablement comes from `WorkoutSyncPresentation.isRetryControlEnabled` rather than from a
    // switch with a `default:` arm, so the property the tests assert on is the one the shipped row
    // consults. A new presentation case cannot make the two disagree.
    @ViewBuilder
    private var retryControl: some View {
        if presentation.isRetryControlEnabled {
            Button(action: onRetry) {
                Text("TRY AGAIN")
                    .font(.montserratBold(size: 12))
                    .foregroundStyle(Color.ascendAccent)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 8)
                    // `.frame(minHeight:)` sizes the view, not the hit area, so the tappable
                    // region would otherwise stay the label's bounds.
                    .contentShape(.rect)
            }
            .accessibilityLabel("Try again")
        } else if presentation == .couldNotSyncOffline {
            Text("OFFLINE")
                .font(.montserratBold(size: 12))
                .foregroundStyle(Color.customGray)
                .padding(.vertical, 10)
                .padding(.horizontal, 8)
                .accessibilityLabel("Offline")
        } else {
            HStack(spacing: 6) {
                // The one animation on this row, and Reduce Motion drops it. Everything else is a
                // hard cut in both motion modes - animating a warning's departure emphasises the
                // thing leaving rather than the answer arriving.
                if !reduceMotion {
                    ProgressView()
                        .controlSize(.mini)
                }
                Text("SYNCING")
                    .font(.montserratBold(size: 12))
            }
            .foregroundStyle(Color.customGray)
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .accessibilityLabel("Syncing")
        }
    }

    private var statusText: String {
        switch presentation {
        case .hidden:
            return ""
        case .syncing:
            return "Syncing"
        case .couldNotSync, .couldNotSyncOffline, .couldNotSyncRetrying:
            return "Couldn't sync this climb"
        case .synced:
            return "Synced"
        }
    }

    private var textColor: Color {
        switch presentation {
        case .couldNotSync, .couldNotSyncOffline, .couldNotSyncRetrying:
            return Color.ascendCaution
        case .synced:
            return Color.ascendAccent
        case .syncing, .hidden:
            return effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray
        }
    }

    private var iconName: String? {
        switch presentation {
        case .hidden:
            return nil
        case .syncing:
            return "arrow.triangle.2.circlepath"
        case .couldNotSync, .couldNotSyncOffline, .couldNotSyncRetrying:
            return "exclamationmark.triangle.fill"
        case .synced:
            return "checkmark.circle.fill"
        }
    }
}

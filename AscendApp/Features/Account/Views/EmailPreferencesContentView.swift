import SwiftUI

/// Everything the Email preference screen actually shows: one switch, one
/// paragraph, and the line that only appears when something needs saying.
///
/// Split from `EmailPreferencesView` so the states can be rendered and read
/// back without a scroll view or navigation chrome in the way.
///
/// The paragraph names categories rather than individual emails so a new email
/// type lands inside an existing bucket and this copy never has to be rewritten.
/// There is deliberately no line about account and security mail: the switch is
/// not labelled a blanket email switch, and the paragraph already says what
/// these emails are.
///
/// Nothing here animates. The failure line appears in the same frame the write
/// fails, in every Reduce Motion state, and no crossfade is applied to it in any
/// form.
struct EmailPreferencesContentView: View {
    let viewModel: EmailPreferencesViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProfileCardSurface {
                consentRow
            }

            Text(
                "Ascend emails you when a climb drops, when you hit a milestone worth marking, and when something about your account or the app is worth knowing. Nothing daily. Nothing noisy."
            )
            .font(.montserratRegular(size: 13.5))
            .foregroundStyle(.white.opacity(0.62))
            .lineSpacing(5.5)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
        }
    }

    /// The label is part of the control rather than a sibling of it, so the
    /// whole row is one 44pt-plus target and one VoiceOver element.
    private var consentRow: some View {
        Toggle(isOn: toggleBinding) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Ascend emails")
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(.white)

                if let statusMessage {
                    Text(statusMessage)
                        .font(.montserratRegular(size: 13))
                        .foregroundStyle(statusColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.switch)
        .tint(.accent)
        .disabled(viewModel.isToggleDisabled)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(minHeight: 44)
        .opacity(viewModel.isUpdating ? 0.68 : 1)
    }

    private var toggleBinding: Binding<Bool> {
        // The view model stays the single source of truth for the switch: it
        // reverts itself when a write fails, and the unsubscribe link can
        // change the stored value from outside the app.
        Binding(
            get: { viewModel.isLifecycleEmailsEnabled },
            set: { isEnabled in
                Task {
                    await viewModel.setLifecycleEmailsEnabled(isEnabled)
                }
            }
        )
    }

    /// Nothing sits under the label in the settled states. It earns a line only
    /// while the value is unknown or the last save did not land.
    private var statusMessage: String? {
        if let errorMessage = viewModel.errorMessage {
            return errorMessage
        }

        switch viewModel.loadState {
        case .loading:
            return "Checking your email settings…"
        case .ready, .failed:
            return nil
        }
    }

    private var statusColor: Color {
        viewModel.errorMessage == nil ? .white.opacity(0.64) : .orange
    }
}

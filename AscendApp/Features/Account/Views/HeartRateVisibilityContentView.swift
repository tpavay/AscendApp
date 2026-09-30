import SwiftUI

/// Everything the Heart Rate privacy screen shows: one switch and the paragraph that says exactly
/// what it governs. Split from `HeartRateVisibilityView` so its states render without navigation
/// chrome in the way.
struct HeartRateVisibilityContentView: View {
    let viewModel: HeartRateVisibilityViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProfileCardSurface {
                visibilityRow
            }

            if viewModel.loadState == .failed {
                retryRow
            }

            Text(
                "Climbers who compare profiles with you see your average and max heart rate. Turn this off and they see neither. You still see your own."
            )
            .font(.montserratRegular(size: 13.5))
            .foregroundStyle(.white.opacity(0.62))
            .lineSpacing(5.5)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
        }
    }

    private var retryRow: some View {
        Button {
            Task {
                await viewModel.load()
            }
        } label: {
            HStack(spacing: 10) {
                Text(viewModel.errorMessage ?? "Couldn't load your heart rate setting.")
                    .font(.montserratMedium(size: 13))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Text("RETRY")
                    .font(.montserratBold(size: 12))
                    .foregroundStyle(.accent)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Retry loading your heart rate setting")
    }

    /// The label is part of the control, so the whole row is one target and one VoiceOver element.
    private var visibilityRow: some View {
        Toggle(isOn: toggleBinding) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Show my heart rate on my profile")
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                if let statusMessage {
                    Text(statusMessage)
                        .font(.montserratRegular(size: 13))
                        .foregroundStyle(viewModel.errorMessage == nil ? .white.opacity(0.64) : .orange)
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
        Binding(
            get: { viewModel.isPublic },
            set: { isPublic in
                Task {
                    await viewModel.setIsPublic(isPublic)
                }
            }
        )
    }

    private var statusMessage: String? {
        switch viewModel.loadState {
        case .loading:
            return "Checking your setting…"
        case .failed:
            return nil
        case .ready:
            return viewModel.isUpdating ? "Updating your profile…" : viewModel.errorMessage
        }
    }
}

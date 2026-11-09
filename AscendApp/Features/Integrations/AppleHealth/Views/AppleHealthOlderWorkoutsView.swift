import SwiftUI

/// Settings -> Apple Health -> Import older workouts. Onboarding's "We found your climbs" in the
/// Connect flow's own chrome: the close X, the same body and range row, and one button.
struct AppleHealthOlderWorkoutsView: View {
    @State private var viewModel: AppleHealthOlderWorkoutsViewModel
    let onClose: () -> Void

    init(viewModel: AppleHealthOlderWorkoutsViewModel? = nil, onClose: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel ?? AppleHealthOlderWorkoutsViewModel())
        self.onClose = onClose
    }

    static let footnote = "Past climbs fill your history and personal bests, never the leaderboards."
    static let nothingTitle = "NOTHING OLDER TO ADD."
    static let nothingDetail = "Every stair stepper workout Apple Health holds from before you joined is already in."
    static let unavailableTitle = "COULDN'T READ APPLE HEALTH."
    static let unavailableDetail = "Close this and try again."

    var body: some View {
        OnboardingScaffold(
            background: { Color.black },
            content: { layout in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Spacer().frame(height: HealthFlowChrome.contentTopClearance)

                        content

                        // Room for the bar laid over the content.
                        Spacer(minLength: 200)
                    }
                    .padding(.horizontal, layout.horizontalPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
            },
            bottomContent: { layout in
                HealthFlowBottomBar(
                    primaryTitle: primaryTitle,
                    primaryHeight: layout.primaryButtonHeight,
                    caption: caption,
                    secondaryTitle: choice == nil ? nil : "Not now",
                    isDisabled: viewModel.isImporting || isLoading,
                    onPrimary: primaryAction,
                    onSecondary: onClose
                )
                // The body scrolls under the bar, so the bar is solid down to the screen's edge and the
                // body fades into it instead of being cut.
                .padding(.top, 10)
                .background(Color.black.padding(.horizontal, -layout.horizontalPadding).padding(.bottom, -layout.bottomPadding))
                .overlay(alignment: .top) {
                    LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: 40)
                        .alignmentGuide(.top) { $0[.bottom] }
                        .allowsHitTesting(false)
                }
            }
        )
        .healthFlowCloseControl(action: onClose)
        .preferredColorScheme(.dark)
        .task { await viewModel.load() }
        .trackOnce(screen: .appleHealthOlderWorkouts)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
        case .found(let choice):
            HealthHistoryContent(choice: choice)
        case .nothing:
            message(title: Self.nothingTitle, detail: Self.nothingDetail)
        case .unavailable:
            message(title: Self.unavailableTitle, detail: Self.unavailableDetail)
        }
    }

    private func message(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.montserratBold(size: 30))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text(detail)
                .font(.montserratRegular(size: 17))
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 40)
    }

    private var choice: HealthHistoryChoice? {
        if case .found(let choice) = viewModel.state { return choice }
        return nil
    }

    private var isLoading: Bool {
        if case .loading = viewModel.state { return true }
        return false
    }

    private var primaryTitle: String {
        choice?.primaryTitle.uppercased() ?? "DONE"
    }

    private var caption: String? {
        guard choice != nil else { return nil }
        return viewModel.errorMessage ?? Self.footnote
    }

    private func primaryAction() {
        guard choice != nil else {
            onClose()
            return
        }
        Task {
            if await viewModel.addToHistory() { onClose() }
        }
    }
}

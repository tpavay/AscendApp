import SwiftUI

/// Screen 12: what Ascend will send, shown as the notifications themselves, before iOS is asked.
///
/// The examples are the real sends, so the ask is specific: a nudge short of the weekly target
/// (only for a climber who set one), new gear, and a new climb. TURN ON goes
/// through ``ClimbDropNotificationState``; Not now declines without asking iOS.
struct OnboardingNotificationPrimerScreen: View {
    let coordinator: OnboardingV3Coordinator

    @State private var viewModel: NotificationPrimerViewModel

    init(coordinator: OnboardingV3Coordinator) {
        self.coordinator = coordinator
        _viewModel = State(wrappedValue: NotificationPrimerViewModel(coordinator: coordinator))
    }

    /// Phones this short (the SE) get tighter cards and spacing so the notifications, the copy and
    /// both buttons fit without scrolling; taller phones keep the design's measurements.
    private static let compactHeight: CGFloat = 720

    var body: some View {
        GeometryReader { screen in
            let isCompact = screen.size.height < Self.compactHeight

            ZStack(alignment: .top) {
                NotificationPrimerBackdrop()

                VStack(spacing: 0) {
                    OnboardingProgressHeader(step: .notificationPrimer)
                        .padding(.top, 9)

                    GeometryReader { proxy in
                        ScrollView {
                            content(isCompact: isCompact)
                                .frame(minHeight: proxy.size.height, alignment: .top)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actions
            }
        }
        .trackOnce(screen: .onboardingNotificationPrimer)
    }

    private func content(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: isCompact ? 8 : 10) {
                ForEach(Array(viewModel.content.examples.enumerated()), id: \.element.id) { index, example in
                    NotificationPrimerCard(example: example, isCompact: isCompact)
                        // They slide down from above, 0.5 s each and 0.35 s apart.
                        .onboardingEntrance(style: .rise(-30), delay: 0.2 + 0.35 * Double(index))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, isCompact ? 12 : 22)

            Spacer(minLength: isCompact ? 12 : 28)

            VStack(alignment: .leading, spacing: 10) {
                OnboardingHeadline(
                    NotificationPrimerContent.headlineLead,
                    accentLines: NotificationPrimerContent.headlineAccent,
                    size: isCompact ? 30 : 34
                )
                .onboardingEntrance(index: 0)

                Text(viewModel.content.body)
                    .onboardingSecondary()
                    .fixedSize(horizontal: false, vertical: true)
                    .onboardingEntrance(index: 1)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, isCompact ? 12 : 20)
        }
    }

    private var actions: some View {
        VStack(spacing: 4) {
            Button("Turn on") {
                Task { await viewModel.turnOn() }
            }
            .buttonStyle(.onboardingPrimary)

            Button("Not now") {
                Task { await viewModel.notNow() }
            }
            .buttonStyle(.onboardingQuietLink)
        }
        .disabled(viewModel.isRequesting)
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .init(x: 0.5, y: 0.25))
        )
    }
}

/// The stairwell behind the screen: the glow at the top of the climb sits behind the first notification
/// and everything under it fades to black, so the copy and buttons keep a plain ground.
///
/// Drawn as an overlay on a view that takes exactly the proposal, because a filled image reports
/// the size it scaled to and would widen the whole stack.
private struct NotificationPrimerBackdrop: View {
    var body: some View {
        Color.black
            .overlay(alignment: .top) {
                Image("OnboardingNotificationBackdrop")
                    .resizable()
                    .scaledToFill()
                    .offset(y: -300)
                    .brightness(0.12)
            }
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0), location: 0.25),
                        .init(color: .black, location: 0.62)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .clipped()
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

#Preview("Notification primer") {
    let suite = UserDefaults(suiteName: "onboarding-v3-primer-preview") ?? .standard
    let coordinator = OnboardingV3Coordinator(
        store: PreAuthOnboardingStore(userDefaults: suite),
        startingAt: .notificationPrimer
    )
    OnboardingV3FlowView(coordinator: coordinator)
}

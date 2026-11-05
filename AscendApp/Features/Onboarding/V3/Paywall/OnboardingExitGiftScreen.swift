import SwiftUI

/// Screen 14: the welcome gift. It shows every time the paywall is closed, for as long as the climber
/// holds no entitlement, so the deal is always one tap away.
///
/// The first visit asks for a tap on the box. Any later visit has already seen it, so the box opens
/// on its own.
struct OnboardingExitGiftScreen: View {
    let coordinator: OnboardingV3Coordinator
    @Environment(\.onboardingPaywallModel) private var injectedModel

    private var model: OnboardingPaywallModel { injectedModel ?? .live }

    @State private var isOpen = false
    @State private var showsFooter = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            background

            if let offer = model.giftOffer {
                content(offer: offer)
            } else {
                // The gift never opens without a product to open: back to the paywall, which sells.
                Color.clear.task { coordinator.go(to: .paywall) }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .task { await start() }
        .trackOnce(screen: .onboardingExitGift)
    }

    // MARK: - Layout

    private var background: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image("AuthStaircaseBackground")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: 520, alignment: .top)
                .clipped()
                .brightness(-0.5)
                .blur(radius: 8)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            LinearGradient(
                stops: [.init(color: .black.opacity(0), location: 0.35), .init(color: .black, location: 0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            GiftGlow()
        }
    }

    private func content(offer: WelcomeGiftOffer) -> some View {
        let copy = WelcomeGiftCopy(offer)

        return GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if isOpen {
                        openState(offer: offer, copy: copy)
                    } else {
                        closedState
                    }
                }
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.3) : nil, value: isOpen)
    }

    private var closedState: some View {
        VStack(spacing: 28) {
            VStack(spacing: 10) {
                Text("Before you go")
                    .onboardingKicker()
                    .onboardingEntrance(index: 0)

                Text("Open your\nwelcome gift.")
                    .paywallText(.black, size: 36, tracking: -0.02, relativeTo: .largeTitle)
                    .textCase(.uppercase)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .accessibilityAddTraits(.isHeader)
                    .onboardingEntrance(index: 1)

                Text("A better price, just for you.")
                    .onboardingSecondary()
                    .onboardingEntrance(index: 2)
            }
            .padding(.top, 70)

            Spacer(minLength: 10)

            Button(action: open) {
                WelcomeGiftBox(isOpen: false)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open your gift")

            Text("Tap to open")
                .paywallText(.bold, size: 15, relativeTo: .subheadline)
                .foregroundStyle(Color(hex: "BDBDBD"))
                .onboardingEntrance(index: 3)

            Spacer(minLength: 40)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }

    private func openState(offer: WelcomeGiftOffer, copy: WelcomeGiftCopy) -> some View {
        VStack(spacing: 0) {
            ZStack {
                WelcomeGiftBox(isOpen: true)
                    .offset(y: 110)

                WelcomeGiftVoucher(offer: offer, copy: copy)
                    .modifier(VoucherRise(reduceMotion: reduceMotion))
            }
            .padding(.horizontal, 26)
            .padding(.top, 44)

            Spacer(minLength: 16)

            if showsFooter {
                footer(copy: copy)
                    .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 14)))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func footer(copy: WelcomeGiftCopy) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                OnboardingHeadline(copy.headlineLead, accentLines: copy.headlineAccent, size: 30)

                Text(copy.subline)
                    .onboardingSecondary()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(spacing: 6) {
                Button {
                    Task { await claim() }
                } label: {
                    if model.activity == .purchasing {
                        ProgressView().tint(.black)
                    } else {
                        Text(copy.callToAction)
                    }
                }
                .buttonStyle(.onboardingPrimary)
                .paywallSheen()
                .disabled(model.isBusy)

                Text(copy.finePrint)
                    .paywallText(.medium, size: 12, relativeTo: .caption)
                    .foregroundStyle(Color(hex: "8E8E8E"))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                if let message = model.notice?.message {
                    Text(message)
                        .onboardingSecondary()
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .accessibilityAddTraits(.updatesFrequently)
                }

                Button("No thanks") { coordinator.go(to: .paywall) }
                    .buttonStyle(.plain)
                    .paywallText(.bold, size: 13, relativeTo: .footnote)
                    .foregroundStyle(Color(hex: "6E6E6E"))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .disabled(model.isBusy)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    // MARK: - Behaviour

    private func start() async {
        guard RemoteFeatureFlagStore.shared.isEnabled(.preAuthPaywall) else {
            coordinator.advance()
            return
        }

        // The plans may not be loaded when a relaunch resumes straight on this screen.
        if model.loadState == .loading { await model.load() }

        let hasSeenGift = coordinator.answers.welcomeGiftFirstShownAt != nil
        if !hasSeenGift {
            coordinator.update { $0.welcomeGiftFirstShownAt = Date() }
        } else if model.giftOffer != nil {
            // They have seen it: the box opens without asking again.
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            open()
        }
    }

    private func open() {
        guard !isOpen else { return }
        isOpen = true
        HapticsManager.shared.trigger(.mediumImpact)

        Task {
            // The stamp lands at 1.1 s and the footer rises at 0.9 s, as in the design.
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(OnboardingEntrance.curve(duration: 0.45)) { showsFooter = true }
            try? await Task.sleep(for: .milliseconds(200))
            HapticsManager.shared.trigger(.success)
        }
    }

    private func claim() async {
        switch await model.claimGift() {
        case .purchased(let startedTrial):
            HapticsManager.shared.trigger(.success)
            coordinator.update { $0.trialStarted = startedTrial }
            coordinator.advance()
        case .cancelled, .notCompleted:
            break
        }
    }
}

/// The voucher flies up from below with an overshoot: 0.75 s starting 0.35 s in.
private struct VoucherRise: ViewModifier {
    let reduceMotion: Bool
    @State private var risen = false

    func body(content: Content) -> some View {
        content
            .opacity(risen ? 1 : 0)
            .offset(y: risen || reduceMotion ? 0 : 160)
            .scaleEffect(risen || reduceMotion ? 1 : 0.6)
            .rotationEffect(.degrees(risen ? -2 : 8))
            .onAppear {
                withAnimation(
                    reduceMotion
                        ? .easeOut(duration: 0.3)
                        : .timingCurve(0.2, 0.9, 0.3, 1.1, duration: 0.75).delay(0.35)
                ) { risen = true }
            }
    }
}

/// The slow lime glow behind the gift.
private struct GiftGlow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bright = false

    var body: some View {
        RadialGradient(
            colors: [OnboardingV3Palette.accent.opacity(0.26), .clear],
            center: .center,
            startRadius: 0,
            endRadius: 190
        )
        .frame(height: 420)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 170)
        .opacity(reduceMotion ? 0.8 : (bright ? 1 : 0.6))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { bright = true }
        }
    }
}

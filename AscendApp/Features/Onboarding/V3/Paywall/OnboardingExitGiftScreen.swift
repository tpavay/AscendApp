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
                // One box for both states, so its lid and body animate when `isOpen` changes
                // instead of being replaced by a second view that starts out gone. The words around
                // it share the spare height evenly, which centres it until they need more, and keep
                // their room once hidden, so opening never moves it.
                ZStack(alignment: .top) {
                    VStack(spacing: 0) {
                        closedHeader
                            .padding(.top, 70)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .opacity(isOpen ? 0 : 1)
                            .accessibilityHidden(isOpen)

                        giftBox
                            .offset(y: 20)

                        Text("Tap to open")
                            .paywallText(.bold, size: 15, relativeTo: .subheadline)
                            .foregroundStyle(Color(hex: "BDBDBD"))
                            .multilineTextAlignment(.center)
                            .onboardingEntrance(index: 3)
                            .padding(.top, 36)
                            .padding(.bottom, 40)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            .opacity(isOpen ? 0 : 1)
                            .accessibilityHidden(isOpen)
                    }
                    .padding(.horizontal, 24)

                    if isOpen {
                        VStack(spacing: 0) {
                            WelcomeGiftVoucher(offer: offer, copy: copy)
                                .modifier(VoucherRise(reduceMotion: reduceMotion))
                                .padding(.horizontal, 26)
                                .padding(.top, 44)

                            Spacer(minLength: 16)

                            if showsFooter {
                                footer(copy: copy)
                                    .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 14)))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            // A scroll view draws its content on past the top safe area, which puts the voucher
            // behind the clock. The fade stays clear of the stamp, the highest thing at rest.
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: 8)
                    Color.black
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.3) : nil, value: isOpen)
    }

    private var closedHeader: some View {
        VStack(spacing: 10) {
            Text("Before you go")
                .onboardingKicker()
                .onboardingEntrance(index: 0)

            Text("Open your\nwelcome gift.")
                .paywallText(.black, size: 36, tracking: -0.02, relativeTo: .largeTitle)
                .textCase(.uppercase)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                // Without a line limit the text wraps mid-word instead of shrinking. Three lines is
                // "OPEN YOUR / WELCOME / GIFT.", the most it can take with every word whole.
                .lineLimit(3)
                .minimumScaleFactor(0.5)
                .accessibilityAddTraits(.isHeader)
                .onboardingEntrance(index: 1)

            Text("A better price, just for you.")
                .onboardingSecondary()
                .multilineTextAlignment(.center)
                .onboardingEntrance(index: 2)
        }
    }

    private var giftBox: some View {
        Button(action: open) {
            WelcomeGiftBox(isOpen: isOpen)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isOpen)
        .accessibilityLabel("Open your gift")
        .accessibilityHidden(isOpen)
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
                if model.isAwaitingConfirmation {
                    PaywallCheckAccessButton(model: model)
                } else {
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
                    .disabled(model.locksPurchase)
                }

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

                // The gift sells an auto-renewing subscription, so its terms are one tap away here
                // as they are on the paywall.
                HStack(spacing: 18) {
                    Link("Terms", destination: URL(string: "https://ascendstepper.com/terms")!)
                    Link("Privacy", destination: URL(string: "https://ascendstepper.com/privacy")!)
                }
                .paywallText(.semiBold, size: 12, relativeTo: .caption)
                .foregroundStyle(Color(hex: "8E8E8E"))
                .frame(minHeight: 36)

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
        // The stack above offers this half of its free height, because it shares it with a spacer.
        // Taken at face value that squeezes the do-not-purchase warning to one truncated line; a
        // footer too tall for a small phone scrolls instead.
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Behaviour

    private func start() async {
        model.resetNotice()

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
            .rotationEffect(.degrees(risen || reduceMotion ? -2 : 8))
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

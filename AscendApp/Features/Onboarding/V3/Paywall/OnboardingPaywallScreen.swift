import SwiftUI

/// Screen 13: the hard paywall before sign-in. Yearly, with Lifetime as the smaller card under it.
///
/// The close button fades in after three seconds and opens the welcome gift, every time. It is not
/// drawn while the store has no gift to open, because a close button with nothing behind it would
/// only be a way out of a paywall that has none.
struct OnboardingPaywallScreen: View {
    let coordinator: OnboardingV3Coordinator
    @Environment(\.onboardingPaywallModel) private var injectedModel

    private var model: OnboardingPaywallModel { injectedModel ?? .live }

    /// The close button's delay, from the design.
    static let closeDelay: Duration = .seconds(3)

    @State private var showsClose = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { proxy in
            // The photograph never takes more than a third of a short phone, so the plans and the
            // button stay on the first screen of the smallest one.
            let heroHeight = min(300, proxy.size.height * 0.34)

            ZStack(alignment: .top) {
                hero(width: proxy.size.width, height: heroHeight)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headline
                            .padding(.top, max(heroHeight - 110, 70))

                        perks

                        // At an accessibility size the plans and the button scroll with the page,
                        // because pinned they would cover it.
                        if dynamicTypeSize.isAccessibilitySize {
                            planCards
                            purchaseControls
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 16)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
            }
            .overlay(alignment: .topLeading) { closeButton }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 8) {
                        planCards
                        purchaseControls
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .background(
                        LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .init(x: 0.5, y: 0.18))
                            .ignoresSafeArea(edges: .bottom)
                    )
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .task { await start() }
        .task(id: model.giftOffer != nil) { await revealClose() }
        // Access can arrive while this screen is up: a purchase still confirming, an Ask to Buy
        // approved on another device, a restore. Whatever the route, a climber who holds it moves on.
        .onChange(of: model.holdsAccess) { _, holdsAccess in
            if holdsAccess { advanceHoldingAccess() }
        }
        .trackOnce(screen: .onboardingPaywall)
    }

    // MARK: - Pieces

    private func hero(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Color.black.frame(height: height)
            Color.clear
                .frame(width: width, height: height)
                .overlay {
                    Image("OnboardingPaywallHero")
                        .resizable()
                        .scaledToFill()
                        .accessibilityHidden(true)
                }
                .clipped()
        }
        .overlay {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.35), location: 0),
                    .init(color: .black.opacity(0), location: 0.25),
                    .init(color: .black.opacity(0.65), location: 0.72),
                    .init(color: .black, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: height + 4)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(height: height + 4, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(edges: .top)
    }

    private var headline: some View {
        Text("\(styled("Never climb a\n", .white))\(styled("boring minute\n", OnboardingV3Palette.accent))\(styled("again.", .white))")
            .textCase(.uppercase)
            .lineLimit(3)
            .minimumScaleFactor(0.5)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Never climb a boring minute again.")
            .accessibilityAddTraits(.isHeader)
    }

    @ScaledMetric(relativeTo: .title) private var headlineSize: CGFloat = 34

    private func styled(_ string: String, _ color: Color) -> Text {
        Text(string)
            .font(.custom("Montserrat-Black", fixedSize: headlineSize))
            .tracking(-headlineSize * 0.02)
            .foregroundStyle(color)
    }

    private var perks: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(PaywallPerk.all.enumerated()), id: \.element.title) { index, perk in
                PaywallPerkRow(perk: perk)
                    .paywallRowEntrance(index: index)
            }
        }
    }

    @ViewBuilder
    private var planCards: some View {
        switch model.loadState {
        case .loading:
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(OnboardingV3Palette.cardFill)
                .frame(height: 84)
                .padding(.top, 12)
                .overlay { ProgressView().tint(OnboardingV3Palette.accent) }
                .accessibilityLabel("Loading plans")
        case .unavailable:
            VStack(spacing: 10) {
                Text(OnboardingPaywallModel.Notice.plansUnavailable.message)
                    .onboardingSecondary()
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                Button("Try again") { Task { await model.load() } }
                    .buttonStyle(.onboardingQuietLink)
            }
            .padding(.top, 12)
        case .ready:
            VStack(spacing: 10) {
                if let yearly = model.yearly {
                    PaywallYearlyCard(
                        plan: yearly,
                        isSelected: model.selectedPlan?.id == yearly.id
                    ) { select(yearly) }
                }

                if let lifetime = model.lifetime {
                    PaywallLifetimeCard(
                        plan: lifetime,
                        isSelected: model.selectedPlan?.id == lifetime.id
                    ) { select(lifetime) }
                }
            }
            .disabled(model.locksPurchase)
        }
    }

    private var purchaseControls: some View {
        VStack(spacing: 8) {
            if let message = model.notice?.message, model.loadState == .ready {
                Text(message)
                    .onboardingSecondary()
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.updatesFrequently)
            }

            if model.isAwaitingConfirmation {
                PaywallCheckAccessButton(model: model)
            } else {
                Button {
                    Task { await purchase() }
                } label: {
                    if model.activity == .purchasing {
                        ProgressView().tint(.black)
                    } else {
                        Text(purchaseTitle)
                    }
                }
                .buttonStyle(.onboardingPrimary)
                .paywallSheen()
                .disabled(model.loadState != .ready || model.locksPurchase)
            }

            footer
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                footerRow
                VStack(spacing: 0) { footerRow }
            }

            // A climber with an account never has to pay to reach sign-in: the same exit the
            // welcome screen offers, into the same returning-mode sign-in.
            Button("Already climbing? Sign in") {
                model.releaseAskToBuyHold()
                coordinator.go(to: .auth)
            }
                .buttonStyle(.plain)
                .frame(minHeight: 36)
                .disabled(model.isBusy)
        }
        .paywallText(.semiBold, size: 12, relativeTo: .caption)
        .foregroundStyle(Color(hex: "8E8E8E"))
    }

    private var footerRow: some View {
        HStack(spacing: 18) {
            // Cancelling is only a thing for the plan that renews.
            Text(model.selectedPlan?.billing == .oneTime ? "Pay once. No renewal." : "Cancel anytime")

            Button(model.activity == .restoring ? "Restoring..." : "Restore") {
                Task { await restore() }
            }
            .disabled(model.isBusy)

            Link("Terms", destination: URL(string: "https://ascendstepper.com/terms")!)
            Link("Privacy", destination: URL(string: "https://ascendstepper.com/privacy")!)
        }
        .frame(minHeight: 36)
    }

    @ViewBuilder
    private var closeButton: some View {
        if showsClose, model.giftOffer != nil {
            Button {
                coordinator.go(to: .exitGift)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.5), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .padding(.leading, 20)
            .padding(.top, 8)
            .transition(.opacity)
        }
    }

    // MARK: - Behaviour

    private var purchaseTitle: String {
        guard let plan = model.selectedPlan else { return "Start climbing" }
        switch plan.billing {
        case .oneTime: return "Get lifetime access"
        case .subscription: return plan.trialActionDescription ?? "Start climbing"
        }
    }

    private func select(_ plan: NativePaywallPlan) {
        HapticsManager.shared.trigger(.selection)
        model.selectedPlanID = plan.id
    }

    private func start() async {
        // Off, the flow skips the paywall and the sign-in that follows hands the climber to the
        // paywall that sells after it.
        guard RemoteFeatureFlagStore.shared.isEnabled(.preAuthPaywall) else {
            advanceFromHere()
            return
        }

        model.markPaywallReached()
        await model.load()
        // Bought before a relaunch, or restored: nothing is left to sell.
        if model.holdsAccess { advanceHoldingAccess() }
    }

    /// Moves on only while this screen is still the one showing, so a purchase that completes and an
    /// entitlement that arrives a moment later cannot advance the flow twice - the second advance
    /// from sign-in would end it.
    private func advanceFromHere() {
        guard coordinator.step == .paywall else { return }
        coordinator.advance()
    }

    private func advanceHoldingAccess() {
        let startedTrial = model.recordHeldAccess()
        coordinator.update { $0.trialStarted = startedTrial }
        advanceFromHere()
    }

    private func revealClose() async {
        guard model.giftOffer != nil else {
            showsClose = false
            return
        }
        try? await Task.sleep(for: Self.closeDelay)
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.4)) { showsClose = true }
    }

    private func purchase() async {
        switch await model.purchaseSelectedPlan() {
        case .purchased(let startedTrial):
            HapticsManager.shared.trigger(.success)
            coordinator.update { $0.trialStarted = startedTrial }
            advanceFromHere()
        case .cancelled, .notCompleted:
            break
        }
    }

    private func restore() async {
        if await model.restore() == .restored {
            HapticsManager.shared.trigger(.success)
            advanceHoldingAccess()
        }
    }
}

// MARK: - Waiting on Apple

/// Stands in for the buy button while a purchase is unconfirmed: the screen says not to purchase
/// again, so the one action left re-checks without starting another.
struct PaywallCheckAccessButton: View {
    let model: OnboardingPaywallModel

    var body: some View {
        Button {
            Task { await model.checkAccess() }
        } label: {
            if model.activity == .checkingAccess {
                ProgressView().tint(.black)
            } else {
                Text("Check access")
            }
        }
        .buttonStyle(.onboardingPrimary)
        .disabled(model.isBusy)
    }
}

// MARK: - Perks

struct PaywallPerk: Equatable {
    enum Art: Equatable {
        case asset(String)
        case medal
    }

    let title: String
    let subtitle: String
    let art: Art

    static let all = [
        PaywallPerk(
            title: "Someone to chase",
            subtitle: "Real climbers' best climbs, every climb",
            art: .asset("AuthStaircaseBackground")
        ),
        PaywallPerk(
            title: "Proof you're improving",
            subtitle: "Records, splits and ranks after every climb",
            art: .medal
        ),
        PaywallPerk(
            title: "A reason to come back",
            subtitle: "Streaks, monthly events, gear to earn",
            art: .asset("Gear/golden_turkey")
        ),
        PaywallPerk(
            title: "Climbs that go somewhere",
            subtitle: "Summit real landmarks around the world",
            art: .asset("OnboardingLandmarkEmpireCard")
        )
    ]
}

private struct PaywallPerkRow: View {
    let perk: PaywallPerk

    var body: some View {
        HStack(spacing: 14) {
            art
                .frame(width: 52, height: 52)
                .background(Color(hex: "141414"))
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(Color(hex: "262626"), lineWidth: 1)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(perk.title)
                    .paywallText(.extraBold, size: 16, relativeTo: .headline)
                    .foregroundStyle(.white)

                Text(perk.subtitle)
                    .paywallText(.medium, size: 13, relativeTo: .footnote)
                    .foregroundStyle(Color(hex: "A0A0A0"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var art: some View {
        switch perk.art {
        case .asset(let name):
            Color.clear.overlay {
                Image(name)
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
        case .medal:
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white, Color(hex: "E8C34A"), Color(hex: "9C7A1C")],
                        center: .init(x: 0.35, y: 0.3),
                        startRadius: 0,
                        endRadius: 22
                    )
                )
                .overlay {
                    Text("1")
                        .font(.custom("Montserrat-Black", fixedSize: 17))
                        .foregroundStyle(.black)
                }
                .padding(7)
        }
    }
}

private struct PaywallRowEntrance: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    func body(content: Content) -> some View {
        content
            .opacity(hasAppeared ? 1 : 0)
            .offset(x: hasAppeared || reduceMotion ? 0 : -14)
            .onAppear {
                withAnimation(OnboardingEntrance.curve(duration: 0.4).delay(0.2 + 0.1 * Double(index))) {
                    hasAppeared = true
                }
            }
    }
}

private extension View {
    /// The row slides in from the left 0.1 s after the one above it.
    func paywallRowEntrance(index: Int) -> some View {
        modifier(PaywallRowEntrance(index: index))
    }
}

import SwiftUI

/// Screen 13: the hard paywall, shown to a signed-in climber who holds no entitlement. Yearly, with
/// Lifetime as the smaller card under it.
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
    private static let perkFadeHeight: CGFloat = 28
    private static let closeTopPadding: CGFloat = 8
    private static let closeSize: CGFloat = 44
    /// The page stops here, so nothing scrolls under the close button or into the status bar.
    private static let pageTopInset = closeTopPadding + closeSize
    private static let pageFadeHeight: CGFloat = 16
    @State private var showsClose = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { proxy in
            // The photograph never takes more than a third of a short phone, so the plans and the
            // button stay on the first screen of the smallest one.
            let heroHeight = min(300, proxy.size.height * 0.34)

            ZStack(alignment: .top) {
                hero(width: proxy.size.width, height: heroHeight)

                ScrollView {
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 20) {
                            headline
                                .padding(.top, max(heroHeight - 110, 70) - Self.pageTopInset)

                            perks
                        }
                        .padding(.horizontal, 22)

                        // At an accessibility size the plans and the button scroll with the page,
                        // because pinned they would cover it.
                        if dynamicTypeSize.isAccessibilitySize {
                            purchaseArea
                        }
                    }
                    .padding(.bottom, 16)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
                .mask {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: Self.pageFadeHeight)
                        Color.black
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
                .padding(.top, Self.pageTopInset)
            }
            .overlay(alignment: .topLeading) { closeButton }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !dynamicTypeSize.isAccessibilitySize {
                    purchaseArea
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .task { await start() }
        .task(id: model.giftOffer != nil) { await revealClose() }
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

    /// Opaque from the first card down: a locked card is dimmed, so it is translucent, and the message
    /// for a store with no plans has no card at all. Whatever passes behind it, the perks or the
    /// photograph, fades out above it instead of showing through.
    private var purchaseArea: some View {
        VStack(spacing: 8) {
            planCards
            purchaseControls
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 8)
        .background {
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: Self.perkFadeHeight)
                Color.black
            }
            .padding(.top, -Self.perkFadeHeight)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
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
                HStack(spacing: 18) { footerItems }
                VStack(spacing: 0) { footerItems }
            }
        }
        .multilineTextAlignment(.center)
        .paywallText(.semiBold, size: 12, relativeTo: .caption)
        .foregroundStyle(Color(hex: "8E8E8E"))
    }

    @ViewBuilder
    private var footerItems: some View {
        // Cancelling is only a thing for the plan that renews.
        Text(model.selectedPlan?.billing == .oneTime ? "Pay once. No renewal." : "Cancel anytime")
            .frame(minHeight: 36)

        Button(model.activity == .restoring ? "Restoring..." : "Restore") {
            Task { await restore() }
        }
        .frame(minHeight: 36)
        .disabled(model.isBusy)

        Link("Terms", destination: URL(string: "https://ascendstepper.com/terms")!)
            .frame(minHeight: 36)
        Link("Privacy", destination: URL(string: "https://ascendstepper.com/privacy")!)
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
                    .frame(width: Self.closeSize, height: Self.closeSize)
                    .background(Color.black.opacity(0.5), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .padding(.leading, 20)
            .padding(.top, Self.closeTopPadding)
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

    /// Access arriving - a purchase, a restore, an Ask to Buy approved elsewhere - needs no handling
    /// here: the root routes on the entitlement and takes the climber into the app.
    private func start() async {
        await model.load()
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
        case .cancelled, .notCompleted:
            break
        }
    }

    private func restore() async {
        if await model.restore() == .restored {
            HapticsManager.shared.trigger(.success)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// At an accessibility size the text needs the art's column, or its longest words break.
    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 14))
    }

    var body: some View {
        layout {
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

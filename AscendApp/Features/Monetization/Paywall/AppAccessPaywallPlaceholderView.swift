import StoreKit
import SwiftUI

struct AppAccessPaywallPlaceholderView: View {
    @Environment(MonetizationManager.self) private var monetizationManager

    private let initialPhase: AppAccessGatePhase
    private let initialRestoreState: AppAccessRestoreState
    private let initialPlans: [NativeSubscriptionPlan]
    private let initialStatusMessage: String?
    private let automaticallyStarts: Bool
    private let accountDeletionDismissalRevision: UInt
    private let onAccountDeletionFocusRestored: (() -> Void)?
    private let onDeleteAccount: @MainActor () -> Void
    private let onSignOut: () -> Void
    private let onRequestOnboardingBack: (@MainActor () -> Bool)?

    init(
        initialPhase: AppAccessGatePhase = .openingHosted,
        initialRestoreState: AppAccessRestoreState = .idle,
        initialPlans: [NativeSubscriptionPlan] = [],
        initialStatusMessage: String? = nil,
        automaticallyStarts: Bool = true,
        accountDeletionDismissalRevision: UInt = 0,
        onAccountDeletionFocusRestored: (() -> Void)? = nil,
        onRequestOnboardingBack: (@MainActor () -> Bool)? = nil,
        onDeleteAccount: @escaping @MainActor () -> Void,
        onSignOut: @escaping () -> Void = {}
    ) {
        self.initialPhase = initialPhase
        self.initialRestoreState = initialRestoreState
        self.initialPlans = initialPlans
        self.initialStatusMessage = initialStatusMessage
        self.automaticallyStarts = automaticallyStarts
        self.accountDeletionDismissalRevision = accountDeletionDismissalRevision
        self.onAccountDeletionFocusRestored = onAccountDeletionFocusRestored
        self.onRequestOnboardingBack = onRequestOnboardingBack
        self.onDeleteAccount = onDeleteAccount
        self.onSignOut = onSignOut
    }

    var body: some View {
        AppAccessPaywallContentView(
            manager: monetizationManager,
            initialPhase: initialPhase,
            initialRestoreState: initialRestoreState,
            initialPlans: initialPlans,
            initialStatusMessage: initialStatusMessage,
            automaticallyStarts: automaticallyStarts,
            accountDeletionDismissalRevision: accountDeletionDismissalRevision,
            onAccountDeletionFocusRestored: onAccountDeletionFocusRestored,
            onRequestOnboardingBack: onRequestOnboardingBack,
            onDeleteAccount: onDeleteAccount,
            onSignOut: onSignOut
        )
    }
}

private struct AppAccessPaywallContentView: View {
    @State private var coordinator: AppAccessPaywallCoordinator
    @State private var isShowingManageSubscriptions = false
    @AccessibilityFocusState private var focusedControl: FocusTarget?

    private let manager: MonetizationManager
    private let onDeleteAccount: @MainActor () -> Void
    private let onSignOut: () -> Void
    private let automaticallyStarts: Bool
    private let accountDeletionDismissalRevision: UInt
    private let onAccountDeletionFocusRestored: (() -> Void)?

    private enum FocusTarget: Hashable {
        case status
        case manageSubscription
        case deleteAccount
    }

    init(
        manager: MonetizationManager,
        initialPhase: AppAccessGatePhase,
        initialRestoreState: AppAccessRestoreState,
        initialPlans: [NativeSubscriptionPlan],
        initialStatusMessage: String?,
        automaticallyStarts: Bool,
        accountDeletionDismissalRevision: UInt,
        onAccountDeletionFocusRestored: (() -> Void)?,
        onRequestOnboardingBack: (@MainActor () -> Bool)?,
        onDeleteAccount: @escaping @MainActor () -> Void,
        onSignOut: @escaping () -> Void
    ) {
        self.manager = manager
        self.automaticallyStarts = automaticallyStarts
        self.accountDeletionDismissalRevision = accountDeletionDismissalRevision
        self.onAccountDeletionFocusRestored = onAccountDeletionFocusRestored
        _coordinator = State(
            initialValue: AppAccessPaywallCoordinator(
                monetizationManager: manager,
                initialPhase: initialPhase,
                initialRestoreState: initialRestoreState,
                initialPlans: initialPlans,
                initialStatusMessage: initialStatusMessage,
                onRequestOnboardingBack: onRequestOnboardingBack,
                // The hosted paywall's DELETE ACCOUNT control and this screen's own must open the
                // same dialog, so they are the same closure rather than two routes that can drift.
                onRequestAccountDeletion: onDeleteAccount
            )
        )
        self.onDeleteAccount = onDeleteAccount
        self.onSignOut = onSignOut
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero

                if coordinator.phase == .accessConfirmed {
                    successContent
                } else if coordinator.phase == .openingHosted || coordinator.phase == .hostedPresented {
                    openingContent
                } else {
                    nativeAndRecoveryContent
                }
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity, minHeight: 600, alignment: .center)
        }
        .scrollBounceBehavior(.basedOnSize)
        .themedBackground()
        .task {
            guard automaticallyStarts else { return }
            coordinator.start()
        }
        .onDisappear { coordinator.cancelOwnedWork() }
        .onChange(of: manager.identityGeneration) { _, _ in
            coordinator.identityDidChange()
        }
        .onChange(of: manager.entitlementState) { _, state in
            coordinator.entitlementDidChange(state)
        }
        .onChange(of: coordinator.phase) { _, phase in
            announcePhase(phase)
        }
        .onChange(of: coordinator.restoreState) { _, state in
            if let message = state.statusMessage {
                AccessibilityNotification.Announcement(message).post()
                focusedControl = .status
            }
        }
        .onChange(of: isShowingManageSubscriptions) { _, isPresented in
            if !isPresented { focusedControl = .manageSubscription }
        }
        .onChange(of: accountDeletionDismissalRevision) { _, _ in
            // A deletion raised from the hosted paywall dismissed that paywall to get here, so
            // backing out of it has to put the climber back on it. That unrenders the control the
            // climber came from, so focus is only restored when the gate is staying put.
            if coordinator.accountDeletionDialogDismissed() {
                AccessibilityNotification.Announcement("Reopening subscription options.").post()
            } else {
                focusedControl = .deleteAccount
            }
            onAccountDeletionFocusRestored?()
        }
        .manageSubscriptionsSheet(isPresented: $isShowingManageSubscriptions)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image("AppIconInternalAccent")
                .resizable()
                .scaledToFit()
                .frame(width: 54, height: 54)
                .accessibilityHidden(true)

            Text(title)
                .font(.montserratBold(size: 30))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            if let message = heroMessage {
                Text(message)
                    .font(.montserratMedium(size: 16))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("appAccessPaywallStatus")
                    .accessibilityFocused($focusedControl, equals: .status)
            }
        }
    }

    private var openingContent: some View {
        VStack(spacing: 16) {
            AscendLoadingIndicator(isPaused: coordinator.phase == .hostedPresented)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .accessibilityHidden(true)
        .accessibilityIdentifier("appAccessPaywallLoading")
    }

    private var successContent: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(Color.ascendAccent)
                .accessibilityHidden(true)
            Text("Opening Ascend")
                .font(.montserratSemiBold(size: 16))
                .foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Access confirmed. Opening Ascend.")
    }

    private var nativeAndRecoveryContent: some View {
        VStack(spacing: 16) {
            if coordinator.phase == .loadingNative
                || coordinator.phase == .purchasing
                || coordinator.phase == .verifying {
                AscendLoadingIndicator()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .accessibilityHidden(true)
            }

            if coordinator.showsPurchaseControls, !coordinator.plans.isEmpty {
                VStack(spacing: 12) {
                    ForEach(coordinator.plans) { plan in
                        planButton(plan)
                    }
                }

                Button {
                    coordinator.purchaseSelectedPlan()
                } label: {
                    Text(coordinator.selectedPlan?.purchaseActionTitle ?? String(
                        localized: "subscription.action.subscribe",
                        defaultValue: "Subscribe with Apple"
                    ))
                        .font(.montserratBold(size: 16))
                        .foregroundStyle(.black.opacity(0.9))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 54)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.ascendAccent)
                        )
                }
                .buttonStyle(.plain)
                .disabled(coordinator.disablesPurchase || coordinator.selectedPlanID == nil)
                .accessibilityHint("Starts checkout through Apple for the selected Ascend plan.")
            } else if coordinator.phase == .verificationUnavailable
                        || coordinator.phase == .pendingApproval {
                Button("Check Access") {
                    coordinator.checkAccess()
                }
                .font(.montserratBold(size: 16))
                .foregroundStyle(.black.opacity(0.9))
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(Color.ascendAccent, in: .rect(cornerRadius: 10))
                .accessibilityHint("Checks your subscription access without starting another purchase.")
            } else if coordinator.phase == .failed || coordinator.phase == .backUnavailable {
                Button("Try Subscription Options Again") {
                    coordinator.retryHosted()
                }
                .font(.montserratBold(size: 16))
                .foregroundStyle(.black.opacity(0.9))
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(Color.ascendAccent, in: .rect(cornerRadius: 10))
            }

            recoveryActions
        }
    }

    private func planButton(_ plan: NativeSubscriptionPlan) -> some View {
        let isSelected = coordinator.selectedPlanID == plan.id
        return Button {
            coordinator.selectPlan(plan.id)
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.ascendAccent : .white.opacity(0.5))
                    .font(.system(size: 21, weight: .semibold))

                VStack(alignment: .leading, spacing: 5) {
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            Text(plan.title)
                                .font(.montserratBold(size: 17))
                            Spacer()
                            Text(plan.localizedPrice)
                                .font(.montserratSemiBold(size: 16))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(plan.title)
                                .font(.montserratBold(size: 17))
                            Text(plan.localizedPrice)
                                .font(.montserratSemiBold(size: 16))
                        }
                    }
                    if let trialDescription = plan.trialDescription {
                        Text(trialDescription)
                            .font(.montserratSemiBold(size: 14))
                            .foregroundStyle(Color.ascendAccent)
                    }
                    Text(plan.renewalDescription)
                        .font(.montserratMedium(size: 13))
                        .foregroundStyle(.white.opacity(0.66))
                }
                .foregroundStyle(.white)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(isSelected ? 0.1 : 0.055), in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.ascendAccent : .white.opacity(0.15), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(coordinator.disablesPurchase)
        .accessibilityLabel(
            [plan.title, plan.localizedPrice, plan.trialDescription, plan.renewalDescription]
                .compactMap { $0 }
                .joined(separator: ", ")
        )
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private var recoveryActions: some View {
        VStack(spacing: 4) {
            Button {
                coordinator.restore()
            } label: {
                Text(coordinator.restoreState.buttonTitle(
                    isRevenueCatConfigured: manager.isRevenueCatConfigured
                ))
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.plain)
            .font(.montserratSemiBold(size: 15))
            .foregroundStyle(.white)
            .disabled(
                !coordinator.restoreState.isButtonEnabled(
                    isRevenueCatConfigured: manager.isRevenueCatConfigured
                ) || coordinator.disablesRestore
            )

            if let restoreMessage = coordinator.restoreState.statusMessage {
                Text(restoreMessage)
                    .font(.montserratMedium(size: 13))
                    .foregroundStyle(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("appAccessRestoreStatus")
            }

            Button("Manage Subscription") {
                isShowingManageSubscriptions = true
            }
            .recoveryLinkStyle()
            .accessibilityFocused($focusedControl, equals: .manageSubscription)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    legalAndSupportLinks
                }
                VStack(spacing: 0) {
                    legalAndSupportLinks
                }
            }
            .font(.montserratMedium(size: 13))
            .foregroundStyle(.white.opacity(0.7))
            .frame(maxWidth: .infinity, minHeight: 44)

            Button(action: onDeleteAccount) {
                Text("Delete account")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .font(.montserratMedium(size: 13))
            .foregroundStyle(.white.opacity(0.55))
            .accessibilityHint("Permanently deletes your Ascend account and all of its data.")
            .accessibilityIdentifier("appAccessDeleteAccount")
            .accessibilityFocused($focusedControl, equals: .deleteAccount)

            Button(action: onSignOut) {
                Text("Sign Out")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .font(.montserratMedium(size: 13))
            .foregroundStyle(.white.opacity(0.72))
            .accessibilityHint("Signs out so you can use a different Ascend account.")
            .accessibilityIdentifier("appAccessSignOut")

            #if DEBUG
            if manager.debugForcesAppAccessPaywall {
                Button("Clear Debug Gate Override") {
                    manager.setDebugForcesAppAccessPaywall(false)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .buttonStyle(.plain)
                .font(.montserratSemiBold(size: 13))
                .foregroundStyle(Color.ascendAccent)
                .accessibilityIdentifier("appAccessClearDebugGateOverride")
            }
            #endif
        }
    }

    @ViewBuilder
    private var legalAndSupportLinks: some View {
        Link("Terms", destination: URL(string: "https://ascendstepper.com/terms")!)
            .frame(minWidth: 44, minHeight: 44)
        Link("Privacy", destination: URL(string: "https://ascendstepper.com/privacy")!)
            .frame(minWidth: 44, minHeight: 44)
        Link("Support", destination: URL(string: "https://ascendstepper.com/support")!)
            .frame(minWidth: 44, minHeight: 44)
    }

    private var title: String {
        switch coordinator.phase {
        case .openingHosted, .hostedPresented:
            return "Loading subscription options"
        case .loadingNative:
            return "Loading subscription options"
        case .nativeReady, .failed:
            return "Choose your Ascend plan"
        case .backUnavailable:
            return "Couldn't go back"
        case .purchasing:
            return "Opening Apple checkout"
        case .verifying, .verificationUnavailable:
            return "Checking your subscription access"
        case .pendingApproval:
            return "Approval is pending"
        case .accessConfirmed:
            return "Access confirmed"
        }
    }

    private var heroMessage: String? {
        switch coordinator.phase {
        case .openingHosted, .hostedPresented, .loadingNative, .verifying, .accessConfirmed:
            nil
        case .nativeReady, .purchasing, .verificationUnavailable, .pendingApproval, .failed,
             .backUnavailable:
            coordinator.statusMessage
        }
    }

    private func announcePhase(_ phase: AppAccessGatePhase) {
        let announcement: String? = switch phase {
        case .loadingNative:
            "Loading subscription options."
        case .purchasing:
            "Apple checkout is opening."
        case .pendingApproval:
            "Apple approval is pending. Do not purchase again."
        case .verifying:
            "Checking your subscription access."
        case .verificationUnavailable:
            "Payment may still be processing. Do not purchase again."
        case .accessConfirmed:
            "Access confirmed. Opening Ascend."
        case .failed:
            coordinator.statusMessage ?? "Subscription options are unavailable."
        case .backUnavailable:
            coordinator.statusMessage ?? "Ascend couldn't reopen the previous step."
        case .openingHosted, .hostedPresented, .nativeReady:
            nil
        }
        if let announcement {
            AccessibilityNotification.Announcement(announcement).post()
            focusedControl = .status
        }
    }
}

private extension View {
    func recoveryLinkStyle() -> some View {
        buttonStyle(.plain)
            .font(.montserratMedium(size: 13))
            .foregroundStyle(.white.opacity(0.72))
            .frame(maxWidth: .infinity, minHeight: 44)
    }
}

#Preview {
    AppAccessPaywallPlaceholderView(onDeleteAccount: {}, onSignOut: {})
        .environment(MonetizationManager())
}

import SwiftUI

/// The app-access gate: a spinner, and the coordinator that puts hosted screens over it.
///
/// Ascend draws nothing else here. The paywall, its decline offer and the founder letter are
/// Superwall screens presented in their own window above this one, and restore, manage
/// subscription, sign out and delete account are controls on those screens that this gate answers.
struct AppAccessPaywallPlaceholderView: View {
    @Environment(MonetizationManager.self) private var monetizationManager

    private let automaticallyStarts: Bool
    private let accountDeletionDismissalRevision: UInt
    private let onDeleteAccount: @MainActor () -> Void
    private let onSignOut: @MainActor () -> Void
    private let onRequestOnboardingBack: (@MainActor () -> Bool)?

    init(
        automaticallyStarts: Bool = true,
        accountDeletionDismissalRevision: UInt = 0,
        onRequestOnboardingBack: (@MainActor () -> Bool)? = nil,
        onDeleteAccount: @escaping @MainActor () -> Void,
        onSignOut: @escaping @MainActor () -> Void = {}
    ) {
        self.automaticallyStarts = automaticallyStarts
        self.accountDeletionDismissalRevision = accountDeletionDismissalRevision
        self.onRequestOnboardingBack = onRequestOnboardingBack
        self.onDeleteAccount = onDeleteAccount
        self.onSignOut = onSignOut
    }

    var body: some View {
        AppAccessPaywallContentView(
            manager: monetizationManager,
            automaticallyStarts: automaticallyStarts,
            accountDeletionDismissalRevision: accountDeletionDismissalRevision,
            onRequestOnboardingBack: onRequestOnboardingBack,
            onDeleteAccount: onDeleteAccount,
            onSignOut: onSignOut
        )
    }
}

private struct AppAccessPaywallContentView: View {
    @State private var coordinator: AppAccessPaywallCoordinator

    private let manager: MonetizationManager
    private let automaticallyStarts: Bool
    private let accountDeletionDismissalRevision: UInt

    init(
        manager: MonetizationManager,
        automaticallyStarts: Bool,
        accountDeletionDismissalRevision: UInt,
        onRequestOnboardingBack: (@MainActor () -> Bool)?,
        onDeleteAccount: @escaping @MainActor () -> Void,
        onSignOut: @escaping @MainActor () -> Void
    ) {
        self.manager = manager
        self.automaticallyStarts = automaticallyStarts
        self.accountDeletionDismissalRevision = accountDeletionDismissalRevision
        _coordinator = State(
            initialValue: AppAccessPaywallCoordinator(
                monetizationManager: manager,
                onRequestOnboardingBack: onRequestOnboardingBack,
                onRequestAccountDeletion: onDeleteAccount,
                onRequestSignOut: onSignOut
            )
        )
    }

    var body: some View {
        AppAccessSpinnerView()
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
            .onChange(of: accountDeletionDismissalRevision) { _, _ in
                // A deletion raised from the hosted paywall dismissed that paywall to get here, so
                // backing out of it has to put the climber back on it.
                coordinator.accountDeletionDialogDismissed()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.willEnterForegroundNotification
                )
            ) { _ in
                coordinator.appWillEnterForeground()
            }
    }
}

#Preview {
    AppAccessPaywallPlaceholderView(onDeleteAccount: {}, onSignOut: {})
        .environment(MonetizationManager())
}

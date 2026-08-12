import SwiftUI

struct BlockedClimbersView: View {
    @Environment(AuthenticationViewModel.self) private var authViewModel
    @Environment(ModerationStore.self) private var moderationStore
    @State private var userIdBeingUnblocked: String?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if moderationStore.isHydrating {
                loadingState
            } else if let hydrationErrorMessage = moderationStore.hydrationErrorMessage {
                errorState(message: hydrationErrorMessage)
            } else if moderationStore.blockedClimbers.isEmpty {
                emptyState
            } else {
                blockedClimberList
            }
        }
        .themedBackground()
        .navigationTitle("Blocked climbers")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let userId = authViewModel.user?.uid,
                  !moderationStore.isBlockListHydrated,
                  !moderationStore.isHydrating else {
                return
            }
            await moderationStore.hydrate(for: userId)
        }
        .alert("Couldn't unblock climber", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Check your connection and try again.")
        }
        .trackOnce(screen: .blockedClimbers)
    }

    private var blockedClimberList: some View {
        List {
            ForEach(moderationStore.blockedClimbers) { blockedClimber in
                HStack(spacing: 14) {
                    Image(systemName: PublicClimberIdentity.genericAvatarSystemName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(.white.opacity(0.1)))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(
                            CrossUserIdentityResolver.hiddenDisplayName(
                                for: blockedClimber.userId
                            )
                        )
                            .font(.montserratSemiBold(size: 15))
                            .foregroundStyle(.white)

                        Text("Blocked \(blockedClimber.createdAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.montserratRegular(size: 12))
                            .foregroundStyle(.white.opacity(0.62))
                    }

                    Spacer(minLength: 12)

                    Button {
                        unblock(blockedClimber)
                    } label: {
                        if userIdBeingUnblocked == blockedClimber.userId {
                            HStack(spacing: 6) {
                                ProgressView()
                                Text("Unblocking")
                            }
                            .accessibilityLabel("Unblocking")
                        } else {
                            Text("Unblock")
                        }
                    }
                    .font(.montserratSemiBold(size: 13))
                    .foregroundStyle(.accent)
                    .frame(minHeight: 44)
                    .disabled(userIdBeingUnblocked != nil)
                }
                .listRowBackground(Color.clear)
                .accessibilityElement(children: .contain)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var loadingState: some View {
        ProgressView("Loading blocked climbers...")
            .font(.montserratMedium(size: 14))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No blocked climbers",
            systemImage: "person.crop.circle.badge.checkmark",
            description: Text("Block a profile when you need distance.")
        )
    }

    private func errorState(message: String) -> some View {
        ContentUnavailableView {
            Label("Blocked climbers unavailable", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again", action: retryHydration)
                .buttonStyle(.borderedProminent)
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )
    }

    private func retryHydration() {
        guard let userId = authViewModel.user?.uid else { return }
        Task {
            await moderationStore.hydrate(for: userId)
        }
    }

    private func unblock(_ blockedClimber: BlockedClimber) {
        guard let blockerUserId = authViewModel.user?.uid else {
            errorMessage = "Sign in and try again."
            return
        }

        userIdBeingUnblocked = blockedClimber.userId
        Task {
            defer { userIdBeingUnblocked = nil }
            do {
                try await moderationStore.unblock(
                    blockerUserId: blockerUserId,
                    blockedUserId: blockedClimber.userId
                )
                HapticsManager.shared.trigger(.success)
            } catch is CancellationError {
                return
            } catch {
                errorMessage = "The unblock didn't save. Check your connection and try again."
            }
        }
    }
}

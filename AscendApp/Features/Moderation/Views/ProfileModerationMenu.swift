import SwiftUI

struct ProfileModerationMenu: View {
    @Environment(AuthenticationViewModel.self) private var authViewModel
    @Environment(ModerationStore.self) private var moderationStore
    @AccessibilityFocusState private var isMenuFocused: Bool
    @State private var isBlocking = false
    @State private var isSubmittingReport = false
    @State private var showsReportSheet = false
    @State private var showsPostBlockSheet = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    let reportedUserId: String
    let source: ModerationSource

    private var isBlocked: Bool {
        moderationStore.blockedUserIds.contains(reportedUserId)
    }

    var body: some View {
        Menu {
            Button(role: .destructive, action: block) {
                Label(
                    isBlocked ? "Blocked" : (isBlocking ? "Blocking..." : "Block"),
                    systemImage: "hand.raised"
                )
            }
            .disabled(isBlocked || isBlocking)

            Button("Report", systemImage: "flag", action: showReport)
                .disabled(isSubmittingReport)
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Profile actions")
        .accessibilityFocused($isMenuFocused)
        .sheet(isPresented: $showsReportSheet) {
            ReportProfileSheet(
                isSubmitting: isSubmittingReport,
                onCancel: dismissReport,
                onSubmit: submitReport
            )
            .appSheetStyle(.large, isInteractiveDismissDisabled: isSubmittingReport)
            .onDisappear(perform: restoreFocus)
        }
        .sheet(isPresented: $showsPostBlockSheet) {
            PostBlockReportSheet(
                isSubmitting: isSubmittingReport,
                onDone: dismissPostBlock,
                onSubmit: submitPostBlockReport
            )
            .appSheetStyle(.large, isInteractiveDismissDisabled: isSubmittingReport)
            .onDisappear(perform: restoreFocus)
        }
        .alert("Couldn't complete that action", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Try again.")
        }
        .alert("Report sent", isPresented: successAlertBinding) {
            Button("Done", role: .cancel) {}
        } message: {
            Text(successMessage ?? "Ascend received your report for review.")
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

    private var successAlertBinding: Binding<Bool> {
        Binding(
            get: { successMessage != nil },
            set: { isPresented in
                if !isPresented {
                    successMessage = nil
                }
            }
        )
    }

    private func block() {
        guard let blockerUserId = authViewModel.user?.uid else {
            errorMessage = "Sign in and try again."
            return
        }

        isBlocking = true
        Task {
            defer { isBlocking = false }
            do {
                try await moderationStore.block(
                    blockerUserId: blockerUserId,
                    blockedUserId: reportedUserId
                )
                HapticsManager.shared.trigger(.success)
                showsPostBlockSheet = true
            } catch is CancellationError {
                return
            } catch {
                errorMessage = "The block didn't save. Check your connection and try again."
            }
        }
    }

    private func showReport() {
        showsReportSheet = true
    }

    private func dismissReport() {
        showsReportSheet = false
    }

    private func dismissPostBlock() {
        showsPostBlockSheet = false
    }

    private func submitReport(_ reason: ModerationReportReason) {
        submit(reason: reason, dismiss: dismissReport)
    }

    private func submitPostBlockReport(_ reason: ModerationReportReason) {
        submit(reason: reason, dismiss: dismissPostBlock)
    }

    private func submit(
        reason: ModerationReportReason,
        dismiss: @escaping () -> Void
    ) {
        guard let reporterUserId = authViewModel.user?.uid else {
            errorMessage = "Sign in and try again."
            return
        }

        isSubmittingReport = true
        Task {
            defer { isSubmittingReport = false }
            do {
                try await moderationStore.report(
                    reporterUserId: reporterUserId,
                    reportedUserId: reportedUserId,
                    reason: reason,
                    source: source
                )
                HapticsManager.shared.trigger(.success)
                dismiss()
                successMessage = "Ascend received your report for review."
            } catch is CancellationError {
                return
            } catch {
                errorMessage = "The report wasn't sent. Wait a minute, then try again."
            }
        }
    }

    private func restoreFocus() {
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            isMenuFocused = true
        }
    }
}

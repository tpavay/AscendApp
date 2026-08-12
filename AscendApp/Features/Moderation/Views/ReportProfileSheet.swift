import SwiftUI

struct ReportProfileSheet: View {
    @State private var selectedReason: ModerationReportReason?

    let isSubmitting: Bool
    let onCancel: () -> Void
    let onSubmit: (ModerationReportReason) -> Void

    var body: some View {
        ModerationSheetScaffold(
            title: "Report profile",
            message: "Choose a reason. Reporting sends this profile to Ascend for review."
        ) {
            ModerationReasonPicker(selection: $selectedReason)
        } footer: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    cancelButton
                    reportButton
                }

                VStack(spacing: 10) {
                    reportButton
                    cancelButton
                }
            }
        }
        .trackOnce(screen: .reportProfile)
    }

    private var cancelButton: some View {
        Button("Cancel", action: onCancel)
            .appSheetButtonStyle(tone: .secondary)
            .disabled(isSubmitting)
    }

    private var reportButton: some View {
        Button(action: submit) {
            if isSubmitting {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.white)
                    Text("Sending report")
                }
                .accessibilityLabel("Sending report")
            } else {
                Text("Send Report")
            }
        }
        .appSheetButtonStyle(tone: .destructive)
        .disabled(selectedReason == nil || isSubmitting)
    }

    private func submit() {
        guard let selectedReason else { return }
        onSubmit(selectedReason)
    }
}

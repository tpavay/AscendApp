import SwiftUI

struct PostBlockReportSheet: View {
    @State private var alsoReportsProfile = false
    @State private var selectedReason: ModerationReportReason?

    let isSubmitting: Bool
    let onDone: () -> Void
    let onSubmit: (ModerationReportReason) -> Void

    var body: some View {
        ModerationSheetScaffold(
            title: "Climber blocked",
            message: "Their name and photo are hidden. Rankings and workout results stay unchanged."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Also report this profile", isOn: $alsoReportsProfile)
                    .font(.montserratSemiBold(size: 15))
                    .tint(.accent)
                    .disabled(isSubmitting)

                if alsoReportsProfile {
                    Text("Choose a reason")
                        .font(.montserratBold(size: 13))
                        .foregroundStyle(.white.opacity(0.72))
                        .accessibilityAddTraits(.isHeader)

                    ModerationReasonPicker(selection: $selectedReason)
                }
            }
        } footer: {
            if alsoReportsProfile {
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
            } else {
                Button("Done", action: onDone)
                    .appSheetButtonStyle()
            }
        }
    }

    private func submit() {
        guard let selectedReason else { return }
        onSubmit(selectedReason)
    }
}

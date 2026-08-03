import SwiftUI

struct ModerationReasonPicker: View {
    @Binding var selection: ModerationReportReason?

    var body: some View {
        VStack(spacing: 8) {
            ForEach(ModerationReportReason.allCases) { reason in
                Button {
                    selection = reason
                } label: {
                    AppSheetOptionRow(
                        systemImage: selection == reason ? "checkmark.circle.fill" : "circle",
                        title: reason.title,
                        iconTint: selection == reason ? .accent : .white.opacity(0.58),
                        tone: selection == reason ? .accent : .standard,
                        style: .compact
                    )
                }
                .buttonStyle(.plain)
                .accessibilityValue(selection == reason ? "Selected" : "Not selected")
            }
        }
    }
}

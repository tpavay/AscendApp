import SwiftUI

/// A manage-sheet row that holds a setting instead of going somewhere.
///
/// The label is part of the control, so the whole row is one target and one VoiceOver element.
struct IntegrationManageToggleRow: View {
    let systemImage: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            IntegrationManageRowLabel(systemImage: systemImage, title: title, subtitle: subtitle)
        }
        .toggleStyle(.switch)
        .tint(.accent)
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .appSheetCardStyle()
    }
}

import SwiftUI

struct AppUpdateSheet: View {
    let presentation: AppUpdatePresentation
    let onOpenAppStore: () -> Void
    let onLater: () -> Void

    var body: some View {
        AppSheetScaffold(
            title: presentation.title,
            message: presentation.message
        ) {
            EmptyView()
        } footer: {
            VStack(spacing: 10) {
                Button("Update on the App Store", action: onOpenAppStore)
                    .appSheetButtonStyle(tone: .accentContrast)
                    .accessibilityHint("Opens Ascend in the App Store.")

                if presentation.showsLaterAction {
                    Button("Later", action: onLater)
                        .appSheetButtonStyle(tone: .secondary)
                }
            }
        }
        .accessibilityAddTraits(.isModal)
        .appSheetStyle(
            .fitted(dragIndicator: presentation.allowsInteractiveDismissal ? .visible : .hidden),
            isInteractiveDismissDisabled: presentation.allowsInteractiveDismissal == false
        )
    }
}

#Preview("Required") {
    AppUpdateSheet(presentation: .required, onOpenAppStore: {}, onLater: {})
}

#Preview("Recommended") {
    AppUpdateSheet(presentation: .recommended, onOpenAppStore: {}, onLater: {})
}

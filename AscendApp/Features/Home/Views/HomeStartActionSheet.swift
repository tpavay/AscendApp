import SwiftUI

struct HomeStartActionSheet: View {
    let onSelect: (HomeStartAction) -> Void

    var body: some View {
        AppSheetScaffold(
            title: "START",
            message: "Track now, race a landmark, or run intervals.",
            headerAlignment: .leading,
            contentAlignment: .leading,
            layout: .actionMenu
        ) {
            VStack(spacing: 10) {
                ForEach(HomeStartAction.allCases, id: \.self) { action in
                    HomeStartActionRow(action: action, onSelect: onSelect)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    HomeStartActionSheet { _ in }
}

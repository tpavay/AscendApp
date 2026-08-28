import SwiftUI

/// The camera roll's scope row: text only, no pills, no icons, sitting directly under the source
/// tabs.
///
/// Deliberately a different typographic register from the 44pt tab pills above it, so two stacked
/// rows read as two levels rather than two peers. The underline treatment is the app's existing one
/// from `ProfileComparisonTabPicker` rather than a second dialect.
struct ShareScopeFilterRow: View {
    let items: [ShareScopeItem]
    let selection: ShareCameraRollSelection
    /// Album items are inert under limited photo access, where PhotoKit can fetch no albums at all.
    let albumsAreAvailable: Bool
    let onSelect: (ShareScopeItem) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .firstTextBaseline, spacing: 22) {
                ForEach(items) { item in
                    itemButton(item)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
        }
        // Behind rather than below, so the selected item's 2pt rule paints over the hairline
        // instead of stacking into one thick line - the same relationship
        // `ProfileComparisonTabPicker` already draws.
        .background(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(height: 1)
        }
    }

    private func itemButton(_ item: ShareScopeItem) -> some View {
        let isSelected = isSelected(item)
        let isEnabled = isEnabled(item)

        return Button {
            guard isEnabled else { return }
            HapticsManager.shared.trigger(.lightImpact)
            onSelect(item)
        } label: {
            VStack(spacing: 9) {
                HStack(spacing: 5) {
                    if item.isBackItem {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .bold))
                    }
                    Text(item.title)
                        .font(isSelected ? .montserratBold(size: 14) : .montserratMedium(size: 14))
                        .lineLimit(1)
                }
                .foregroundStyle(foreground(isSelected: isSelected, isEnabled: isEnabled))

                Rectangle()
                    .fill(isSelected ? Color.ascendAccent : .clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel(item))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func foreground(isSelected: Bool, isEnabled: Bool) -> Color {
        guard isEnabled else { return .white.opacity(0.2) }
        return isSelected ? .white : .white.opacity(0.42)
    }

    private func isSelected(_ item: ShareScopeItem) -> Bool {
        switch item {
        case .recents:
            return selection == .recents
        case .allAlbums:
            return selection == .allAlbums
        // The back item stands for the album currently on screen, so it reads as the selected one
        // even though tapping it goes back to the grid.
        case .back(let album):
            return selection.album == album
        case .album(let album):
            return selection.album == album
        }
    }

    /// Recents always works. Everything else is an album, and there are no albums to reach under
    /// limited photo access.
    private func isEnabled(_ item: ShareScopeItem) -> Bool {
        if case .recents = item { return true }
        return albumsAreAvailable
    }

    private func accessibilityLabel(_ item: ShareScopeItem) -> String {
        item.isBackItem ? "Back to all albums, \(item.title)" : item.title
    }
}

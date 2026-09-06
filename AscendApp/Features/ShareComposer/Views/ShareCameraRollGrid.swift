import Photos
import PhotosUI
import SwiftUI
import UIKit

/// Inline Camera Roll grid — the user's real photos and videos, tapped to pick
/// directly as a background (no intermediate "choose" button).
///
/// The library is injected rather than owned: the filter row and the calendar button both sit above
/// this grid and drive the same scope, so the state has to outlive this view's identity.
struct ShareCameraRollGrid: View {
    let library: SharePhotoLibrary
    let onPick: (ShareBackgroundSource) -> Void
    var onClearDate: () -> Void = {}
    var onShowRecents: () -> Void = {}

    @State private var isLoadingSelection = false

    private let columns = [
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3)
    ]

    var body: some View {
        Group {
            switch library.accessState {
            case .denied:
                deniedState
            case .unknown:
                loadingState
            default:
                if library.assets.isEmpty {
                    // A library still being enumerated has no assets yet, and saying "No photos
                    // yet" to a climber holding 30,000 of them is a lie the spinner prevents.
                    if library.isLoadingAssets {
                        loadingState
                    } else {
                        emptyScopeState
                    }
                } else {
                    grid
                }
            }
        }
    }

    private var loadingState: some View {
        ProgressView()
            .tint(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Loading photos")
    }

    private var grid: some View {
        ScrollView {
            if library.accessState == .limited {
                limitedSelectionRow
            }

            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(library.assets, id: \.localIdentifier) { asset in
                    Button {
                        select(asset)
                    } label: {
                        PhotoThumbCell(asset: asset, library: library)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoadingSelection)
                }
            }
            .padding(.horizontal, 3)
            .padding(.top, library.accessState == .limited ? 12 : 16)

            if library.accessState == .limited {
                fullAccessFooter
            }
        }
        .overlay {
            if isLoadingSelection {
                ProgressView().tint(.white)
            }
        }
    }

    // MARK: - Limited access

    /// PhotoKit can fetch no albums at all under limited access, so the album shortcuts go inert and
    /// this becomes the one control that still does something.
    private var limitedSelectionRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 13, weight: .semibold))
                Text("Selected Photos · \(library.assets.count)")
                    .font(.montserratSemiBold(size: 11))
                    .tracking(1.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)

            Spacer(minLength: 8)

            Button {
                HapticsManager.shared.trigger(.lightImpact)
                presentLimitedLibraryPicker()
            } label: {
                Text("Add more")
                    .font(.montserratBold(size: 11))
                    .tracking(1.2)
                    .foregroundStyle(.black.opacity(0.82))
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Capsule().fill(Color.ascendAccent))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    /// After the last photo rather than above the first: the climber reads this exactly when they
    /// have run out, which is when they want it.
    private var fullAccessFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ascend can only see the \(library.assets.count) photos you picked.")
                .font(.montserratRegular(size: 12))
                .foregroundStyle(Color.customGray)

            Button {
                openSettings()
            } label: {
                Text("Allow full access")
                    .font(.montserratSemiBold(size: 12))
                    .foregroundStyle(Color.ascendAccent)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Empty states

    @ViewBuilder
    private var emptyScopeState: some View {
        let scope = library.scope

        if let album = scope.selection.album, scope.dateWindow == nil {
            emptyState(
                title: "This album is empty.",
                message: "Nothing here to put behind your climb.",
                primaryTitle: "Show recents",
                primaryAction: onShowRecents,
                secondary: nil,
                accessibilityAlbum: album.title
            )
        } else if let window = scope.dateWindow {
            let name = window.displayName()
            emptyState(
                title: scope.selection.album.map { "Nothing in \($0.title) from \(name)." }
                    ?? "Nothing from \(name).",
                message: scope.selection.album.map {
                    "The album has \($0.count.formatted(.number.grouping(.automatic))) photos. None of them are from then."
                } ?? "Pick a different month.",
                primaryTitle: "Clear the date",
                primaryAction: onClearDate,
                secondary: scope.selection.album == nil ? nil : ("Show recents", onShowRecents),
                accessibilityAlbum: nil
            )
        } else if library.accessState == .limited {
            // The "Add more" row lives inside the grid, which does not exist with nothing selected.
            // Without this branch a limited climber who picked nothing has no route back to the
            // limited-library picker at all.
            emptyState(
                title: "Ascend can't see any photos.",
                message: "You picked none to share. Pick the shots it can use.",
                primaryTitle: "Add photos",
                primaryAction: { presentLimitedLibraryPicker() },
                secondary: ("Allow full access", { openSettings() }),
                accessibilityAlbum: nil
            )
        } else {
            emptyState(
                title: "No photos yet.",
                message: "Shoot something worth putting behind a climb.",
                primaryTitle: nil,
                primaryAction: nil,
                secondary: nil,
                accessibilityAlbum: nil
            )
        }
    }

    private func emptyState(
        title: String,
        message: String,
        primaryTitle: String?,
        primaryAction: (() -> Void)?,
        secondary: (String, () -> Void)?,
        accessibilityAlbum: String?
    ) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.white.opacity(0.6))

            Text(title)
                .font(.montserratSemiBold(size: 16))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.montserratRegular(size: 13))
                .foregroundStyle(Color.customGray)
                .multilineTextAlignment(.center)

            if let primaryTitle, let primaryAction {
                Button {
                    HapticsManager.shared.trigger(.lightImpact)
                    primaryAction()
                } label: {
                    Text(primaryTitle)
                        .font(.montserratSemiBold(size: 14))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 22)
                        .frame(height: 44)
                        .background(Capsule().fill(Color.ascendAccent))
                }
                .buttonStyle(.plain)
            }

            if let secondary {
                Button {
                    HapticsManager.shared.trigger(.lightImpact)
                    secondary.1()
                } label: {
                    Text(secondary.0)
                        .font(.montserratSemiBold(size: 12))
                        .foregroundStyle(Color.customGray)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var deniedState: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.white.opacity(0.6))
            Text("Photos access is off")
                .font(.montserratSemiBold(size: 16))
                .foregroundStyle(.white)
            Text("Turn on Photos access to use your own shots as backgrounds.")
                .font(.montserratRegular(size: 13))
                .foregroundStyle(Color.customGray)
                .multilineTextAlignment(.center)
            Button {
                openSettings()
            } label: {
                Text("Open Settings")
                    .font(.montserratSemiBold(size: 14))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 22)
                    .frame(height: 44)
                    .background(Capsule().fill(Color.ascendAccent))
            }
            .buttonStyle(.plain)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func select(_ asset: PHAsset) {
        HapticsManager.shared.trigger(.lightImpact)
        isLoadingSelection = true
        let identifier = asset.localIdentifier
        let isVideo = asset.mediaType == .video
        Task {
            defer { isLoadingSelection = false }
            if isVideo {
                if let url = await library.videoURL(forIdentifier: identifier) {
                    onPick(.video(url))
                }
            } else {
                if let image = await library.fullImage(forIdentifier: identifier) {
                    onPick(.photo(image))
                }
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// PhotosUI only offers this from a `UIViewController`, so the top one has to be found by hand.
    /// Changing the selection fires the library change observer, which is what refreshes the grid.
    private func presentLimitedLibraryPicker() {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController
        else { return }

        var presenter = root
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: presenter)
    }
}

private struct PhotoThumbCell: View {
    let asset: PHAsset
    let library: SharePhotoLibrary

    @State private var thumbnail: UIImage?

    var body: some View {
        Color.white.opacity(0.05)
            .aspectRatio(1, contentMode: .fill)
            .overlay {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if asset.mediaType == .video {
                    Text(Self.durationText(asset.duration))
                        .font(.montserratSemiBold(size: 9))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .padding(5)
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .task(id: asset.localIdentifier) {
                thumbnail = await library.thumbnail(forIdentifier: asset.localIdentifier, size: 130)
            }
    }

    private static func durationText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}

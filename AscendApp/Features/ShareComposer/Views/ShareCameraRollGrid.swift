import Photos
import SwiftUI
import UIKit

/// Inline Camera Roll grid — the user's real photos and videos, tapped to pick
/// directly as a background (no intermediate "choose" button).
struct ShareCameraRollGrid: View {
    let onPick: (ShareBackgroundSource) -> Void

    @State private var library = SharePhotoLibrary()
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
            default:
                grid
            }
        }
        .task { await library.loadIfNeeded() }
    }

    private var grid: some View {
        ScrollView {
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
            .padding(.top, 16)
        }
        .overlay {
            if isLoadingSelection {
                ProgressView().tint(.white)
            }
        }
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
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Open Settings")
                    .font(.montserratSemiBold(size: 14))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 22)
                    .frame(height: 44)
                    .background(Capsule().fill(Color(red: 0.706, green: 0.8, blue: 0)))
            }
            .buttonStyle(.plain)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func select(_ asset: PHAsset) {
        HapticsManager.shared.trigger(.lightImpact)
        isLoadingSelection = true
        Task {
            defer { isLoadingSelection = false }
            if asset.mediaType == .video {
                if let url = await library.videoURL(forIdentifier: asset.localIdentifier) {
                    onPick(.video(url))
                }
            } else {
                if let image = await library.fullImage(forIdentifier: asset.localIdentifier) {
                    onPick(.photo(image))
                }
            }
        }
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

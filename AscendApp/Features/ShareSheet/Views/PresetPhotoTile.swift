import SwiftUI

/// One photograph in the picker. The thumbnail loads when the tile appears; choosing it loads the
/// card-resolution image.
struct PresetPhotoTile: View {
    let photo: PresetPhotoLibrary.Photo
    let library: PresetPhotoLibrary
    let onChoose: (UIImage) -> Void

    @State private var thumbnail: UIImage?

    var body: some View {
        Button {
            Task {
                if let image = await library.cardImage(for: photo.id) {
                    onChoose(image)
                }
            }
        } label: {
            Color(shareHex: 0x1C1C1C)
                .frame(height: 116)
                .overlay {
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Photo")
        .task {
            thumbnail = await library.thumbnail(for: photo.id, side: 116)
        }
    }
}

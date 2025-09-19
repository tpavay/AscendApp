import SwiftUI
import PhotosUI

struct PhotoGalleryView: View {
    @Binding var selectedItems: [PhotosPickerItem]
    @State private var selectedImages: [SelectedImage] = []
    @State private var imageToDelete: SelectedImage?

    private var hasImages: Bool { !selectedImages.isEmpty }

    var body: some View {
        Group {
            if hasImages {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(selectedImages) { img in
                            WorkoutPhotoView(selectedImage: img) {
                                imageToDelete = img
                            }
                        }

                        // Picker tile at the end, fixed width
                        PhotoPickerTile(width: 140, selectedItems: $selectedItems)
                    }
                    .padding(.horizontal, 4)
                }
                .scrollTargetBehavior(.paging)
            } else {
                // Standalone picker tile, fills available width
                PhotoPickerTile(width: nil, selectedItems: $selectedItems)
                    .frame(maxWidth: .infinity)
                    .frame(height: 120) // keep height stable when empty
            }
        }
        // Single onChange to process items and mutate state on main actor
        .onChange(of: selectedItems) { _, newItems in
            Task {
                let newSelectedImages = await PhotoManager.processItems(newItems)
                await MainActor.run {
                    selectedImages.append(contentsOf: newSelectedImages)
                    selectedItems.removeAll()
                }
            }
        }
        .sheet(item: $imageToDelete) { image in
            DeletePhotoConfirmationView(
                onDelete: {
                    selectedImages.removeAll { $0.id == image.id }
                    imageToDelete = nil
                },
                onCancel: { imageToDelete = nil }
            )
            .presentationDetents([.height(180)])
        }
    }
}

private struct PhotoPickerTile: View {
    /// If `width` is nil, the tile will expand to max width.
    let width: CGFloat?
    @Binding var selectedItems: [PhotosPickerItem]

    var body: some View {
        PhotosPicker(selection: $selectedItems, matching: .images) {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.accent, style: StrokeStyle(lineWidth: 1, dash: [10, 5]))
                .frame(width: width, height: 120) // width==nil means "no fixed width"
                .overlay {
                    VStack(spacing: 6) {
                        Image("CameraIcon")
                        Text("Add Photos")
                            .font(.montserratSemiBold(size: 14))
                    }
                }
        }
    }
}

#Preview {
    @Previewable @State var selectedItems: [PhotosPickerItem] = []
    PhotoGalleryView(selectedItems: $selectedItems)
        .padding()
}

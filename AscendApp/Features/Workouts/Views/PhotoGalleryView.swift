//
//  PhotoGalleryView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 9/20/25.
//


import SwiftUI
import PhotosUI

struct PhotoGalleryView: View {
    @Binding var selectedImages: [SelectedPhotoItem] // Change this binding
    @State private var selectedPhotos: [PhotosPickerItem] = [] // Make this local state
    @State private var photoToDelete: SelectedPhotoItem?

    var body: some View {
        Group {
            if selectedImages.isEmpty {
                // Empty state - show picker
                PhotoPickerButton(selectedPhotos: $selectedPhotos)
                    .frame(height: 120)
            } else {
                // Photos selected - show gallery with picker at end
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(selectedImages) { item in
                            ThumbnailPhotoView(photoItem: item) {
                                photoToDelete = item
                            }
                        }

                        // Picker at the end
                        PhotoPickerButton(selectedPhotos: $selectedPhotos)
                            .frame(width: 120)
                    }
                    .padding(.horizontal, 4)
                }
                .scrollTargetBehavior(.paging)
            }
        }
        .onChange(of: selectedPhotos) { _, newItems in
            Task {
                await processNewPhotos(newItems)
            }
        }
        .sheet(item: $photoToDelete) { item in
            DeletePhotoConfirmationView(
                onDelete: { deletePhoto(item) },
                onCancel: { photoToDelete = nil }
            )
        }
    }
}

extension PhotoGalleryView {
    @MainActor
    private func processNewPhotos(_ newItems: [PhotosPickerItem]) async {
        // Process photos on background, update UI on main
        let newSelectedImages = await withTaskGroup(of: SelectedPhotoItem?.self) { group in
            for item in newItems {
                group.addTask {
                    await createSelectedPhotoItem(from: item)
                }
            }

            var results: [SelectedPhotoItem] = []
            for await result in group {
                if let item = result {
                    results.append(item)
                }
            }
            return results
        }

        // UI update on main actor
        selectedImages.append(contentsOf: newSelectedImages)
        selectedPhotos.removeAll() // Clear picker - this is now safe!
    }

    private func createSelectedPhotoItem(from item: PhotosPickerItem)
    async -> SelectedPhotoItem? {
        guard let data = try? await item.loadTransferable(type:
                                                            Data.self),
              let uiImage = UIImage(data: data) else {
            return nil
        }

        return SelectedPhotoItem(
            pickerItem: item,
            image: Image(uiImage: uiImage),
            localIdentifier: item.itemIdentifier ?? UUID().uuidString
        )
    }

    private func deletePhoto(_ item: SelectedPhotoItem) {
        selectedImages.removeAll { $0.id == item.id }
        photoToDelete = nil
    }
}

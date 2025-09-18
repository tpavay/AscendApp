//
//  PhotoGalleryView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 9/13/25.
//

import SwiftUI
import PhotosUI

struct PhotoGalleryView: View {
    @State private var tempPickerItems: [PhotosPickerItem] = []
    @State private var selectedImages: [SelectedImage] = []
    @State private var imageToDelete: SelectedImage?
    
    var body: some View {
        if selectedImages.isEmpty {
            // PhotosPicker Button
            PhotosPicker(selection: $tempPickerItems, matching: .images) {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.accent,
                            style: StrokeStyle(
                                lineWidth: 1,
                                dash: [10,5]
                            ))
                    .frame(height: 120)
                    .overlay {
                        VStack {
                            Image("CameraIcon")
                            Text("Add Photos")
                                .font(.montserratSemiBold(size: 14))
                        }
                    }
            }
            .onChange(of: tempPickerItems) { _, newItems in
                Task {
                    // Process new items and ADD them to existing selectedImages
                    let newSelectedImages = await PhotoManager.processItems(newItems)
                    selectedImages.append(contentsOf: newSelectedImages)

                    // Clear the picker selection for next use
                    tempPickerItems.removeAll()
                }
            }
        }

        if !selectedImages.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    // Show selected photos first (on the left)
                    ForEach(selectedImages) { selectedImage in
                        WorkoutPhotoView(selectedImage: selectedImage) {
                            imageToDelete = selectedImage
                        }
                    }
                    
                    // Add Photos picker appears to the right of the photos
                    PhotosPicker(selection: $tempPickerItems, matching: .images) {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.accent,
                                    style: StrokeStyle(
                                        lineWidth: 1,
                                        dash: [10,5]
                                    ))
                            .frame(width: 140, height: 120)
                            .overlay {
                                VStack {
                                    Image("CameraIcon")
                                    Text("Add Photos")
                                        .font(.montserratSemiBold(size: 14))
                                }
                            }
                    }
                    .onChange(of: tempPickerItems) { _, newItems in
                        Task {
                            // Process new items and ADD them to existing selectedImages
                            let newSelectedImages = await PhotoManager.processItems(newItems)
                            selectedImages.append(contentsOf: newSelectedImages)

                            // Clear the picker selection for next use
                            tempPickerItems.removeAll()
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .scrollTargetBehavior(.paging)
            .sheet(item: $imageToDelete) { imageToDelete in
                DeletePhotoConfirmationView(
                    onDelete: {
                        // Simply remove from selectedImages array - no picker syncing needed
                        selectedImages.removeAll { $0.id == imageToDelete.id }
                        self.imageToDelete = nil
                    },
                    onCancel: {
                        self.imageToDelete = nil
                    }
                )
                .presentationDetents([.height(180)])
            }
        }
    }
}

#Preview {
    PhotoGalleryView()
        .padding()
}

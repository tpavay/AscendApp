//
//  PhotoGalleryView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 9/20/25.
//


import SwiftUI
import PhotosUI
import AVFoundation

struct PhotoGalleryView: View {
    @Binding var selectedImages: [SelectedPhotoItem] // Change this binding
    var existingMediaCount: Int = 0 // Count of existing media already in the workout
    var existingVideoCount: Int = 0 // Count of existing videos already in the workout
    
    @State private var selectedPhotos: [PhotosPickerItem] = [] // Make this local state
    @State private var photoToDelete: SelectedPhotoItem?
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    
    // Computed properties for validation
    private var videoCount: Int {
        selectedImages.filter { $0.isVideo }.count
    }
    
    private var totalMediaCount: Int {
        selectedImages.count + existingMediaCount
    }
    
    private var totalVideoCount: Int {
        videoCount + existingVideoCount
    }
    
    private var canAddMore: Bool {
        totalMediaCount < 3
    }

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

                        // Picker at the end - only show if under limit
                        if canAddMore {
                            PhotoPickerButton(selectedPhotos: $selectedPhotos)
                                .frame(width: 120)
                        }
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
        .alert("Media Limit Reached", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
}

extension PhotoGalleryView {
    @MainActor
    private func processNewPhotos(_ newItems: [PhotosPickerItem]) async {
        // Validate total media count first
        let potentialTotal = totalMediaCount + newItems.count
        if potentialTotal > 3 {
            errorMessage = "Only 3 combined photos and videos (max 1 video) can be added to a given workout."
            showErrorAlert = true
            selectedPhotos.removeAll()
            return
        }
        
        // Count videos in new items
        var newVideoCount = 0
        for item in newItems {
            if let contentType = item.supportedContentTypes.first?.identifier,
               contentType.contains("video") || contentType.contains("movie") {
                newVideoCount += 1
            }
        }
        
        // Check video limit (including existing videos)
        if totalVideoCount + newVideoCount > 1 {
            errorMessage = "You can only add one video with a max length of 15 seconds."
            showErrorAlert = true
            selectedPhotos.removeAll()
            return
        }
        
        // Process photos/videos on background, update UI on main
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
        
        // Check if any videos were too long
        let hasInvalidVideo = newSelectedImages.contains { item in
            item.isVideo && (item.duration ?? 0) > 15
        }
        
        if hasInvalidVideo {
            errorMessage = "You can only add one video with a max length of 15 seconds."
            showErrorAlert = true
            selectedPhotos.removeAll()
            return
        }

        // UI update on main actor
        selectedImages.append(contentsOf: newSelectedImages)
        selectedPhotos.removeAll() // Clear picker - this is now safe!
    }

    private func createSelectedPhotoItem(from item: PhotosPickerItem) async -> SelectedPhotoItem? {
        // Check if it's a video
        if let contentType = item.supportedContentTypes.first?.identifier,
           contentType.contains("video") || contentType.contains("movie") {
            return await createVideoItem(from: item)
        } else {
            return await createPhotoItem(from: item)
        }
    }
    
    private func createPhotoItem(from item: PhotosPickerItem) async -> SelectedPhotoItem? {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data) else {
            return nil
        }

        return SelectedPhotoItem(
            pickerItem: item,
            image: Image(uiImage: uiImage),
            localIdentifier: item.itemIdentifier ?? UUID().uuidString,
            isVideo: false,
            duration: nil
        )
    }
    
    private func createVideoItem(from item: PhotosPickerItem) async -> SelectedPhotoItem? {
        guard let movie = try? await item.loadTransferable(type: VideoPickerTransferable.self) else {
            return nil
        }
        
        let asset = AVAsset(url: movie.url)
        let duration = try? await asset.load(.duration).seconds
        
        // Generate thumbnail
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        guard let cgImage = try? imageGenerator.copyCGImage(at: .zero, actualTime: nil),
              let duration = duration else {
            return nil
        }
        
        let uiImage = UIImage(cgImage: cgImage)
        
        return SelectedPhotoItem(
            pickerItem: item,
            image: Image(uiImage: uiImage),
            localIdentifier: item.itemIdentifier ?? UUID().uuidString,
            isVideo: true,
            duration: duration
        )
    }

    private func deletePhoto(_ item: SelectedPhotoItem) {
        selectedImages.removeAll { $0.id == item.id }
        photoToDelete = nil
    }
}

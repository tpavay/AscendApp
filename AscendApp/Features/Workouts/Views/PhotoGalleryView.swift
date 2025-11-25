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
    @Binding private var selectedImages: [SelectedPhotoItem]
    @Binding private var highlightedSelectedItemId: UUID?
    var existingMediaCount: Int = 0 // Count of existing media already in the workout
    var existingVideoCount: Int = 0 // Count of existing videos already in the workout
    
    @State private var selectedPhotos: [PhotosPickerItem] = [] // Make this local state
    @State private var photoToDelete: SelectedPhotoItem?
    @State private var itemForActionSheet: SelectedPhotoItem?
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var videoToTrim: SelectedPhotoItem?
    @State private var showingVideoTrimmer = false
    @State private var pendingVideoItem: SelectedPhotoItem? // Video waiting to be trimmed
    @State private var isLoadingMedia = false // Loading state for media processing
    
    init(
        selectedImages: Binding<[SelectedPhotoItem]>,
        highlightedSelectedItemId: Binding<UUID?> = .constant(nil),
        existingMediaCount: Int = 0,
        existingVideoCount: Int = 0
    ) {
        self._selectedImages = selectedImages
        self._highlightedSelectedItemId = highlightedSelectedItemId
        self.existingMediaCount = existingMediaCount
        self.existingVideoCount = existingVideoCount
    }
    
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
                // Empty state - show picker (with loading state if applicable)
                PhotoPickerButton(selectedPhotos: $selectedPhotos, isLoading: isLoadingMedia)
                    .frame(height: 120)
            } else {
                // Photos selected - show gallery with picker at end
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(selectedImages) { item in
                            ThumbnailPhotoView(
                                photoItem: item,
                                isHighlighted: highlightedSelectedItemId == item.id,
                                onTap: {
                                    itemForActionSheet = item
                                },
                                onDelete: {
                                    photoToDelete = item
                                }
                            )
                        }

                        // Picker at the end - only show if under limit
                        if canAddMore {
                            PhotoPickerButton(selectedPhotos: $selectedPhotos, isLoading: isLoadingMedia)
                                .frame(width: 120)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .scrollTargetBehavior(.paging)
            }
        }
        .onChange(of: selectedPhotos) {
            Task {
                await processNewPhotos(selectedPhotos)
            }
        }
        .sheet(item: $itemForActionSheet) { item in
            SelectedPhotoActionSheet(
                isVideo: item.isVideo,
                isHighlighted: highlightedSelectedItemId == item.id,
                onMakeHighlighted: {
                    highlightedSelectedItemId = item.id
                    itemForActionSheet = nil
                },
                onDelete: {
                    photoToDelete = item
                    itemForActionSheet = nil
                },
                onCancel: {
                    itemForActionSheet = nil
                }
            )
            .presentationDetents([.height(actionSheetHeight(for: item))])
            .presentationDragIndicator(.visible)
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
        .sheet(isPresented: $showingVideoTrimmer) {
            if let videoToTrim = videoToTrim,
               let videoURL = videoToTrim.originalVideoURL,
               let duration = videoToTrim.duration {
                VideoTrimmerView(
                    videoURL: videoURL,
                    videoDuration: duration,
                    onTrim: { startTime, endTime in
                        await trimVideo(item: videoToTrim, startTime: startTime, endTime: endTime)
                    },
                    onCancel: {
                        // Don't add the video if user cancels trimming
                        self.videoToTrim = nil
                        self.pendingVideoItem = nil
                        showingVideoTrimmer = false
                    }
                )
            }
        }
    }
    
    private func actionSheetHeight(for item: SelectedPhotoItem) -> CGFloat {
        highlightedSelectedItemId == item.id ? 220 : 240
    }
}

extension PhotoGalleryView {
    @MainActor
    private func processNewPhotos(_ newItems: [PhotosPickerItem]) async {
        // Set loading state
        isLoadingMedia = true
        
        // Validate total media count first
        let potentialTotal = totalMediaCount + newItems.count
        if potentialTotal > 3 {
            errorMessage = "Only 3 combined photos and videos (max 1 video) can be added to a given workout."
            showErrorAlert = true
            selectedPhotos.removeAll()
            isLoadingMedia = false
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
            isLoadingMedia = false
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
        
        // Check if any videos need trimming
        var videosNeedingTrim: [SelectedPhotoItem] = []
        var readyToAddItems: [SelectedPhotoItem] = []
        
        for item in newSelectedImages {
            if item.isVideo && (item.duration ?? 0) > 15 {
                videosNeedingTrim.append(item)
            } else {
                readyToAddItems.append(item)
            }
        }
        
        // Add items that don't need trimming
        selectedImages.append(contentsOf: readyToAddItems)
        
        // If there's a video that needs trimming, show trimmer
        if let videoNeedingTrim = videosNeedingTrim.first {
            // Only handle first video (since we only allow 1 video total)
            pendingVideoItem = videoNeedingTrim
            videoToTrim = videoNeedingTrim
            showingVideoTrimmer = true
        }
        
        // Clear loading state
        isLoadingMedia = false
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
        
        let asset = AVURLAsset(url: movie.url)
        let duration = try? await asset.load(.duration).seconds
        
        // Generate thumbnail
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        guard let cgImage = try? await imageGenerator.image(at: .zero).image,
              let duration = duration else {
            return nil
        }
        
        let uiImage = UIImage(cgImage: cgImage)
        
        return SelectedPhotoItem(
            pickerItem: item,
            image: Image(uiImage: uiImage),
            localIdentifier: item.itemIdentifier ?? UUID().uuidString,
            isVideo: true,
            duration: duration,
            trimmedVideoURL: nil,
            originalVideoURL: movie.url,
            trimmedDuration: nil
        )
    }

    private func deletePhoto(_ item: SelectedPhotoItem) {
        selectedImages.removeAll { $0.id == item.id }
        
        if highlightedSelectedItemId == item.id {
            highlightedSelectedItemId = nil
        }
        
        // Clean up trimmed video file if it exists
        if let trimmedURL = item.trimmedVideoURL {
            try? FileManager.default.removeItem(at: trimmedURL)
        }
        
        // Clean up original video temporary file if it exists
        if let originalURL = item.originalVideoURL {
            try? FileManager.default.removeItem(at: originalURL)
        }
        
        photoToDelete = nil
    }
    
    @MainActor
    private func trimVideo(item: SelectedPhotoItem, startTime: TimeInterval, endTime: TimeInterval) async {
        guard let originalURL = item.originalVideoURL else {
            showingVideoTrimmer = false
            return
        }
        
        let trimmingService = VideoTrimmingService()
        
        do {
            // Trim the video
            let trimmedURL = try await trimmingService.trimVideo(
                sourceURL: originalURL,
                startTime: startTime,
                endTime: endTime
            )
            
            let trimmedDuration = endTime - startTime
            
            // Generate new thumbnail from trimmed video
            let thumbnailImage = try await trimmingService.generateThumbnail(from: trimmedURL, at: 0)
            
            // Create updated item with trimmed video
            let updatedItem = SelectedPhotoItem(
                pickerItem: item.pickerItem,
                image: Image(uiImage: thumbnailImage),
                localIdentifier: item.localIdentifier,
                isVideo: true,
                duration: item.duration,
                trimmedVideoURL: trimmedURL,
                originalVideoURL: originalURL,
                trimmedDuration: trimmedDuration
            )
            
            // Add to selected images
            selectedImages.append(updatedItem)
            
            // Clear pending state
            pendingVideoItem = nil
            videoToTrim = nil
            showingVideoTrimmer = false
            
        } catch {
            errorMessage = "Failed to trim video. Please try again."
            showErrorAlert = true
            showingVideoTrimmer = false
        }
    }
}

private struct SelectedPhotoActionSheet: View {
    let isVideo: Bool
    let isHighlighted: Bool
    let onMakeHighlighted: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    private var labels: (options: String, highlight: String, delete: String) {
        if isVideo {
            return ("Video Options", "Make Highlighted Video", "Delete Video")
        } else {
            return ("Photo Options", "Make Highlighted Photo", "Delete Photo")
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(labels.options)
                    .font(.montserratBold(size: 20))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
            }
            
            VStack(spacing: 12) {
                if !isHighlighted {
                    Button(action: onMakeHighlighted) {
                        actionRow(
                            systemImage: "star.fill",
                            text: labels.highlight,
                            tint: .accent,
                            textColor: effectiveColorScheme == .dark ? .white : .black
                        )
                    }
                } else {
                    highlightedRow
                }
                
                Button(role: .destructive, action: onDelete) {
                    actionRow(
                        systemImage: "trash",
                        text: labels.delete,
                        tint: .red,
                        textColor: .red
                    )
                }
            }
            
            Button(action: onCancel) {
                Text("Cancel")
                    .font(.montserratMedium(size: 16))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(effectiveColorScheme == .dark ? .white.opacity(0.05) : .gray.opacity(0.05))
                    )
            }
        }
        .padding(20)
        .themedBackground()
    }
    
    private func actionRow(systemImage: String, text: String, tint: Color, textColor: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18))
                .foregroundStyle(tint)
            
            Text(text)
                .font(.montserratMedium(size: 16))
                .foregroundStyle(textColor)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1))
        )
    }
    
    private var highlightedRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "star.fill")
                .font(.system(size: 18))
                .foregroundStyle(.accent)
            
            Text("Currently Highlighted")
                .font(.montserratMedium(size: 16))
                .foregroundStyle(.accent)
            
            Spacer()
            
            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.accent.opacity(0.15))
        )
    }
}

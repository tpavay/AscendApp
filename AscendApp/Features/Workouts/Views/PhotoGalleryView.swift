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
    var embeddedInScrollRow: Bool = false
    
    @State private var selectedPhotos: [PhotosPickerItem] = [] // Make this local state
    @State private var photoToDelete: SelectedPhotoItem?
    @State private var itemForActionSheet: SelectedPhotoItem?
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var isLoadingMedia = false // Loading state for media processing
    
    init(
        selectedImages: Binding<[SelectedPhotoItem]>,
        highlightedSelectedItemId: Binding<UUID?> = .constant(nil),
        existingMediaCount: Int = 0,
        existingVideoCount: Int = 0,
        embeddedInScrollRow: Bool = false
    ) {
        self._selectedImages = selectedImages
        self._highlightedSelectedItemId = highlightedSelectedItemId
        self.existingMediaCount = existingMediaCount
        self.existingVideoCount = existingVideoCount
        self.embeddedInScrollRow = embeddedInScrollRow
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
            if embeddedInScrollRow {
                embeddedGalleryContent
            } else if selectedImages.isEmpty {
                standaloneEmptyState
            } else {
                ScrollView(.horizontal) {
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
                            compactPickerButton
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .scrollIndicators(.hidden)
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

    @ViewBuilder
    private var standaloneEmptyState: some View {
        if existingMediaCount > 0 {
            if canAddMore {
                compactPickerButton
            }
        } else {
            PhotoPickerButton(selectedPhotos: $selectedPhotos, isLoading: isLoadingMedia)
                .frame(height: 120)
        }
    }

    private var embeddedGalleryContent: some View {
        HStack(spacing: 12) {
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

            if canAddMore {
                compactPickerButton
            }
        }
    }

    private var compactPickerButton: some View {
        PhotoPickerButton(
            selectedPhotos: $selectedPhotos,
            isLoading: isLoadingMedia,
            style: .inlineTile
        )
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

        // Check if any videos exceed 15 seconds or have unknown duration
        var validItems: [SelectedPhotoItem] = []
        var hasInvalidVideo = false

        for item in newSelectedImages {
            if item.isVideo {
                // Reject if duration is unknown (nil) or exceeds 15 seconds
                guard let duration = item.duration, duration <= 15 else {
                    hasInvalidVideo = true
                    // Clean up the temporary file
                    if let videoURL = item.videoURL {
                        try? FileManager.default.removeItem(at: videoURL)
                    }
                    continue
                }
            }
            validItems.append(item)
        }

        // Show error if any video was invalid
        if hasInvalidVideo {
            errorMessage = "Video must be 15 seconds or less."
            showErrorAlert = true
        }

        // Add valid items
        selectedImages.append(contentsOf: validItems)

        // Clear loading state
        isLoadingMedia = false
        selectedPhotos.removeAll()
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
            videoURL: movie.url
        )
    }

    private func deletePhoto(_ item: SelectedPhotoItem) {
        selectedImages.removeAll { $0.id == item.id }

        if highlightedSelectedItemId == item.id {
            highlightedSelectedItemId = nil
        }

        // Clean up video temporary file if it exists
        if let videoURL = item.videoURL {
            try? FileManager.default.removeItem(at: videoURL)
        }

        photoToDelete = nil
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
        AppSheetScaffold(title: labels.options, layout: .actionMenu) {
            VStack(spacing: 12) {
                if !isHighlighted {
                    Button(action: onMakeHighlighted) {
                        AppSheetOptionRow(
                            systemImage: "star.fill",
                            title: labels.highlight,
                            iconTint: .accent,
                            style: .compact
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    AppSheetOptionRow(
                        systemImage: "star.fill",
                        title: "Currently Highlighted",
                        iconTint: .accent,
                        tone: .accent,
                        style: .compact,
                        trailingSymbol: "checkmark",
                        trailingTint: .accent
                    )
                }
                
                Button(role: .destructive, action: onDelete) {
                    AppSheetOptionRow(
                        systemImage: "trash",
                        title: labels.delete,
                        iconTint: .red,
                        tone: .destructive,
                        style: .compact
                    )
                }
                .buttonStyle(.plain)
            }
        } footer: {
            Button(action: onCancel) {
                Text("Cancel")
            }
            .appSheetButtonStyle(tone: .subtle)
        }
        .appSheetStyle(.actionMenu)
    }
}

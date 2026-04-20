//
//  PhotoGalleryView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 9/20/25.
//

import SwiftUI
import PhotosUI

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
    @State private var mediaProcessingTask: Task<Void, Never>?
    @State private var activeProcessingToken = UUID()
    
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
        .onChange(of: selectedPhotos) { _, newItems in
            beginProcessing(newItems)
        }
        .onDisappear {
            cancelMediaProcessing()
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
    private func beginProcessing(_ newItems: [PhotosPickerItem]) {
        mediaProcessingTask?.cancel()

        guard !newItems.isEmpty else {
            activeProcessingToken = UUID()
            mediaProcessingTask = nil
            isLoadingMedia = false
            return
        }

        let token = UUID()
        activeProcessingToken = token
        isLoadingMedia = true

        mediaProcessingTask = Task {
            defer {
                finishProcessing(token)
            }

            let preparationOutcome = await SelectedMediaPreparationService.prepareItems(
                newItems,
                currentMediaCount: totalMediaCount,
                currentVideoCount: totalVideoCount
            )

            guard activeProcessingToken == token else {
                SelectedMediaPreparationService.cleanupTemporaryVideoFiles(in: preparationOutcome.items)
                return
            }

            if let alertMessage = preparationOutcome.alertMessage {
                errorMessage = alertMessage
                showErrorAlert = true
            }

            guard preparationOutcome.wasCancelled == false else {
                return
            }

            selectedImages.append(contentsOf: preparationOutcome.items)
        }
    }

    @MainActor
    private func cancelMediaProcessing() {
        activeProcessingToken = UUID()
        mediaProcessingTask?.cancel()
        mediaProcessingTask = nil
        selectedPhotos.removeAll()
        isLoadingMedia = false
    }

    @MainActor
    private func finishProcessing(_ token: UUID) {
        guard activeProcessingToken == token else { return }

        mediaProcessingTask = nil
        selectedPhotos.removeAll()
        isLoadingMedia = false
    }

    private func deletePhoto(_ item: SelectedPhotoItem) {
        selectedImages.removeAll { $0.id == item.id }

        if highlightedSelectedItemId == item.id {
            highlightedSelectedItemId = nil
        }

        SelectedMediaPreparationService.cleanupTemporaryVideoFile(at: item.videoURL)

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

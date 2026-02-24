//
//  WorkoutPhotosSection.swift
//  AscendApp
//
//  Created by Tyler Pavay on 9/26/25.
//

import SwiftUI
import SwiftData

struct WorkoutPhotosSection: View {
    @Bindable var workout: Workout
    @State private var selectedPhoto: Photo?
    @State private var photoForAction: Photo?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @State private var themeManager = ThemeManager.shared

    // Query pending uploads for this workout
    @Query private var pendingUploads: [PendingMediaUpload]

    init(workout: Workout) {
        self._workout = Bindable(wrappedValue: workout)
        let workoutId = workout.id
        self._pendingUploads = Query(
            filter: #Predicate<PendingMediaUpload> { $0.workoutId == workoutId },
            sort: [SortDescriptor(\PendingMediaUpload.orderIndex)]
        )
    }

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    /// Total count of photos (uploaded + pending)
    private var totalCount: Int {
        workout.photos.count + pendingUploads.count
    }

    /// Whether to show the section (has photos or pending uploads)
    private var shouldShow: Bool {
        !workout.photos.isEmpty || !pendingUploads.isEmpty
    }

    /// Unified media item for interleaved display
    private enum MediaItem: Identifiable {
        case uploaded(Photo, orderIndex: Int)
        case pending(PendingMediaUpload)

        var id: UUID {
            switch self {
            case .uploaded(let photo, _): return photo.id
            case .pending(let upload): return upload.id
            }
        }

        var orderIndex: Int {
            switch self {
            case .uploaded(_, let index): return index
            case .pending(let upload): return upload.orderIndex
            }
        }
    }

    /// Combined and sorted media items
    private var sortedMediaItems: [MediaItem] {
        let uploaded = workout.photos.enumerated().map { MediaItem.uploaded($1, orderIndex: $0) }
        let pending = pendingUploads.map { MediaItem.pending($0) }
        return (uploaded + pending).sorted { $0.orderIndex < $1.orderIndex }
    }

    var body: some View {
        if shouldShow {
            VStack(spacing: 16) {
                // Section header
                HStack {
                    Text("Photos & Videos")
                        .font(.montserratSemiBold(size: 20))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                    Text("(\(totalCount))")
                        .font(.montserratRegular(size: 16))
                        .foregroundStyle(.gray)

                    Spacer()
                }

                // Photos grid with interleaved placeholders
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(sortedMediaItems) { item in
                            switch item {
                            case .uploaded(let photo, _):
                                uploadedPhotoView(photo: photo)
                            case .pending(let upload):
                                pendingUploadPlaceholder(upload: upload)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
            }
            .fullScreenCover(item: $selectedPhoto) { photo in
                FullScreenPhotoView(photo: photo) {
                    selectedPhoto = nil
                }
            }
            .sheet(item: $photoForAction) { photo in
                PhotoActionSheet(
                    photo: photo,
                    isHighlighted: isHighlighted(photo),
                    onMakeHighlighted: {
                        makeHighlighted(photo)
                        photoForAction = nil
                    },
                    onDelete: {
                        Task {
                            await deletePhoto(photo)
                        }
                        photoForAction = nil
                    },
                    onCancel: {
                        photoForAction = nil
                    }
                )
                .presentationDetents([.height(isHighlighted(photo) ? 260 : 280)])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - View Builders

    @ViewBuilder
    private func uploadedPhotoView(photo: Photo) -> some View {
        ZStack(alignment: .topLeading) {
            LoadablePhotoView(
                photo: photo,
                size: CGSize(width: 110, height: 110),
                cornerRadius: 10
            ) {
                selectedPhoto = photo
            }

            // Highlighted indicator
            if isHighlighted(photo) {
                Image(systemName: "star.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(
                        Circle()
                            .fill(.accent)
                    )
                    .padding(6)
            }
        }
        .contextMenu {
            if !isHighlighted(photo) {
                Button {
                    makeHighlighted(photo)
                } label: {
                    Label(photo.isVideo ? "Make Highlighted Video" : "Make Highlighted Photo", systemImage: "star.fill")
                }
            }

            Button(role: .destructive) {
                photoForAction = photo
            } label: {
                Label(photo.isVideo ? "Delete Video" : "Delete Photo", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func pendingUploadPlaceholder(upload: PendingMediaUpload) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(effectiveColorScheme == .dark ? Color.white.opacity(0.1) : Color.gray.opacity(0.15))
                .frame(width: 110, height: 110)

            if upload.uploadStatus == .failed {
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.orange)
                    Text("Failed")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            } else {
                VStack(spacing: 4) {
                    ProgressView()
                        .tint(effectiveColorScheme == .dark ? .white : .gray)
                    Text("Uploading")
                        .font(.caption2)
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
                }
            }

            // Video indicator
            if upload.isVideo {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "video.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.5))
                            )
                        Spacer()
                    }
                    .padding(6)
                }
            }
        }
    }

    // MARK: - Helper Methods

    private func isHighlighted(_ photo: Photo) -> Bool {
        // Check if this photo is the highlighted one
        if let highlightedId = workout.highlightedPhotoId {
            return highlightedId == photo.id
        }
        // Fallback: if no highlighted photo is set, the first photo is considered highlighted
        return workout.photos.first?.id == photo.id
    }

    private func makeHighlighted(_ photo: Photo) {
        workout.setHighlightedPhoto(photo.id)
        try? modelContext.save()
    }

    private func deletePhoto(_ photo: Photo) async {
        // Delete from Firebase
        do {
            let photoService = PhotoService()
            try await photoService.deletePhotos([photo])
        } catch {
            print("Failed to delete photo from Firebase: \(error)")
            return
        }

        // Remove from workout
        workout.photos.removeAll { $0.id == photo.id }

        // If the deleted photo was highlighted, reset to first available
        if workout.highlightedPhotoId == photo.id {
            workout.highlightedPhotoId = workout.photos.first?.id
        }

        try? modelContext.save()
    }
}

#Preview {
    let workout = Workout(
        name: "Sample Workout",
        duration: 1800,
        steps: 2500,
        floors: 156,
        photos: [
            Photo(url: URL(string: "https://picsum.photos/200/200?random=1")!),
            Photo(url: URL(string: "https://picsum.photos/200/200?random=2")!),
            Photo(url: URL(string: "https://picsum.photos/200/200?random=3")!)
        ]
    )

    return WorkoutPhotosSection(workout: workout)
        .padding()
}

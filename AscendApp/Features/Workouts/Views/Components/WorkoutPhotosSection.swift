//
//  WorkoutPhotosSection.swift
//  AscendApp
//
//  Created by Tyler Pavay on 9/26/25.
//

import SwiftUI

struct WorkoutPhotosSection: View {
    @Bindable var workout: Workout
    @State private var selectedPhoto: Photo?
    @State private var photoForAction: Photo?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        VStack(spacing: 16) {
            // Section header
            HStack {
                Text("Photos & Videos")
                    .font(.montserratSemiBold(size: 20))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                Text("(\(workout.photos.count))")
                    .font(.montserratRegular(size: 16))
                    .foregroundStyle(.gray)

                Spacer()
            }

            // Photos grid
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(workout.photos) { photo in
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
                }
                .padding(.vertical, 4)
            }
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
            print("❌ Failed to delete photo from Firebase: \(error)")
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

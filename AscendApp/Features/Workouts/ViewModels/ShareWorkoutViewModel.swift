//
//  ShareWorkoutViewModel.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/5/25.
//

import Foundation
import SwiftUI
import UIKit

@MainActor
final class ShareWorkoutViewModel: ObservableObject {
    static let posterExportSize = CGSize(width: 1080, height: 1350)
    static let posterAspectRatio = posterExportSize.width / posterExportSize.height
    static let displayCardHeight: CGFloat = 420
    static let displayCardWidth: CGFloat = displayCardHeight * posterAspectRatio

    @Published var usesPhotoBackground: Bool = false
    @Published var backgroundImage: UIImage? = nil
    @Published var isLoadingBackground: Bool = false

    let workout: Workout
    private var backgroundLoadTask: Task<Void, Never>?

    init(workout: Workout) {
        self.workout = workout
        preloadDefaultBackground()
    }

    func useDefaultBackground() {
        cancelBackgroundLoad()
        isLoadingBackground = false
        usesPhotoBackground = false
    }

    func updateBackgroundImage(_ image: UIImage?) {
        backgroundImage = image
        usesPhotoBackground = image != nil
    }

    func renderCurrentPoster(
        measurementSystem: MeasurementSystem,
        stepHeight: Double
    ) -> UIImage? {
        let poster = WorkoutSharePoster(
            workout: workout,
            usesPhotoBackground: usesPhotoBackground,
            backgroundImage: backgroundImage,
            measurementSystem: measurementSystem,
            stepHeight: stepHeight
        )

        let content = poster
            .frame(
                width: ShareWorkoutViewModel.displayCardWidth,
                height: ShareWorkoutViewModel.displayCardHeight
            )
            .clipped()

        let renderer = ImageRenderer(content: content)
        renderer.scale = ShareWorkoutViewModel.posterExportSize.height / ShareWorkoutViewModel.displayCardHeight
        return renderer.uiImage
    }

    func shareText(
        measurementSystem: MeasurementSystem,
        stepHeight: Double
    ) -> String {
        workoutShareText(
            for: workout,
            measurementSystem: measurementSystem,
            stepHeight: stepHeight
        )
    }

    private func preloadDefaultBackground() {
        guard backgroundImage == nil,
              let photoURL = workout.photos.first?.url else {
            return
        }

        startBackgroundLoad(for: photoURL)
    }

    private func startBackgroundLoad(for url: URL) {
        cancelBackgroundLoad()
        isLoadingBackground = true

        backgroundLoadTask = Task { [url] in
            let image = await Self.loadImage(from: url)
            await MainActor.run {
                defer { self.backgroundLoadTask = nil }

                guard !Task.isCancelled else {
                    self.isLoadingBackground = false
                    return
                }

                if let image, self.backgroundImage == nil {
                    self.backgroundImage = image
                    self.usesPhotoBackground = true
                }
                self.isLoadingBackground = false
            }
        }
    }

    private func cancelBackgroundLoad() {
        backgroundLoadTask?.cancel()
        backgroundLoadTask = nil
    }

    private static func loadImage(from url: URL) async -> UIImage? {
        await Task.detached(priority: .utility) { () -> UIImage? in
            do {
                let data: Data
                if url.isFileURL {
                    data = try Data(contentsOf: url)
                } else {
                    let (remoteData, _) = try await URLSession.shared.data(from: url)
                    data = remoteData
                }
                return UIImage(data: data)
            } catch {
                return nil
            }
        }.value
    }
}

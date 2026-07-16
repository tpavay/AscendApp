//
//  SelectedMediaPreparationService.swift
//  AscendApp
//
//  Created by Codex on 4/13/26.
//

import AVFoundation
import Foundation
import PhotosUI
import SwiftUI

enum SelectedMediaPreparationService {
    static let maximumMediaCount = 3
    static let maximumVideoCount = 1
    static let maximumVideoDuration: TimeInterval = 15

    struct PreparationOutcome {
        let items: [SelectedPhotoItem]
        let alertMessage: String?
        let wasCancelled: Bool
    }

    static func validationMessage(
        forAdditionalMediaCount additionalMediaCount: Int,
        additionalVideoCount: Int,
        currentMediaCount: Int,
        currentVideoCount: Int
    ) -> String? {
        let potentialTotal = currentMediaCount + additionalMediaCount
        if potentialTotal > maximumMediaCount {
            return "Only 3 combined photos and videos (max 1 video) can be added to a given workout."
        }

        if currentVideoCount + additionalVideoCount > maximumVideoCount {
            return "You can only add one video with a max length of 15 seconds."
        }

        return nil
    }

    static func prepareItems(
        _ newItems: [PhotosPickerItem],
        currentMediaCount: Int,
        currentVideoCount: Int
    ) async -> PreparationOutcome {
        if let validationMessage = validationMessage(
            forAdditionalMediaCount: newItems.count,
            additionalVideoCount: additionalVideoCount(in: newItems),
            currentMediaCount: currentMediaCount,
            currentVideoCount: currentVideoCount
        ) {
            return PreparationOutcome(items: [], alertMessage: validationMessage, wasCancelled: false)
        }

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

        if Task.isCancelled {
            cleanupTemporaryVideoFiles(in: newSelectedImages)
            return PreparationOutcome(items: [], alertMessage: nil, wasCancelled: true)
        }

        var validItems: [SelectedPhotoItem] = []
        var hasInvalidVideo = false

        for item in newSelectedImages {
            if item.isVideo {
                guard let duration = item.duration, duration <= maximumVideoDuration else {
                    hasInvalidVideo = true
                    cleanupTemporaryVideoFile(at: item.videoURL)
                    continue
                }
            }

            validItems.append(item)
        }

        if Task.isCancelled {
            cleanupTemporaryVideoFiles(in: validItems)
            return PreparationOutcome(items: [], alertMessage: nil, wasCancelled: true)
        }

        let alertMessage = hasInvalidVideo ? "Video must be 15 seconds or less." : nil
        return PreparationOutcome(items: validItems, alertMessage: alertMessage, wasCancelled: false)
    }

    static func cleanupTemporaryVideoFiles(in items: [SelectedPhotoItem]) {
        for item in items {
            cleanupTemporaryVideoFile(at: item.videoURL)
        }
    }

    static func cleanupTemporaryVideoFile(at url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func additionalVideoCount(in items: [PhotosPickerItem]) -> Int {
        var newVideoCount = 0
        for item in items {
            if let contentType = item.supportedContentTypes.first?.identifier,
               contentType.contains("video") || contentType.contains("movie") {
                newVideoCount += 1
            }
        }
        return newVideoCount
    }

    private static func createSelectedPhotoItem(from item: PhotosPickerItem) async -> SelectedPhotoItem? {
        if let contentType = item.supportedContentTypes.first?.identifier,
           contentType.contains("video") || contentType.contains("movie") {
            return await createVideoItem(from: item)
        } else {
            return await createPhotoItem(from: item)
        }
    }

    private static func createPhotoItem(from item: PhotosPickerItem) async -> SelectedPhotoItem? {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data) else {
                return nil
            }

            try Task.checkCancellation()

            return SelectedPhotoItem(
                pickerItem: item,
                image: Image(uiImage: uiImage),
                localIdentifier: item.itemIdentifier ?? UUID().uuidString,
                isVideo: false,
                duration: nil
            )
        } catch {
            return nil
        }
    }

    private static func createVideoItem(from item: PhotosPickerItem) async -> SelectedPhotoItem? {
        guard let movie = try? await item.loadTransferable(type: VideoPickerTransferable.self) else {
            return nil
        }

        do {
            try Task.checkCancellation()

            let asset = AVURLAsset(url: movie.url)
            let loadedDuration = try await asset.load(.duration)
            let duration = loadedDuration.seconds
            guard duration.isFinite else {
                cleanupTemporaryVideoFile(at: movie.url)
                return nil
            }

            try Task.checkCancellation()

            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true

            let cgImage = try await imageGenerator.image(at: .zero).image

            try Task.checkCancellation()

            let uiImage = UIImage(cgImage: cgImage)

            return SelectedPhotoItem(
                pickerItem: item,
                image: Image(uiImage: uiImage),
                localIdentifier: item.itemIdentifier ?? UUID().uuidString,
                isVideo: true,
                duration: duration,
                videoURL: movie.url
            )
        } catch {
            cleanupTemporaryVideoFile(at: movie.url)
            return nil
        }
    }
}

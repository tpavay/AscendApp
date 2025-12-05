//
//  VideoTrimmingService.swift
//  AscendApp
//
//  Created by Tyler Pavay on 11/21/25.
//

import AVFoundation
import UIKit

actor VideoTrimmingService {
    enum TrimmingError: Error {
        case invalidTimeRange
        case exportFailed
        case assetCreationFailed
    }
    
    /// Trims a video to the specified time range
    /// - Parameters:
    ///   - sourceURL: The URL of the original video
    ///   - startTime: The start time in seconds
    ///   - endTime: The end time in seconds
    /// - Returns: The URL of the trimmed video
    func trimVideo(sourceURL: URL, startTime: TimeInterval, endTime: TimeInterval) async throws -> URL {
        guard endTime > startTime else {
            throw TrimmingError.invalidTimeRange
        }
        
        let asset = AVURLAsset(url: sourceURL)
        // Preload essential properties to avoid synchronous blocking
        try await asset.load(.isExportable, .duration, .tracks)

        // Create output URL
        let outputURL = URL.temporaryDirectory
            .appending(path: "trimmed_\(UUID().uuidString).\(sourceURL.pathExtension)")
        
        // Remove if exists
        try? FileManager.default.removeItem(at: outputURL)
        
        // Create export session
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw TrimmingError.assetCreationFailed
        }
        
        // Configure export
        let startCMTime = CMTime(seconds: startTime, preferredTimescale: 600)
        let endCMTime = CMTime(seconds: endTime, preferredTimescale: 600)
        let timeRange = CMTimeRange(start: startCMTime, end: endCMTime)
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        exportSession.timeRange = timeRange
        
        // Export the video
        // Note: export() and status are deprecated in iOS 18 but the replacement API
        // states(updateInterval:) has limited documentation. Using deprecated API for now.
        await exportSession.export()

        guard exportSession.status == .completed else {
            throw TrimmingError.exportFailed
        }

        return outputURL
    }
    
    /// Generates a thumbnail for a video at a specific time
    /// - Parameters:
    ///   - url: The video URL
    ///   - time: The time in seconds to generate thumbnail from
    /// - Returns: A UIImage thumbnail
    func generateThumbnail(from url: URL, at time: TimeInterval) async throws -> UIImage {
        let asset = AVURLAsset(url: url)
        // Preload to ensure asset is ready for thumbnail generation
        try await asset.load(.isReadable, .tracks)

        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceAfter = .zero
        imageGenerator.requestedTimeToleranceBefore = .zero
        
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        let cgImage = try await imageGenerator.image(at: cmTime).image
        
        return UIImage(cgImage: cgImage)
    }
}


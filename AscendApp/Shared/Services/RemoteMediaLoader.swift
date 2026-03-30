//
//  RemoteMediaLoader.swift
//  AscendApp
//
//  Created by Codex on 3/30/26.
//

import AVFoundation
import UIKit

struct RemoteMediaLoader: Sendable {
    enum LoaderError: LocalizedError {
        case timedOut(kind: MediaKind)
        case invalidResponse(statusCode: Int?)
        case invalidImageData
        case videoNotPlayable

        enum MediaKind: String {
            case photo
            case video
            case videoThumbnail
        }

        var errorDescription: String? {
            switch self {
            case .timedOut(let kind):
                return "\(kind.rawValue.capitalized) load timed out."
            case .invalidResponse(let statusCode):
                if let statusCode {
                    return "Received an invalid media response (\(statusCode))."
                }
                return "Received an invalid media response."
            case .invalidImageData:
                return "Received invalid image data."
            case .videoNotPlayable:
                return "Video is not currently playable."
            }
        }
    }

    typealias PhotoRequest = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    typealias VideoPlayableRequest = @Sendable (URL) async throws -> Void

    static let shared = RemoteMediaLoader()

    private let imageCache: ImageCache
    private let photoRequest: PhotoRequest
    private let videoPlayableRequest: VideoPlayableRequest
    private let requestTimeoutSeconds: Double
    private let errorRecorder: @Sendable (Error, LoaderError.MediaKind) -> Void

    init(
        imageCache: ImageCache = .shared,
        requestTimeoutSeconds: Double = 15.0,
        photoRequest: PhotoRequest? = nil,
        videoPlayableRequest: VideoPlayableRequest? = nil,
        errorRecorder: @escaping @Sendable (Error, LoaderError.MediaKind) -> Void = Self.recordError(_:kind:)
    ) {
        self.imageCache = imageCache
        self.requestTimeoutSeconds = requestTimeoutSeconds
        self.photoRequest = photoRequest ?? Self.defaultPhotoRequest(timeoutSeconds: requestTimeoutSeconds)
        self.videoPlayableRequest = videoPlayableRequest ?? Self.defaultVideoPlayableRequest
        self.errorRecorder = errorRecorder
    }

    func loadPhoto(from url: URL) async -> UIImage? {
        if let cached = imageCache.image(for: url) {
            return cached
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = requestTimeoutSeconds

        do {
            let (data, response) = try await photoRequest(request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LoaderError.invalidResponse(statusCode: nil)
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw LoaderError.invalidResponse(statusCode: httpResponse.statusCode)
            }
            guard let image = UIImage(data: data) else {
                throw LoaderError.invalidImageData
            }

            imageCache.store(image, for: url)
            return image
        } catch is CancellationError {
            return nil
        } catch {
            errorRecorder(error, .photo)
            return nil
        }
    }

    func loadVideoThumbnail(from url: URL) async -> UIImage? {
        if let cached = imageCache.image(for: url) {
            return cached
        }

        guard await canPrepareVideo(from: url) else {
            return nil
        }

        let asset = AVURLAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true

        do {
            let cgImage = try await imageGenerator.image(at: .zero).image
            let image = UIImage(cgImage: cgImage)
            imageCache.store(image, for: url)
            return image
        } catch is CancellationError {
            return nil
        } catch {
            errorRecorder(error, .videoThumbnail)
            return nil
        }
    }

    func canPrepareVideo(from url: URL) async -> Bool {
        do {
            try await Self.runWithTimeout(seconds: requestTimeoutSeconds) {
                try await videoPlayableRequest(url)
            }
            return true
        } catch is CancellationError {
            return false
        } catch {
            errorRecorder(error, .video)
            return false
        }
    }

    private static func defaultPhotoRequest(timeoutSeconds: Double) -> PhotoRequest {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeoutSeconds
        configuration.timeoutIntervalForResource = timeoutSeconds
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration)

        return { request in
            try await session.data(for: request)
        }
    }

    private static func defaultVideoPlayableRequest(_ url: URL) async throws {
        let asset = AVURLAsset(url: url)
        let isPlayable = try await asset.load(.isPlayable)
        guard isPlayable else {
            throw LoaderError.videoNotPlayable
        }
    }

    private static func runWithTimeout(
        seconds: Double,
        operation: @escaping @Sendable () async throws -> Void
    ) async throws {
        try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask {
                try await operation()
                return true
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                return false
            }

            let result = try await group.next()!
            group.cancelAll()

            if !result {
                throw LoaderError.timedOut(kind: .video)
            }
        }
    }

    private static func recordError(_ error: Error, kind: LoaderError.MediaKind) {
        TelemetryManager.shared.recordError(
            error,
            context: .network,
            code: "remote_media_load_failed",
            additionalInfo: ["media_kind": kind.rawValue]
        )
    }
}

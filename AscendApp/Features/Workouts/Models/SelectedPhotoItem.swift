//
//  SelectedPhotoItem.swift
//  AscendApp
//
//  Created by Tyler Pavay on 9/20/25.
//

import Foundation
import PhotosUI
import SwiftUI
import AVFoundation

struct SelectedPhotoItem: Identifiable {
    let id = UUID()
    let pickerItem: PhotosPickerItem
    let image: Image
    let localIdentifier: String
    let isVideo: Bool
    let duration: TimeInterval?
    var trimmedVideoURL: URL? // URL of trimmed video if applicable
    var originalVideoURL: URL? // Original video URL before trimming
    var trimmedDuration: TimeInterval? // Duration after trimming
    
    init(
        pickerItem: PhotosPickerItem,
        image: Image,
        localIdentifier: String,
        isVideo: Bool = false,
        duration: TimeInterval? = nil,
        trimmedVideoURL: URL? = nil,
        originalVideoURL: URL? = nil,
        trimmedDuration: TimeInterval? = nil
    ) {
        self.pickerItem = pickerItem
        self.image = image
        self.localIdentifier = localIdentifier
        self.isVideo = isVideo
        self.duration = duration
        self.trimmedVideoURL = trimmedVideoURL
        self.originalVideoURL = originalVideoURL
        self.trimmedDuration = trimmedDuration
    }
    
    /// Returns the effective duration (trimmed duration if available, otherwise original)
    var effectiveDuration: TimeInterval? {
        trimmedDuration ?? duration
    }
    
    /// Returns the effective video URL (trimmed if available, otherwise original)
    var effectiveVideoURL: URL? {
        trimmedVideoURL ?? originalVideoURL
    }
}

// Custom transferable for video
struct VideoPickerTransferable: Transferable {
    let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let copy = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).\(received.file.pathExtension)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self(url: copy)
        }
    }
}

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
    var videoURL: URL?

    init(
        pickerItem: PhotosPickerItem,
        image: Image,
        localIdentifier: String,
        isVideo: Bool = false,
        duration: TimeInterval? = nil,
        videoURL: URL? = nil
    ) {
        self.pickerItem = pickerItem
        self.image = image
        self.localIdentifier = localIdentifier
        self.isVideo = isVideo
        self.duration = duration
        self.videoURL = videoURL
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

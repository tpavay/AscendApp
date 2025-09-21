//
//  PhotoService.swift
//  AscendApp
//
//  Created by Tyler Pavay on 9/20/25.
//

import PhotosUI
import SwiftUI

class PhotoService {
    private let photoRepository: PhotoRepositoryProtocol

    init(photoRepository: PhotoRepositoryProtocol = FirebasePhotoRepository()) {
        self.photoRepository = photoRepository
    }

    func uploadPhotos(_ items: [PhotosPickerItem]) async throws -> [Photo] {
        var photos: [Photo] = []

        for item in items {
            // 1. Extract data from PhotosPickerItem
            guard let data = try await item.loadTransferable(type: Data.self) else {
                continue // Skip invalid items
            }

            // 2. Create unique filename
            let filename = "photos/\(UUID().uuidString).jpg"

            // 3. Upload via repository
            let downloadURL = try await photoRepository.upload(data, filename: filename)

            // 4. Create domain model
            let photo = Photo(url: downloadURL)
            photos.append(photo)
        }

        return photos
    }
}

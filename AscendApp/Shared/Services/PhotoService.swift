//
//  PhotoService.swift
//  AscendApp
//
//  Created by Tyler Pavay on 9/20/25.
//

import PhotosUI
import SwiftUI

actor PhotoService {
    private let repo: any PhotoRepositoryProtocol
    init(repo: any PhotoRepositoryProtocol = FirebasePhotoRepository()) {
        self.repo = repo
    }

    func uploadPhotos(_ items: [PhotosPickerItem]) async throws -> [Photo] {
        let repo = self.repo
        return try await withThrowingTaskGroup(of: Photo?.self) { group in
            for item in items {
                group.addTask {
                    guard let data = try await item.loadTransferable(type: Data.self) else { return nil }
                    let filename = "photos/\(UUID().uuidString).jpg"
                    let url = try await repo.upload(data, filename: filename)
                    return Photo(url: url)
                }
            }
            var out: [Photo] = []
            for try await p in group { if let p { out.append(p) } }
            return out
        }
    }

    func deletePhotos(_ photos: [Photo]) async throws {
        let repo = self.repo
        try await withThrowingTaskGroup(of: Void.self) { group in
            for photo in photos {
                group.addTask {
                    try await repo.delete(url: photo.url)
                }
            }
            try await group.waitForAll()
        }
    }
}

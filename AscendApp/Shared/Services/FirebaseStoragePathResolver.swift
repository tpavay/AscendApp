//
//  FirebaseStoragePathResolver.swift
//  AscendApp
//
//  Created by Codex on 3/29/26.
//

import Foundation

enum FirebaseStoragePathResolver {
    static func storagePath(for photo: Photo) -> String? {
        if let storagePath = photo.storagePath, !storagePath.isEmpty {
            return storagePath
        }

        return storagePath(from: photo.url)
    }

    static func storagePath(from url: URL) -> String? {
        if url.scheme == "gs" {
            return url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let encodedPath = components.percentEncodedPath.components(separatedBy: "/o/").last
        else {
            return nil
        }

        return encodedPath.removingPercentEncoding
    }
}

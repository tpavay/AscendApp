import Foundation

final class DiskAssetCache: @unchecked Sendable {
    static let climbCatalog = DiskAssetCache(
        namespace: "ClimbCatalog",
        maxBytes: 12 * 1024 * 1024
    )

    static let climbImages = DiskAssetCache(
        namespace: "ClimbImages",
        maxBytes: 320 * 1024 * 1024
    )

    private let fileManager: FileManager
    private let directoryURL: URL
    private let maxBytes: Int
    private let lock = NSLock()

    init(
        namespace: String,
        maxBytes: Int,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.maxBytes = maxBytes

        let cachesDirectory = fileManager.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? URL.cachesDirectory

        self.directoryURL = cachesDirectory.appending(path: "AscendApp/\(namespace)")

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            assertionFailure("Failed to create cache directory \(directoryURL): \(error)")
        }
    }

    func data(for key: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }

        let fileURL = fileURL(for: key)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        touch(fileURL)
        return try Data(contentsOf: fileURL)
    }

    func fileURLIfPresent(for key: String) -> URL? {
        lock.lock()
        defer { lock.unlock() }

        let fileURL = fileURL(for: key)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        touch(fileURL)
        return fileURL
    }

    @discardableResult
    func store(_ data: Data, for key: String) throws -> URL {
        lock.lock()
        defer { lock.unlock() }

        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let fileURL = fileURL(for: key)
        try data.write(to: fileURL, options: .atomic)
        touch(fileURL)
        try trimIfNeeded()
        return fileURL
    }

    @discardableResult
    func storeFile(at sourceURL: URL, for key: String) throws -> URL {
        lock.lock()
        defer { lock.unlock() }

        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let destinationURL = fileURL(for: key)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        touch(destinationURL)
        try trimIfNeeded()
        return destinationURL
    }

    func remove(for key: String) throws {
        lock.lock()
        defer { lock.unlock() }

        let fileURL = fileURL(for: key)
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    func clear() throws {
        lock.lock()
        defer { lock.unlock() }

        guard fileManager.fileExists(atPath: directoryURL.path) else { return }
        try fileManager.removeItem(at: directoryURL)
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    private func fileURL(for key: String) -> URL {
        let pathExtension = URL(fileURLWithPath: key).pathExtension
        let hashedKey = Data(key.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")

        if pathExtension.isEmpty {
            return directoryURL.appending(path: hashedKey)
        }

        return directoryURL.appending(path: "\(hashedKey).\(pathExtension)")
    }

    private func touch(_ fileURL: URL) {
        try? fileManager.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: fileURL.path
        )
    }

    private func trimIfNeeded() throws {
        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]

        let fileURLs = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        )

        var entries: [(url: URL, size: Int, modifiedAt: Date)] = []
        var totalBytes = 0

        for fileURL in fileURLs {
            let values = try fileURL.resourceValues(forKeys: resourceKeys)
            guard values.isRegularFile == true else { continue }

            let size = values.fileSize ?? 0
            totalBytes += size
            entries.append((
                url: fileURL,
                size: size,
                modifiedAt: values.contentModificationDate ?? .distantPast
            ))
        }

        guard totalBytes > maxBytes else { return }

        let sortedEntries = entries.sorted { $0.modifiedAt < $1.modifiedAt }
        var remainingBytes = totalBytes

        for entry in sortedEntries where remainingBytes > maxBytes {
            try fileManager.removeItem(at: entry.url)
            remainingBytes -= entry.size
        }
    }
}

//
//  ClosedLegacyMediaPath.swift
//  AscendApp
//

import Foundation

/// Recognises workout media that still lives at a bucket-root Storage prefix.
///
/// Uploads have written `users/{uid}/...` since the user-scoped path migration,
/// but media attached before it sits at the flat `photos/` and `videos/`
/// prefixes. A flat path names no owner, so any rule permissive enough to admit
/// the uploader admits every signed-in account; `storage.rules` therefore closes
/// those prefixes to all client access.
///
/// A delete aimed at one can only fail, and workout deletion refuses to proceed
/// while any media delete fails - so without this check, a climber holding a
/// pre-migration workout could never delete it.
enum ClosedLegacyMediaPath {

    private static let closedRootPrefixes = ["photos/", "videos/", "profile_pictures/"]

    /// Whether a Firebase Storage download URL points at a closed root prefix.
    static func addressesClosedRootObject(_ url: URL) -> Bool {
        guard let objectPath = storageObjectPath(in: url) else { return false }
        return closedRootPrefixes.contains { objectPath.hasPrefix($0) }
    }

    /// The object path a Firebase Storage download URL addresses.
    ///
    /// A download URL is `/v0/b/{bucket}/o/{object}`, with the whole object path
    /// percent-encoded into that last segment. The raw path is split before
    /// decoding - decoding first would turn `photos%2Ffile.jpg` into two
    /// segments and lose the shape. Anything not matching that layout returns
    /// nil, so an unrelated URL is never mistaken for a closed object.
    private static func storageObjectPath(in url: URL) -> String? {
        guard let encodedPath = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .percentEncodedPath else {
            return nil
        }

        let segments = encodedPath.split(separator: "/", omittingEmptySubsequences: true)
        guard segments.count == 5,
              segments[0] == "v0",
              segments[1] == "b",
              segments[3] == "o" else {
            return nil
        }

        return String(segments[4]).removingPercentEncoding
    }
}

extension Array where Element == Photo {
    /// Splits media into what the client can no longer reach and what it can.
    func partitionedByClosedLegacyPath() -> (unreachable: [Photo], deletable: [Photo]) {
        var unreachable: [Photo] = []
        var deletable: [Photo] = []

        for photo in self {
            if ClosedLegacyMediaPath.addressesClosedRootObject(photo.url) {
                unreachable.append(photo)
            } else {
                deletable.append(photo)
            }
        }

        return (unreachable, deletable)
    }
}

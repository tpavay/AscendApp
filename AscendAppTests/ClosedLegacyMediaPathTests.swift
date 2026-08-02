//
//  ClosedLegacyMediaPathTests.swift
//  AscendAppTests
//

import Foundation
import Testing
@testable import AscendApp

struct ClosedLegacyMediaPathTests {

    private static let bucket = "ascend-staging-fa7d5.firebasestorage.app"

    private static func downloadURL(objectPath: String) -> URL {
        let encoded = objectPath.replacing("/", with: "%2F")
        return URL(
            string: "https://firebasestorage.googleapis.com/v0/b/\(bucket)/o/\(encoded)"
                + "?alt=media&token=94f4cee6-de5e-4562-b7f8-c1cf2fbc6d44"
        )!
    }

    @Test
    func recognisesEveryClosedRootPrefix() {
        let closedPaths = [
            "photos/07765C1A-17D5-4F48-8BBA-F083989595F9.jpg",
            "videos/3C4D5E6F-7081-4923-A456-B7C8D9E0F1A2.mov",
            "profile_pictures/uid_4D5E6F70-8192-4A34-B567-C8D9E0F1A2B3.jpg",
        ]

        for path in closedPaths {
            #expect(
                ClosedLegacyMediaPath.addressesClosedRootObject(Self.downloadURL(objectPath: path)),
                "Expected \(path) to be recognised as unreachable."
            )
        }
    }

    @Test
    func leavesOwnerScopedMediaAlone() {
        // The uid segment is what makes these reachable, and "users/.../photos/"
        // must never be mistaken for the closed root "photos/" prefix.
        let ownedPaths = [
            "users/uFFxxP2fBUf15Y9Nv8gA1EAyRUF3/photos/CF12C2B5-EEF6-424E-AD37-C793DBB429BF.jpg",
            "users/uFFxxP2fBUf15Y9Nv8gA1EAyRUF3/videos/E2BA1D96-B0A1-475D-836F-CA86ED48601D.mov",
            "users/uFFxxP2fBUf15Y9Nv8gA1EAyRUF3/profile_pictures/58E60C20-68D3-4A91-9E5A-3F725C845D3B.jpg",
        ]

        for path in ownedPaths {
            #expect(
                !ClosedLegacyMediaPath.addressesClosedRootObject(Self.downloadURL(objectPath: path)),
                "Expected \(path) to stay deletable."
            )
        }
    }

    @Test
    func treatsUnrecognisedURLsAsReachable() {
        // Anything that is not a Storage download URL keeps its normal delete
        // path: guessing "unreachable" would silently skip a real cleanup.
        let strangers = [
            "https://example.com/photos/whatever.jpg",
            "https://example.com/v0/b/bucket/o/photos%2Fnot-a-storage-url.jpg/extra",
            "https://firebasestorage.googleapis.com/v0/b/bucket/o",
            "https://picsum.photos/200/200",
        ]

        for value in strangers {
            let url = URL(string: value)!
            #expect(
                !ClosedLegacyMediaPath.addressesClosedRootObject(url),
                "Expected \(value) to stay deletable."
            )
        }
    }

    @Test
    func partitionsMediaByReachability() {
        let legacy = Photo(url: Self.downloadURL(objectPath: "photos/legacy.jpg"))
        let owned = Photo(url: Self.downloadURL(objectPath: "users/uid-1/photos/owned.jpg"))

        let (unreachable, deletable) = [legacy, owned].partitionedByClosedLegacyPath()

        #expect(unreachable.map(\.url) == [legacy.url])
        #expect(deletable.map(\.url) == [owned.url])
    }
}

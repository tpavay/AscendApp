import Foundation
import Testing
@testable import AscendApp

/// Pins `DisplayNamePolicy` to the same vector the Cloud Functions validator,
/// the seeding contract module, and `firestore.rules` assert against.
///
/// Swift is the copy with the drift history: allowlisting the okina once let it
/// accept an anonymous-climber sentinel that all three other layers rejected,
/// and the Firestore write was denied with an opaque permissions error.
struct DisplayNameScreeningParityTests {
    private struct ScreeningVector: Decodable {
        let allowed: [String]
        let rejected: [String]
    }

    @Test
    func displayNameScreeningMatchesTheSharedVector() throws {
        let vector = try Self.sharedScreeningVector()

        #expect(!vector.allowed.isEmpty)
        #expect(!vector.rejected.isEmpty)

        for name in vector.allowed {
            #expect(
                DisplayNamePolicy.isAllowed(name),
                "shared vector allows \(name.debugDescription) but Swift rejected it"
            )
        }

        for name in vector.rejected {
            #expect(
                !DisplayNamePolicy.isAllowed(name),
                "shared vector rejects \(name.debugDescription) but Swift allowed it"
            )
        }
    }

    private static func sharedScreeningVector() throws -> ScreeningVector {
        let repoRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let vectorURL = repoRoot.appending(
            path: "SharedTestVectors/display-name-screening-vector.json"
        )
        let data = try Data(contentsOf: vectorURL)
        return try JSONDecoder().decode(ScreeningVector.self, from: data)
    }
}

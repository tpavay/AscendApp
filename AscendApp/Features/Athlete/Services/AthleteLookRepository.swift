import Foundation
@preconcurrency import FirebaseFirestore

/// Where a climber's athlete look is kept: one document, `users/{uid}/athlete_look/current`,
/// written only by its owner and read by the climbers whose stairs it runs on.
protocol AthleteLookRepository: Sendable {
    /// The look `userId` saved, or nil when they never saved one.
    func fetchLook(userId: String) async throws -> AthleteLook?
    func saveLook(_ look: AthleteLook, userId: String) async throws
}

final class FirestoreAthleteLookRepository: AthleteLookRepository, Sendable {
    static let shared = FirestoreAthleteLookRepository()

    /// Bump when the stored shape changes; `firestore.rules` accepts a range, never one number.
    /// 2 added the optional unlocked items: `carry`, `head` and `costume`.
    static let schemaVersion = 2

    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func fetchLook(userId: String) async throws -> AthleteLook? {
        let snapshot = try await document(userId: userId).getDocument()
        return snapshot.data().flatMap(Self.look(from:))
    }

    func saveLook(_ look: AthleteLook, userId: String) async throws {
        try await document(userId: userId).setData(Self.payload(for: look))
    }

    static func payload(for look: AthleteLook) -> [String: Any] {
        var payload: [String: Any] = [
            "schemaVersion": schemaVersion,
            "body": look.body.rawValue,
            "skinTone": look.skinTone.rawValue,
            "hairStyle": look.hairStyle.rawValue,
            "hairColor": look.hairColor.rawValue,
            "top": look.top.rawValue,
            "bottom": look.bottom.rawValue,
            "shoes": look.shoes.rawValue,
            "size": look.size.rawValue,
            "muscle": look.muscle.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        for slot in AthleteGear.Slot.allCases {
            if let item = look.wearing(slot) {
                payload[slot.rawValue] = item.rawValue
            }
        }
        return payload
    }

    /// A stored look, or nil when any field is missing or is an option this build does not
    /// offer - a newer build's choice is drawn as a stand-in rather than guessed at. Unlocked items
    /// are the exception: one this build does not know, or one stored in the wrong slot, is simply
    /// not drawn, and the rest of the look still is.
    static func look(from data: [String: Any]) -> AthleteLook? {
        func option<Option: RawRepresentable>(_ key: String) -> Option? where Option.RawValue == String {
            (data[key] as? String).flatMap(Option.init(rawValue:))
        }
        func item(in slot: AthleteGear.Slot) -> AthleteGear? {
            (data[slot.rawValue] as? String).flatMap(AthleteGear.init(rawValue:)).flatMap { $0.slot == slot ? $0 : nil }
        }
        guard let body: AthleteLook.Body = option("body"),
              let skinTone: AthleteLook.SkinTone = option("skinTone"),
              let hairStyle: AthleteLook.HairStyle = option("hairStyle"),
              let hairColor: AthleteLook.HairColor = option("hairColor"),
              let top: AthleteLook.KitColor = option("top"),
              let bottom: AthleteLook.KitColor = option("bottom"),
              let shoes: AthleteLook.KitColor = option("shoes"),
              let size: AthleteLook.Size = option("size"),
              let muscle: AthleteLook.Muscle = option("muscle") else { return nil }
        return AthleteLook(
            body: body,
            skinTone: skinTone,
            hairStyle: hairStyle,
            hairColor: hairColor,
            top: top,
            bottom: bottom,
            shoes: shoes,
            size: size,
            muscle: muscle,
            carry: item(in: .carry),
            head: item(in: .head),
            costume: item(in: .costume)
        )
    }

    private func document(userId: String) -> DocumentReference {
        db.collection("users").document(userId).collection("athlete_look").document("current")
    }
}

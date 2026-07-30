//
//  UserDataRepository.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/24/25.
//

import Foundation
@preconcurrency import FirebaseFirestore

struct UserDisplayNameData: Sendable {
    let firstName: String?
    let lastName: String?
    let displayName: String?
    let profilePictureURL: String?
    let age: Int?
    let gender: String?
    let weightKg: Double?
    let heightCm: Double?
    let locationCity: String?
    let locationCountry: String?
    let locationRegion: String?
    let onboardingFirstClimbId: String?
    let joinedAt: Date?

    init(_ data: [String: Any]?) {
        self.firstName = data?["firstName"] as? String
        self.lastName = data?["lastName"] as? String
        self.displayName = data?["displayName"] as? String
        self.profilePictureURL = data?["profilePictureURL"] as? String
        if let age = data?["age"] as? Int {
            self.age = age
        } else if let age = data?["age"] as? NSNumber {
            self.age = age.intValue
        } else {
            self.age = nil
        }
        self.gender = data?["gender"] as? String
        if let weightKg = data?["weight_kg"] as? Double {
            self.weightKg = weightKg
        } else if let weightKg = data?["weight_kg"] as? NSNumber {
            self.weightKg = weightKg.doubleValue
        } else {
            self.weightKg = nil
        }
        if let heightCm = data?["height_cm"] as? Double {
            self.heightCm = heightCm
        } else if let heightCm = data?["height_cm"] as? NSNumber {
            self.heightCm = heightCm.doubleValue
        } else {
            self.heightCm = nil
        }
        self.locationCountry = data?["location_country"] as? String
        self.locationCity = data?["location_city"] as? String
        self.locationRegion = data?["location_region"] as? String
        self.onboardingFirstClimbId = data?["onboarding_first_climb_id"] as? String
        if let joinedAt = data?["joined_at"] as? Timestamp {
            self.joinedAt = joinedAt.dateValue()
        } else if let joinedAt = data?["joined_at"] as? Date {
            self.joinedAt = joinedAt
        } else {
            self.joinedAt = nil
        }
    }
}

final class UserDataRepository: Sendable {

    static let shared = UserDataRepository()
    let db = Firestore.firestore()

    private init() {}

    func cacheDisplayName(_ displayName: String) {
        UserDefaults.standard.set(displayName, forKey: "displayName")
        UserDefaults.standard.synchronize()
    }
    
    func getCachedDisplayName() -> String? {
        return UserDefaults.standard.string(forKey: "displayName")
    }
    
    func cacheProfilePictureURL(_ urlString: String) {
        UserDefaults.standard.set(urlString, forKey: "profilePictureURL")
        UserDefaults.standard.synchronize()
    }
    
    func getCachedProfilePictureURL() -> String? {
        return UserDefaults.standard.string(forKey: "profilePictureURL")
    }
    
    func clearUserCache() {
        UserDefaults.standard.removeObject(forKey: "displayName")
        UserDefaults.standard.removeObject(forKey: "profilePictureURL")
        UserDefaults.standard.synchronize()
    }
    
    func getUserFromFirestore(userId: String) async throws -> UserDisplayNameData {
        let document = try await db.collection("users").document(userId).getDocument()

        let userDisplayNameData = UserDisplayNameData(document.data())
        return userDisplayNameData
    }
    
    func getDisplayName(userId: String) async -> String? {
        do {
            let userData = try await getUserFromFirestore(userId: userId)
            let displayName = userData.displayName ?? ""
            if !displayName.isEmpty {
                cacheDisplayName(displayName)
                return displayName
            }
        } catch {
            debugLog("Error fetching user from Firestore: \(error)")
            TelemetryManager.shared.recordError(error, context: .firestore, code: "user_fetch_failed")
        }

        return getCachedDisplayName()
    }
    
    func hasUserName(userId: String) async -> Bool {
        guard let displayName = await getDisplayName(userId: userId) else { return false }
        return !displayName.isEmpty
    }
    
    func saveUserToFirestore(
        userId: String,
        email: String?,
        firstName: String?,
        lastName: String?,
        displayName: String?,
        profilePictureURL: String? = nil,
        age: Int? = nil,
        gender: String? = nil,
        weightKg: Double? = nil,
        heightCm: Double? = nil,
        locationCity: String? = nil,
        locationCountry: String? = nil,
        locationRegion: String? = nil,
        onboardingFirstClimbId: String? = nil,
        joinedAt: Date? = nil
    ) async throws {
        let validatedDisplayName = try displayName.map(DisplayNamePolicy.validated)
        let userRef = db.collection("users").document(userId)
        
        // Check if user already exists
        let document = try await userRef.getDocument()
        let userExists = document.exists
        
        if userExists {
            var newData: [String: Any] = [:]

            if let email {
                newData["email"] = email
            }

            if let firstName {
                newData["firstName"] = firstName
            }

            if let lastName {
                newData["lastName"] = lastName
            }

            if let validatedDisplayName {
                newData["displayName"] = validatedDisplayName
            }

            if let profilePictureURL {
                newData["profilePictureURL"] = profilePictureURL
            }

            if let age {
                newData["age"] = age
            }

            if let gender {
                newData["gender"] = gender
            }

            if let weightKg {
                newData["weight_kg"] = weightKg
            }

            if let heightCm {
                newData["height_cm"] = heightCm
            }

            if let locationCity {
                newData["location_city"] = locationCity
            }

            if let locationCountry {
                newData["location_country"] = locationCountry
            }

            if let locationRegion {
                newData["location_region"] = locationRegion
            }

            if let onboardingFirstClimbId {
                newData["onboarding_first_climb_id"] = onboardingFirstClimbId
            }

            if let joinedAt {
                newData["joined_at"] = Timestamp(date: joinedAt)
            }

            // Compare with existing data and only update changed fields
            let existingData = document.data() ?? [:]
            var changedData: [String: Any] = [:]
            
            for (key, newValue) in newData {
                if let newStringValue = newValue as? String {
                    let existingValue = existingData[key] as? String ?? ""
                    if newStringValue != existingValue {
                        changedData[key] = newValue
                    }
                } else if let newIntValue = newValue as? Int {
                    let existingValue = (existingData[key] as? Int) ?? (existingData[key] as? NSNumber)?.intValue
                    if existingValue != newIntValue {
                        changedData[key] = newValue
                    }
                } else if let newDoubleValue = newValue as? Double {
                    let existingValue = (existingData[key] as? Double) ?? (existingData[key] as? NSNumber)?.doubleValue
                    if existingValue != newDoubleValue {
                        changedData[key] = newValue
                    }
                } else if let newTimestampValue = newValue as? Timestamp {
                    let existingValue = existingData[key] as? Timestamp
                    if existingValue?.dateValue() != newTimestampValue.dateValue() {
                        changedData[key] = newValue
                    }
                }
            }
            
            // Only update if data actually changed
            if !changedData.isEmpty {
                changedData["lastUpdated"] = FieldValue.serverTimestamp()
                try await userRef.setData(changedData, merge: true)
            }
        } else {
            // New user - create with all data plus timestamps
            var userData: [String: Any] = [
                "email": email ?? "",
                "firstName": firstName ?? "",
                "lastName": lastName ?? "",
                "displayName": validatedDisplayName ?? ""
            ]

            if let profilePictureURL {
                userData["profilePictureURL"] = profilePictureURL
            }

            if let age {
                userData["age"] = age
            }

            if let gender {
                userData["gender"] = gender
            }

            if let weightKg {
                userData["weight_kg"] = weightKg
            }

            if let heightCm {
                userData["height_cm"] = heightCm
            }

            if let locationCity {
                userData["location_city"] = locationCity
            }

            if let locationCountry {
                userData["location_country"] = locationCountry
            }

            if let locationRegion {
                userData["location_region"] = locationRegion
            }

            if let onboardingFirstClimbId {
                userData["onboarding_first_climb_id"] = onboardingFirstClimbId
            }

            userData["createdAt"] = FieldValue.serverTimestamp()
            userData["joined_at"] = joinedAt.map(Timestamp.init(date:)) ?? FieldValue.serverTimestamp()
            userData["lastUpdated"] = FieldValue.serverTimestamp()
            try await userRef.setData(userData, merge: true)
        }
    }
    
    func updateProfilePictureURL(userId: String, profilePictureURL: String) async throws {
        try await updateUserAndPublicProfile(
            userId: userId,
            email: nil,
            userFields: ["profilePictureURL": profilePictureURL],
            alwaysPublish: true
        )
        
        cacheProfilePictureURL(profilePictureURL)
    }
    
    func getProfilePictureURL(userId: String) async -> String? {
        do {
            let userData = try await getUserFromFirestore(userId: userId)
            if let profilePictureURL = userData.profilePictureURL, !profilePictureURL.isEmpty {
                cacheProfilePictureURL(profilePictureURL)
                return profilePictureURL
            }
        } catch {
            debugLog("Error fetching profile picture URL from Firestore: \(error)")
            TelemetryManager.shared.recordError(error, context: .firestore, code: "profile_picture_fetch_failed")
        }

        return getCachedProfilePictureURL()
    }
    
    func updateDisplayName(userId: String, email: String? = nil, displayName: String) async throws {
        let displayName = try DisplayNamePolicy.validated(displayName)
        try await updateUserAndPublicProfile(
            userId: userId,
            email: email,
            userFields: ["displayName": displayName],
            alwaysPublish: true
        )

        cacheDisplayName(displayName)
    }

    func updateOnboardingProfile(
        userId: String,
        email: String? = nil,
        displayName: String,
        age: Int,
        gender: ProfileGender
    ) async throws {
        let displayName = try DisplayNamePolicy.validated(displayName)
        try await updateUserAndPublicProfile(
            userId: userId,
            email: email,
            userFields: [
                "displayName": displayName,
                "age": age,
                "gender": gender.rawValue
            ],
            alwaysPublish: true
        )
        cacheDisplayName(displayName)
    }

    func updateOnboardingDemographics(
        userId: String,
        email: String? = nil,
        displayName: String? = nil,
        age: Int? = nil,
        gender: ProfileGender? = nil,
        weightKg: Double? = nil,
        heightCm: Double? = nil,
        locationCity: String? = nil,
        locationCountry: String? = nil,
        locationRegion: String? = nil
    ) async throws {
        let displayName = try displayName.map(DisplayNamePolicy.validated)
        var userFields: [String: Any] = [:]

        if let displayName {
            userFields["displayName"] = displayName
        }
        if let age {
            userFields["age"] = age
        }
        if let gender {
            userFields["gender"] = gender.rawValue
        }
        if let weightKg {
            userFields["weight_kg"] = weightKg
        }
        if let heightCm {
            userFields["height_cm"] = heightCm
        }
        if let locationCity {
            userFields["location_city"] = locationCity
        }
        if let locationCountry {
            userFields["location_country"] = locationCountry.uppercased()
        }
        if let locationRegion {
            userFields["location_region"] = locationRegion
        }

        try await updateUserAndPublicProfile(
            userId: userId,
            email: email,
            userFields: userFields,
            alwaysPublish: false
        )

        if let displayName {
            cacheDisplayName(displayName)
        }
    }

    func updateOnboardingFirstClimb(
        userId: String,
        email: String? = nil,
        climbId: String
    ) async throws {
        let userRef = db.collection("users").document(userId)
        let document = try await userRef.getDocument()

        if document.exists {
            try await userRef.setData([
                "onboarding_first_climb_id": climbId,
                "lastUpdated": FieldValue.serverTimestamp()
            ], merge: true)
        } else {
            try await saveUserToFirestore(
                userId: userId,
                email: email,
                firstName: nil,
                lastName: nil,
                displayName: nil,
                onboardingFirstClimbId: climbId
            )
        }
    }

    private func updateUserAndPublicProfile(
        userId: String,
        email: String?,
        userFields: [String: Any],
        alwaysPublish: Bool
    ) async throws {
        // The private record and the public mirror have to move together, and a
        // transaction cannot queue offline the way a cached write does, so the
        // caller gets an honest answer instead of a half-applied profile.
        try await ProfilePublicationError.requireConnection()

        let userRef = db.collection("users").document(userId)
        let publicProfileRef = userRef.collection("public_profile").document("current")

        do {
            _ = try await db.runTransaction { transaction, errorPointer -> Any? in
                do {
                    let userSnapshot = try transaction.getDocument(userRef)
                    let publicProfileSnapshot = try transaction.getDocument(publicProfileRef)
                    var mergedUserData = userSnapshot.data() ?? [:]
                    var userWrite = userFields

                    if !userSnapshot.exists {
                        let initialUserData: [String: Any] = [
                            "email": email ?? "",
                            "firstName": "",
                            "lastName": "",
                            "displayName": ""
                        ]
                        mergedUserData.merge(initialUserData) { current, _ in current }
                        userWrite.merge(initialUserData) { current, _ in current }
                        userWrite["createdAt"] = FieldValue.serverTimestamp()
                    }

                    mergedUserData.merge(userFields) { _, new in new }
                    userWrite["lastUpdated"] = FieldValue.serverTimestamp()

                    let storedDisplayName = mergedUserData["displayName"] as? String
                    let hasAuthoredDisplayName = storedDisplayName?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty == false
                    let publicPayload: [String: Any]?
                    if alwaysPublish || hasAuthoredDisplayName {
                        let identity = try Self.publicIdentity(
                            userId: userId,
                            userData: mergedUserData
                        )
                        publicPayload = try ProfileRepository.publicIdentityPayload(
                            identity,
                            advancesIdentityVersion: try ProfileRepository
                                .publicIdentityNeedsVersionAdvance(
                                    identity,
                                    existingData: publicProfileSnapshot.data()
                                )
                            )
                    } else {
                        publicPayload = nil
                    }

                    transaction.setData(userWrite, forDocument: userRef, merge: true)
                    if let publicPayload {
                        transaction.setData(
                            publicPayload,
                            forDocument: publicProfileRef,
                            merge: true
                        )
                    }
                    return nil
                } catch let error as NSError {
                    errorPointer?.pointee = error
                    return nil
                }
            }
        } catch {
            // A connection that drops mid-transaction reads the same to the user
            // as never having had one.
            throw ProfilePublicationError.mappingLostConnection(error)
        }
    }

    private static func publicIdentity(
        userId: String,
        userData: [String: Any]
    ) throws -> ProfileUserIdentity {
        let storedProfile = UserDisplayNameData(userData)
        let publicIdentity = PublicClimberIdentity.resolve(
            userId: userId,
            storedDisplayName: storedProfile.displayName,
            storedPhotoURL: storedProfile.profilePictureURL.flatMap(URL.init(string:))
        )

        return ProfileUserIdentity(
            userId: userId,
            displayName: try DisplayNamePolicy.validated(publicIdentity.displayName),
            photoURL: publicIdentity.photoURL,
            age: storedProfile.age,
            gender: storedProfile.gender.flatMap(ProfileGender.init(rawValue:)),
            weightKg: storedProfile.weightKg,
            heightCm: storedProfile.heightCm,
            locationCity: storedProfile.locationCity,
            locationCountryCode: storedProfile.locationCountry,
            locationRegionCode: storedProfile.locationRegion,
            joinedAt: storedProfile.joinedAt
        )
    }

}

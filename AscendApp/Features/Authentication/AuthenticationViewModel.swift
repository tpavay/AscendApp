//
//  AuthenticationViewModel.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/10/25.
//

import Foundation
import FirebaseAuth
import FirebaseCore
import Observation
import PhotosUI
import SwiftUI

enum AuthenticationState {
    case authenticated
    case authenticatingWithApple
    case authenticatingWithGoogle
    case authenticatingWithInternalQA
    case unauthenticated

    /// Shown while restoring a session on app launch (waiting for profile fetch)
    case restoringSession

    var isAuthenticating: Bool {
        switch self {
        case .authenticatingWithApple, .authenticatingWithGoogle, .authenticatingWithInternalQA:
            return true
        case .authenticated, .unauthenticated, .restoringSession:
            return false
        }
    }
}



@MainActor
@Observable
class AuthenticationViewModel {
    var displayName: String = ""
    var user: User?
    var authenticationState: AuthenticationState = .unauthenticated
    var errorMessage: String?
    var isErrorAlertPresented: Bool = false
    var photoURL: URL?
    var customProfilePictureURL: URL?
    private(set) var lastUsedProvider: AuthProviderKind?
    private(set) var hasRemoteDisplayName: Bool = false

    /// Indicates whether the profile data has been loaded from Firestore/cache after auth restore.
    /// Used to avoid showing authenticated UI before profile state is known.
    private(set) var isProfileLoaded: Bool = false

    private var authenticationService = AuthenticationService()
    private let accountSessionStore = AccountSessionStore.shared
    private let monetizationIdentityManager: any MonetizationIdentityManaging

    init(
        monetizationIdentityManager: any MonetizationIdentityManaging = MonetizationManager.shared,
        observesFirebaseAuth: Bool = true
    ) {
        self.monetizationIdentityManager = monetizationIdentityManager
        lastUsedProvider = accountSessionStore.lastUsedProvider

        // Load cached display name immediately for UI responsiveness
        displayName = UserDataRepository.shared.getCachedDisplayName() ?? ""
        
        // Load cached profile picture URL
        if let cachedURLString = UserDataRepository.shared.getCachedProfilePictureURL() {
            customProfilePictureURL = URL(string: cachedURLString)
        }

        if observesFirebaseAuth, let currentUser = Auth.auth().currentUser {
            user = currentUser
            photoURL = currentUser.photoURL
            authenticationState = .restoringSession
        }

        if observesFirebaseAuth {
            registerAuthStateHandler()
        }
    }
    private var authStateHandle: AuthStateDidChangeListenerHandle?

    func registerAuthStateHandler() {
        if authStateHandle == nil {
            authStateHandle = Auth.auth().addStateDidChangeListener({ auth, user in
                self.user = user
                self.photoURL = user?.photoURL ?? URL(string: "")

                if let user = user {
                    // Set telemetry user ID and log session restored
                    TelemetryManager.shared.setUserId(user.uid)
                    TelemetryManager.shared.log(.authSessionRestored)

                    // Check if we're in an interactive sign-in flow (already showing progress)
                    let isInteractiveSignIn = self.authenticationState == .authenticatingWithGoogle ||
                                               self.authenticationState == .authenticatingWithApple ||
                                               self.authenticationState == .authenticatingWithInternalQA

                    // Load cached display name immediately
                    let cachedDisplayName = UserDataRepository.shared.getCachedDisplayName() ?? ""
                    self.displayName = cachedDisplayName
                    let shouldSaveInitialUserRecord = !isInteractiveSignIn || !cachedDisplayName.isEmpty

                    // If we have a cached name, we can show authenticated immediately
                    // Otherwise, show restoring session while we fetch from Firestore
                    let initialAuthenticationState: AuthenticationState
                    if !cachedDisplayName.isEmpty {
                        self.isProfileLoaded = true
                        initialAuthenticationState = .authenticated
                    } else if isInteractiveSignIn {
                        // Interactive sign-in: set authenticated immediately even without display name
                        initialAuthenticationState = .authenticated
                    } else {
                        // Cold launch without cached name: show restoring session
                        self.isProfileLoaded = false
                        initialAuthenticationState = .restoringSession
                    }
                    self.beginAuthenticatedSession(
                        userID: user.uid,
                        initialState: initialAuthenticationState
                    )

                    // Handle Firestore operations in background
                    Task {
                        // Avoid writing a provider-derived or empty display name during new sign-up.
                        // The post-auth name step creates the profile document with the user's chosen name.
                        if shouldSaveInitialUserRecord {
                            try? await self.saveUserToFirestore(user: user)
                        }

                        // Fetch the authoritative display name from Firestore
                        let firestoreDisplayName = await UserDataRepository.shared.getDisplayName(userId: user.uid)

                        // Fetch custom profile picture URL from Firestore
                        let profilePictureURLString = await UserDataRepository.shared.getProfilePictureURL(userId: user.uid)

                        await MainActor.run {
                            // Update display name if we got one from Firestore
                            if let firestoreDisplayName, !firestoreDisplayName.isEmpty {
                                self.displayName = firestoreDisplayName
                                self.hasRemoteDisplayName = true
                            } else {
                                self.hasRemoteDisplayName = false
                            }

                            // Update profile picture URL
                            if let profilePictureURLString {
                                self.customProfilePictureURL = URL(string: profilePictureURLString)
                            }

                            // Now that profile is loaded, evaluate the final auth state
                            self.isProfileLoaded = true
                            let finalState = self.getAuthenticationState()
                            self.authenticationState = finalState

                            // Log the outcome for debugging
                            TelemetryManager.shared.log(.authProfileLoaded)
                        }
                    }
                } else {
                    let monetizationTransition = self.monetizationIdentityManager.prepareIdentityReset()

                    // User signed out - reset all state
                    TelemetryManager.shared.log(.authSignOut)
                    TelemetryManager.shared.clearUserId()
                    Task {
                        await self.monetizationIdentityManager.resetIdentity(
                            transition: monetizationTransition
                        )
                    }

                    self.displayName = ""
                    self.customProfilePictureURL = nil
                    self.hasRemoteDisplayName = false
                    self.isProfileLoaded = false
                    self.authenticationState = .unauthenticated
                    UserDataRepository.shared.clearUserCache()
                }
            })
        }
    }

    /// Claims the new RevenueCat identity *before* publishing an authenticated state, so routing
    /// never evaluates access against the previous identity's stale answer. The entitlement state
    /// is `.unknown` the moment the app is authenticated, which routes to a wait, not the paywall.
    func beginAuthenticatedSession(
        userID: String,
        initialState: AuthenticationState
    ) {
        let monetizationTransition = monetizationIdentityManager.prepareIdentity(
            userId: userID
        )
        Task {
            await monetizationIdentityManager.identify(
                userId: userID,
                transition: monetizationTransition
            )
        }
        authenticationState = initialState
    }
}

@MainActor
extension AuthenticationViewModel {
    func signOut() {
        Task { @MainActor in
            await PushNotificationService.shared.unregisterCurrentDevice()

            do {
                try authenticationService.signOut()
                errorMessage = nil
            }
            catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func signInWithGoogle() async {
        authenticationState = .authenticatingWithGoogle
        errorMessage = nil
        TelemetryManager.shared.track(
            OnboardingAnalyticsEvent.authStarted(provider: AuthProviderKind.google.rawValue)
        )

        do {
            _ = try await authenticationService.signInWithGoogle()
            recordSuccessfulSignIn(provider: .google)
            TelemetryManager.shared.track(
                OnboardingAnalyticsEvent.authCompleted(provider: AuthProviderKind.google.rawValue)
            )
            TelemetryManager.shared.log(.authInteractiveSignInSuccess)
        } catch {
            // Don't show error for user cancellation
            if error is CancellationError {
                TelemetryManager.shared.track(
                    OnboardingAnalyticsEvent.authFailed(
                        provider: AuthProviderKind.google.rawValue,
                        reason: "cancelled"
                    )
                )
                // User canceled - just reset state without showing error
                authenticationState = .unauthenticated
            } else {
                TelemetryManager.shared.track(
                    OnboardingAnalyticsEvent.authFailed(
                        provider: AuthProviderKind.google.rawValue,
                        reason: "failed"
                    )
                )
                TelemetryManager.shared.log(.authSignInFailed)
                TelemetryManager.shared.recordError(error, context: .auth, code: "google_sign_in_failed", additionalInfo: ["provider": "google"])
                errorMessage = error.localizedDescription
                authenticationState = .unauthenticated
            }
        }
    }

    func signInWithInternalQA(email: String, password: String) async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        guard InternalQASignInAvailability.isEnabled(projectID: FirebaseApp.app()?.options.projectID) else {
            errorMessage = "Internal QA sign-in is unavailable in this build."
            authenticationState = .unauthenticated
            return
        }

        guard !trimmedEmail.isEmpty else {
            errorMessage = "Enter the internal QA email address."
            authenticationState = .unauthenticated
            return
        }

        guard !password.isEmpty else {
            errorMessage = "Enter the internal QA password."
            authenticationState = .unauthenticated
            return
        }

        authenticationState = .authenticatingWithInternalQA
        errorMessage = nil
        TelemetryManager.shared.track(
            OnboardingAnalyticsEvent.authStarted(provider: AuthProviderKind.internalQA.rawValue)
        )

        do {
            _ = try await authenticationService.signInWithEmail(email: trimmedEmail, password: password)
            recordSuccessfulSignIn(provider: .internalQA)
            TelemetryManager.shared.track(
                OnboardingAnalyticsEvent.authCompleted(provider: AuthProviderKind.internalQA.rawValue)
            )
            TelemetryManager.shared.log(.authInteractiveSignInSuccess)
        } catch {
            TelemetryManager.shared.track(
                OnboardingAnalyticsEvent.authFailed(
                    provider: AuthProviderKind.internalQA.rawValue,
                    reason: "failed"
                )
            )
            TelemetryManager.shared.log(.authSignInFailed)
            TelemetryManager.shared.recordError(
                error,
                context: .auth,
                code: "internal_qa_sign_in_failed",
                additionalInfo: ["provider": "internal_qa"]
            )
            errorMessage = error.localizedDescription
            authenticationState = .unauthenticated
        }
    }
    
    func signInWithApple() async {
        authenticationState = .authenticatingWithApple
        errorMessage = nil
        TelemetryManager.shared.track(
            OnboardingAnalyticsEvent.authStarted(provider: AuthProviderKind.apple.rawValue)
        )

        do {
            _ = try await authenticationService.signInWithApple()
            recordSuccessfulSignIn(provider: .apple)
            TelemetryManager.shared.track(
                OnboardingAnalyticsEvent.authCompleted(provider: AuthProviderKind.apple.rawValue)
            )
            TelemetryManager.shared.log(.authInteractiveSignInSuccess)
        } catch {
            // Don't show error for user cancellation
            if error is CancellationError {
                TelemetryManager.shared.track(
                    OnboardingAnalyticsEvent.authFailed(
                        provider: AuthProviderKind.apple.rawValue,
                        reason: "cancelled"
                    )
                )
                // User canceled - just reset state without showing error
                authenticationState = .unauthenticated
            } else {
                TelemetryManager.shared.track(
                    OnboardingAnalyticsEvent.authFailed(
                        provider: AuthProviderKind.apple.rawValue,
                        reason: "failed"
                    )
                )
                TelemetryManager.shared.log(.authSignInFailed)
                TelemetryManager.shared.recordError(error, context: .auth, code: "apple_sign_in_failed", additionalInfo: ["provider": "apple"])
                errorMessage = error.localizedDescription
                authenticationState = .unauthenticated
            }
        }
    }

    func setDisplayName(firstName: String, lastName: String) async {
        do {
            let fullDisplayName = "\(firstName) \(lastName)"
            let validatedDisplayName = try DisplayNamePolicy.validated(
                fullDisplayName
            )
            try await authenticationService.updateUserDisplayName(
                displayName: validatedDisplayName
            )
            displayName = validatedDisplayName
            
            // Cache display name for immediate UI updates
            UserDataRepository.shared.cacheDisplayName(validatedDisplayName)
            
            // Save updated user info to Firestore with individual names
            if let user = user {
                try await UserDataRepository.shared.saveUserToFirestore(
                    userId: user.uid,
                    email: user.email,
                    firstName: firstName,
                    lastName: lastName,
                    displayName: validatedDisplayName
                )
                hasRemoteDisplayName = true
            }
            
            authenticationState = .authenticated
        } catch {
            errorMessage = error.localizedDescription
            isErrorAlertPresented = true
        }
    }

    private func getAuthenticationState() -> AuthenticationState {
        if user == nil {
            return .unauthenticated
        }

        return .authenticated
    }

    private func recordSuccessfulSignIn(provider: AuthProviderKind) {
        accountSessionStore.recordSuccessfulSignIn(provider: provider)
        lastUsedProvider = provider
    }
    
    private func saveUserToFirestore(user: User) async throws {
        let existingData = try? await UserDataRepository.shared.getUserFromFirestore(userId: user.uid)
        
        try await UserDataRepository.shared.saveUserToFirestore(
            userId: user.uid,
            email: user.email,
            firstName: existingData?.firstName,
            lastName: existingData?.lastName,
            displayName: existingData?.displayName,
            age: existingData?.legacyAge,
            birthday: existingData?.birthday,
            gender: existingData?.gender,
            weightKg: existingData?.weightKg,
            heightCm: existingData?.heightCm,
            locationCity: existingData?.locationCity,
            locationCountry: existingData?.locationCountry,
            locationRegion: existingData?.locationRegion,
            onboardingFirstClimbId: existingData?.onboardingFirstClimbId,
            joinedAt: existingData?.joinedAt ?? user.metadata.creationDate
        )
    }
    
    func updateProfilePicture(photoPickerItem: PhotosPickerItem) async {
        errorMessage = nil
        
        guard let user = user else {
            errorMessage = "User not authenticated"
            return
        }

        do {
            try ProfilePublicationError.requireConnection()

            guard let imageData = try await photoPickerItem.loadTransferable(type: Data.self) else {
                errorMessage = "Failed to upload photo"
                return
            }

            let filename = "users/\(user.uid)/profile_pictures/\(UUID().uuidString).jpg"
            let photoRepo = FirebasePhotoRepository()
            let uploadedURL = try await photoRepo.upload(imageData, filename: filename)

            try await UserDataRepository.shared.updateProfilePictureURL(
                userId: user.uid,
                profilePictureURL: uploadedURL.absoluteString
            )
            
            // Update the local state
            customProfilePictureURL = uploadedURL

        } catch {
            errorMessage = profileUpdateFailureMessage(
                error,
                fallback: "Failed to update profile picture"
            )
        }
    }
    
    func updateProfilePictureWithData(imageData: Data) async {
        errorMessage = nil
        
        guard let user = user else {
            errorMessage = "User not authenticated"
            return
        }
        
        do {
            try ProfilePublicationError.requireConnection()

            // Upload the photo data directly
            let filename = "users/\(user.uid)/profile_pictures/\(UUID().uuidString).jpg"
            let photoRepo = FirebasePhotoRepository()
            let uploadedURL = try await photoRepo.upload(imageData, filename: filename)
            
            // Save the URL to Firestore user document
            try await UserDataRepository.shared.updateProfilePictureURL(
                userId: user.uid,
                profilePictureURL: uploadedURL.absoluteString
            )
            
            // Update the local state
            customProfilePictureURL = uploadedURL

        } catch {
            errorMessage = profileUpdateFailureMessage(
                error,
                fallback: "Failed to update profile picture"
            )
        }
    }
    
    private func profileUpdateFailureMessage(
        _ error: Error,
        fallback: String
    ) -> String {
        if let publicationError = error as? ProfilePublicationError {
            return publicationError.errorDescription ?? fallback
        }
        return "\(fallback): \(error.localizedDescription)"
    }

    /// Runs a profile mutation and hands its failure back to the caller instead
    /// of leaving it on `errorMessage`.
    ///
    /// `errorMessage` is app-wide: the Settings root renders it inline, so a
    /// message a pushed editor left behind follows the climber back out and
    /// sits there under an unrelated screen.
    func scopedProfileUpdate(
        fallback: String,
        _ update: () async -> Bool
    ) async -> String? {
        errorMessage = nil
        let didSucceed = await update()
        let failure = errorMessage
        errorMessage = nil
        return didSucceed ? nil : (failure ?? fallback)
    }

    var displayPhotoURL: URL? {
        // Prioritize custom profile picture, then fall back to OAuth provider photo
        return customProfilePictureURL ?? photoURL
    }
    
    @discardableResult
    func updateDisplayName(_ newDisplayName: String) async -> Bool {
        errorMessage = nil
        
        guard let user = user else {
            errorMessage = "User not authenticated"
            return false
        }
        
        let previousDisplayName = displayName

        do {
            let validatedDisplayName = try DisplayNamePolicy.validated(
                newDisplayName
            )

            // Update local state immediately for responsive UI
            displayName = validatedDisplayName

            try await authenticationService.updateUserDisplayName(
                displayName: validatedDisplayName
            )
            
            // Save to Firestore user document
            try await UserDataRepository.shared.updateDisplayName(
                userId: user.uid,
                email: user.email,
                displayName: validatedDisplayName
            )
            hasRemoteDisplayName = true

            return true
            
        } catch {
            displayName = previousDisplayName
            errorMessage = profileUpdateFailureMessage(
                error,
                fallback: "Failed to update display name"
            )
            return false
        }
    }

    @discardableResult
    func updateProfileName(firstName: String, lastName: String) async -> Bool {
        errorMessage = nil

        guard let user else {
            errorMessage = "User not authenticated"
            return false
        }

        let normalizedFirstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousDisplayName = displayName

        do {
            let composedDisplayName = try DisplayNamePolicy.composedBoardName(
                firstName: normalizedFirstName,
                lastName: normalizedLastName
            )
            displayName = composedDisplayName

            try await authenticationService.updateUserDisplayName(
                displayName: composedDisplayName
            )
            try await UserDataRepository.shared.updateProfileName(
                userId: user.uid,
                email: user.email,
                firstName: normalizedFirstName,
                lastName: normalizedLastName
            )
            hasRemoteDisplayName = true
            return true
        } catch {
            displayName = previousDisplayName
            errorMessage = profileUpdateFailureMessage(
                error,
                fallback: "Failed to update name"
            )
            return false
        }
    }

    @discardableResult
    func updateOnboardingProfile(
        displayName newDisplayName: String,
        birthday: ProfileBirthday,
        gender: ProfileGender
    ) async -> Bool {
        errorMessage = nil

        guard let user else {
            errorMessage = "User not authenticated"
            return false
        }

        guard birthday.hasValidProfileAge() else {
            errorMessage = "Choose a birthday for an age from 13 to 120"
            return false
        }

        let previousDisplayName = displayName

        do {
            let validatedDisplayName = try DisplayNamePolicy.validated(
                newDisplayName
            )
            displayName = validatedDisplayName

            try await authenticationService.updateUserDisplayName(
                displayName: validatedDisplayName
            )

            try await UserDataRepository.shared.updateOnboardingProfile(
                userId: user.uid,
                email: user.email,
                displayName: validatedDisplayName,
                birthday: birthday,
                gender: gender
            )
            hasRemoteDisplayName = true

            return true
        } catch {
            displayName = previousDisplayName
            errorMessage = profileUpdateFailureMessage(
                error,
                fallback: "Failed to update profile"
            )
            return false
        }
    }

    @discardableResult
    func updateOnboardingGender(_ gender: ProfileGender) async -> Bool {
        errorMessage = nil

        guard let user else {
            errorMessage = "User not authenticated"
            return false
        }

        do {
            try await UserDataRepository.shared.updateOnboardingDemographics(
                userId: user.uid,
                email: user.email,
                displayName: displayName,
                gender: gender
            )
            return true
        } catch {
            errorMessage = "Failed to update profile: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func updateOnboardingBirthday(_ birthday: ProfileBirthday) async -> Bool {
        errorMessage = nil

        guard let user else {
            errorMessage = "User not authenticated"
            return false
        }

        guard birthday.hasValidProfileAge() else {
            errorMessage = "Choose a birthday for an age from 13 to 120"
            return false
        }

        do {
            try await UserDataRepository.shared.updateOnboardingDemographics(
                userId: user.uid,
                email: user.email,
                displayName: displayName,
                birthday: birthday
            )
            return true
        } catch {
            errorMessage = "Failed to update profile: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func updateBirthday(_ birthday: ProfileBirthday) async -> Bool {
        errorMessage = nil

        guard let user else {
            errorMessage = "User not authenticated"
            return false
        }

        guard birthday.hasValidProfileAge() else {
            errorMessage = "Choose a birthday for an age from 13 to 120"
            return false
        }

        do {
            try await UserDataRepository.shared.updateBirthday(
                userId: user.uid,
                email: user.email,
                birthday: birthday
            )
            return true
        } catch {
            errorMessage = profileUpdateFailureMessage(
                error,
                fallback: "Failed to update birthday"
            )
            return false
        }
    }

    @discardableResult
    func updateOnboardingWeightKilograms(_ weightKg: Double) async -> Bool {
        errorMessage = nil

        guard let user else {
            errorMessage = "User not authenticated"
            return false
        }

        guard weightKg > 0, weightKg <= 400 else {
            errorMessage = "Enter a valid body weight"
            return false
        }

        do {
            try await UserDataRepository.shared.updateOnboardingDemographics(
                userId: user.uid,
                email: user.email,
                displayName: displayName,
                weightKg: weightKg
            )
            return true
        } catch {
            errorMessage = "Failed to update profile: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func updateOnboardingBodyMetrics(weightKg: Double, heightCm: Double) async -> Bool {
        errorMessage = nil

        guard let user else {
            errorMessage = "User not authenticated"
            return false
        }

        guard weightKg > 0, weightKg <= 400 else {
            errorMessage = "Enter a valid body weight"
            return false
        }

        guard heightCm >= 90, heightCm <= 240 else {
            errorMessage = "Enter a valid height"
            return false
        }

        do {
            try await UserDataRepository.shared.updateOnboardingDemographics(
                userId: user.uid,
                email: user.email,
                displayName: displayName,
                weightKg: weightKg,
                heightCm: heightCm
            )
            return true
        } catch {
            errorMessage = "Failed to update profile: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func updateOnboardingLocation(city: String, countryCode: String, region: String?) async -> Bool {
        errorMessage = nil

        guard let user else {
            errorMessage = "User not authenticated"
            return false
        }

        let normalizedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCountry = countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let normalizedRegion = region?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedCity.isEmpty, normalizedCity.count <= 120 else {
            errorMessage = "Choose a valid city"
            return false
        }

        guard normalizedCountry.range(of: #"^[A-Z]{2}$"#, options: .regularExpression) != nil else {
            errorMessage = "Choose a valid country"
            return false
        }

        guard normalizedRegion?.count ?? 0 <= 120 else {
            errorMessage = "Choose a valid region"
            return false
        }

        do {
            try await UserDataRepository.shared.updateOnboardingDemographics(
                userId: user.uid,
                email: user.email,
                displayName: displayName,
                locationCity: normalizedCity,
                locationCountry: normalizedCountry,
                locationRegion: normalizedRegion?.isEmpty == true ? nil : normalizedRegion
            )
            return true
        } catch {
            errorMessage = "Failed to update profile: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func updateOnboardingFirstClimb(_ climbId: String) async -> Bool {
        errorMessage = nil

        guard let user else {
            errorMessage = "User not authenticated"
            return false
        }

        let normalizedClimbId = climbId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedClimbId.range(of: #"^[a-z0-9-]{1,160}$"#, options: .regularExpression) != nil else {
            errorMessage = "Choose a valid first climb"
            return false
        }

        do {
            try await UserDataRepository.shared.updateOnboardingFirstClimb(
                userId: user.uid,
                email: user.email,
                climbId: normalizedClimbId
            )
            return true
        } catch {
            errorMessage = "Failed to update first climb: \(error.localizedDescription)"
            return false
        }
    }
}

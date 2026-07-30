//
//  AuthenticationViewModel.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/10/25.
//

import Foundation
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
    var user: AuthenticatedUser?
    var authenticationState: AuthenticationState = .unauthenticated
    var errorMessage: String?
    var isErrorAlertPresented: Bool = false
    var photoURL: URL?
    var customProfilePictureURL: URL?
    private(set) var lastUsedProvider: AuthProviderKind?
    private(set) var hasRemoteDisplayName: Bool = false
    private(set) var authenticatedUserID: String?

    /// Indicates whether the profile data has been loaded from Firestore/cache after auth restore.
    /// Used to avoid showing authenticated UI before profile state is known.
    private(set) var isProfileLoaded: Bool = false

    private let authenticationClient: any AuthenticationClient
    private let authenticationStateObserver: any AuthenticationStateObserving
    private let profileSessionProvider: any AuthenticationProfileSessionProviding
    private let accountSessionStore: AccountSessionStore
    private let monetizationIdentityManager: any MonetizationIdentityManaging
    private let pushNotificationManager: any AuthenticatedPushNotificationManaging
    private var authStateObservation: AuthenticationStateObservation?

    init(
        monetizationIdentityManager: any MonetizationIdentityManaging = MonetizationManager.shared,
        authenticationClient: any AuthenticationClient = LiveAuthenticationClient(),
        authenticationStateObserver: any AuthenticationStateObserving = FirebaseAuthenticationStateObserver(),
        profileSessionProvider: any AuthenticationProfileSessionProviding = LiveAuthenticationProfileSessionProvider(),
        accountSessionStore: AccountSessionStore = .shared,
        pushNotificationManager: any AuthenticatedPushNotificationManaging = PushNotificationService.shared
    ) {
        self.monetizationIdentityManager = monetizationIdentityManager
        self.authenticationClient = authenticationClient
        self.authenticationStateObserver = authenticationStateObserver
        self.profileSessionProvider = profileSessionProvider
        self.accountSessionStore = accountSessionStore
        self.pushNotificationManager = pushNotificationManager
        lastUsedProvider = accountSessionStore.lastUsedProvider

        // Load cached display name immediately for UI responsiveness
        displayName = profileSessionProvider.cachedDisplayName() ?? ""
        
        // Load cached profile picture URL
        if let cachedURLString = profileSessionProvider.cachedProfilePictureURL() {
            customProfilePictureURL = URL(string: cachedURLString)
        }

        if let currentUser = authenticationStateObserver.currentUser {
            user = currentUser
            authenticatedUserID = currentUser.uid
            photoURL = currentUser.photoURL
            authenticationState = .restoringSession
        }

        registerAuthStateHandler()
    }

    func registerAuthStateHandler() {
        guard authStateObservation == nil else { return }

        authStateObservation = authenticationStateObserver.observe { [weak self] user in
            self?.handleAuthenticationStateChange(user)
        }
    }

    private func handleAuthenticationStateChange(_ user: AuthenticatedUser?) {
        self.user = user
        photoURL = user?.photoURL

        guard let user else {
            endAuthenticatedSession()
            return
        }

        TelemetryManager.shared.setUserId(user.uid)
        TelemetryManager.shared.log(.authSessionRestored)

        let isInteractiveSignIn = authenticationState == .authenticatingWithGoogle ||
            authenticationState == .authenticatingWithApple ||
            authenticationState == .authenticatingWithInternalQA

        let cachedDisplayName = profileSessionProvider.cachedDisplayName() ?? ""
        displayName = cachedDisplayName
        let shouldSaveInitialUserRecord = !isInteractiveSignIn || !cachedDisplayName.isEmpty

        let initialAuthenticationState: AuthenticationState
        if !cachedDisplayName.isEmpty {
            isProfileLoaded = true
            initialAuthenticationState = .authenticated
        } else if isInteractiveSignIn {
            initialAuthenticationState = .authenticated
        } else {
            isProfileLoaded = false
            initialAuthenticationState = .restoringSession
        }
        beginAuthenticatedSession(
            userID: user.uid,
            initialState: initialAuthenticationState
        )

        Task {
            if shouldSaveInitialUserRecord {
                try? await profileSessionProvider.saveInitialUser(user)
            }

            let firestoreDisplayName = await profileSessionProvider.displayName(userID: user.uid)
            let profilePictureURLString = await profileSessionProvider.profilePictureURL(userID: user.uid)

            if let firestoreDisplayName, !firestoreDisplayName.isEmpty {
                displayName = firestoreDisplayName
                hasRemoteDisplayName = true
            } else {
                hasRemoteDisplayName = false
            }

            if let profilePictureURLString {
                customProfilePictureURL = URL(string: profilePictureURLString)
            }

            isProfileLoaded = true
            authenticationState = getAuthenticationState()
            TelemetryManager.shared.log(.authProfileLoaded)
        }
    }

    @discardableResult
    func beginAuthenticatedSession(
        userID: String,
        initialState: AuthenticationState
    ) -> Task<Void, Never> {
        authenticatedUserID = userID
        let monetizationTransition = monetizationIdentityManager.prepareIdentity(
            userId: userID
        )
        let identityTask = Task {
            await monetizationIdentityManager.identify(
                userId: userID,
                transition: monetizationTransition
            )
        }
        authenticationState = initialState
        return identityTask
    }

    @discardableResult
    func endAuthenticatedSession() -> Task<Void, Never> {
        let monetizationTransition = monetizationIdentityManager.prepareIdentityReset()
        let identityTask = Task {
            await monetizationIdentityManager.resetIdentity(
                transition: monetizationTransition
            )
        }

        TelemetryManager.shared.log(.authSignOut)
        TelemetryManager.shared.clearUserId()
        user = nil
        photoURL = nil
        authenticatedUserID = nil
        displayName = ""
        customProfilePictureURL = nil
        hasRemoteDisplayName = false
        isProfileLoaded = false
        authenticationState = .unauthenticated
        profileSessionProvider.clearCache()
        return identityTask
    }
}

@MainActor
extension AuthenticationViewModel {
    func signOut() {
        Task { @MainActor in
            await pushNotificationManager.unregisterCurrentDevice()

            do {
                try authenticationClient.signOut()
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
            try await authenticationClient.signInWithGoogle()
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
            try await authenticationClient.signInWithEmail(email: trimmedEmail, password: password)
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
            try await authenticationClient.signInWithApple()
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
            try await authenticationClient.updateUserDisplayName(displayName: fullDisplayName)
            displayName = fullDisplayName
            
            // Cache display name for immediate UI updates
            UserDataRepository.shared.cacheDisplayName(fullDisplayName)
            
            // Save updated user info to Firestore with individual names
            if let user = user {
                try await UserDataRepository.shared.saveUserToFirestore(
                    userId: user.uid,
                    email: user.email,
                    firstName: firstName,
                    lastName: lastName,
                    displayName: fullDisplayName
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
    
    func updateProfilePicture(photoPickerItem: PhotosPickerItem) async {
        errorMessage = nil
        
        guard let user = user else {
            errorMessage = "User not authenticated"
            return
        }
        
        do {
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
            errorMessage = "Failed to update profile picture: \(error.localizedDescription)"
        }
    }
    
    func updateProfilePictureWithData(imageData: Data) async {
        errorMessage = nil
        
        guard let user = user else {
            errorMessage = "User not authenticated"
            return
        }
        
        do {
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
            errorMessage = "Failed to update profile picture: \(error.localizedDescription)"
        }
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
        
        let trimmedName = newDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedName.isEmpty else {
            errorMessage = "Display name cannot be empty"
            return false
        }
        
        let previousDisplayName = displayName

        do {
            // Update local state immediately for responsive UI
            displayName = trimmedName

            try await authenticationClient.updateUserDisplayName(displayName: trimmedName)
            
            // Save to Firestore user document
            try await UserDataRepository.shared.updateDisplayName(
                userId: user.uid,
                email: user.email,
                displayName: trimmedName
            )
            hasRemoteDisplayName = true

            return true
            
        } catch {
            displayName = previousDisplayName
            errorMessage = "Failed to update display name: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func updateOnboardingProfile(displayName newDisplayName: String, age: Int, gender: ProfileGender) async -> Bool {
        errorMessage = nil

        guard let user else {
            errorMessage = "User not authenticated"
            return false
        }

        let trimmedName = newDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            errorMessage = "Display name cannot be empty"
            return false
        }

        guard (13...120).contains(age) else {
            errorMessage = "Enter an age from 13 to 120"
            return false
        }

        let previousDisplayName = displayName

        do {
            displayName = trimmedName

            try await authenticationClient.updateUserDisplayName(displayName: trimmedName)

            try await UserDataRepository.shared.updateOnboardingProfile(
                userId: user.uid,
                email: user.email,
                displayName: trimmedName,
                age: age,
                gender: gender
            )
            hasRemoteDisplayName = true

            return true
        } catch {
            displayName = previousDisplayName
            errorMessage = "Failed to update profile: \(error.localizedDescription)"
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
    func updateOnboardingAge(_ age: Int) async -> Bool {
        errorMessage = nil

        guard let user else {
            errorMessage = "User not authenticated"
            return false
        }

        guard (13...120).contains(age) else {
            errorMessage = "Enter an age from 13 to 120"
            return false
        }

        do {
            try await UserDataRepository.shared.updateOnboardingDemographics(
                userId: user.uid,
                email: user.email,
                displayName: displayName,
                age: age
            )
            return true
        } catch {
            errorMessage = "Failed to update profile: \(error.localizedDescription)"
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
            do {
                try await LeaderboardService.shared.updateBodyWeight(
                    userId: user.uid,
                    weightKg: weightKg
                )
            } catch {
                debugLog("Warning: Failed to update leaderboard body weight: \(error)")
            }
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
            do {
                try await LeaderboardService.shared.updateBodyWeight(
                    userId: user.uid,
                    weightKg: weightKg
                )
            } catch {
                debugLog("Warning: Failed to update leaderboard body weight: \(error)")
            }
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

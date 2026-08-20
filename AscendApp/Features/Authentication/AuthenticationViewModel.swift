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

    /// What the sign-in provider supplied that the climber's profile does not
    /// carry yet - Apple or Google alike. Present only while something is still
    /// owed: it is dropped the moment the name reaches the profile, or the moment
    /// the profile turns out to have a name already.
    ///
    /// The name step reads this to open prefilled, so a climber who shared only
    /// half a name is asked for the missing half rather than for both.
    private(set) var suppliedIdentity: SignInSuppliedIdentity?

    /// Indicates whether the profile data has been loaded from Firestore/cache after auth restore.
    /// Used to avoid showing authenticated UI before profile state is known.
    private(set) var isProfileLoaded: Bool = false

    private var authenticationService: AuthenticationService
    private let accountSessionStore = AccountSessionStore.shared
    private let monetizationIdentityManager: any MonetizationIdentityManaging
    private let signInIdentityStore: SignInIdentityStore

    init(
        monetizationIdentityManager: any MonetizationIdentityManaging = MonetizationManager.shared,
        signInIdentityStore: SignInIdentityStore = .shared,
        observesFirebaseAuth: Bool = true
    ) {
        self.monetizationIdentityManager = monetizationIdentityManager
        self.signInIdentityStore = signInIdentityStore
        self.authenticationService = AuthenticationService(signInIdentityStore: signInIdentityStore)
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

                    // Read synchronously, before any await: the name step is
                    // seeded from this, and a seed that arrives after the screen
                    // is on-screen is a screen that asked for it anyway.
                    self.resolveSuppliedIdentity(for: user)

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
                        // The name the provider supplied is written before anything
                        // reads the profile back, so the name step is already
                        // satisfied by the time onboarding resolves it.
                        let didAdoptSuppliedName = await self.adoptSuppliedName(for: user)

                        // Avoid writing a provider-derived or empty display name during new sign-up.
                        // The post-auth name step creates the profile document with the user's chosen name.
                        if !didAdoptSuppliedName, shouldSaveInitialUserRecord {
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

                    // Signing back in is what repairs credentials that were failing workout
                    // syncs, and this is the only place the app sees the signed-out half of that
                    // transition - including when Firebase revokes a session rather than the
                    // climber tapping sign out.
                    WorkoutSyncCoordinator.shared.forgetAuthenticatedIdentity()

                    // Autonomous workers outlive the session that started them, and this is the
                    // only place the app sees every way one ends - sign out, a revoked session,
                    // a deleted account. Whatever they are still holding belongs to the climber
                    // who just left, so it stops here rather than writing under the next one.
                    AuthenticatedBootstrapCoordinator.shared.endAuthenticatedSession()

                    self.displayName = ""
                    self.customProfilePictureURL = nil
                    self.hasRemoteDisplayName = false
                    // In-memory only. What Apple supplied stays on disk, because
                    // signing out and back in is precisely the case where Apple
                    // hands back nothing at all.
                    self.suppliedIdentity = nil
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

    // MARK: - Provider-supplied identity

    /// Resolves the name this sign-in supplied, from whichever provider it was.
    ///
    /// One path, not a per-provider branch. Apple's copy comes off the persisted
    /// capture, because Apple populates the credential on the first authorization
    /// for an Apple ID and app pair and never again. Google's - and any name
    /// Firebase already holds, including the one Apple's credential just set -
    /// comes off the account itself, because Google supplies it on every sign-in.
    /// The Apple capture is preferred only because it is the copy that is still
    /// owed; both end up in the same value and under the same rule.
    func resolveSuppliedIdentity(for user: User) {
        if let captured = signInIdentityStore.identity(
            forProviderUserID: user.appleProviderUserID
        ) {
            suppliedIdentity = captured
            return
        }

        let fromAccount = SignInSuppliedIdentity(
            providerUserID: user.uid,
            fullName: user.displayName,
            email: user.email
        )
        suppliedIdentity = fromAccount.carriesSomething ? fromAccount : nil
    }

    /// The seam the name step's rendering tests drive, because `resolveSuppliedIdentity`
    /// needs a Firebase `User` no test can construct.
    func loadSuppliedIdentity(forProviderUserID providerUserID: String?) {
        suppliedIdentity = signInIdentityStore.identity(forProviderUserID: providerUserID)
    }

    /// Gives the account a name without ever asking for one.
    ///
    /// Returns `true` when it wrote the profile itself, so the caller does not
    /// write an empty one over the top.
    ///
    /// Resolution always terminates: a profile that already carries a name keeps
    /// it (step 1, and what a climber who deleted and reinstalled lands on), else
    /// whatever the provider supplied at this sign-in (step 2), else
    /// `SignInNamePlaceholder` (step 3). Only a profile that could not be *read*
    /// is left alone, and only until the next launch can read it. There is no
    /// fourth outcome and no screen behind this - the name step was removed.
    ///
    /// A failed write is not a dead end either. Nothing caches a name that never
    /// landed, so the next launch takes this same path again and retries; until
    /// it lands the climber renders under a system handle rather than being
    /// blocked.
    @discardableResult
    func adoptSuppliedName(for user: User) async -> Bool {
        // Resolution step 1, answered without a round trip. A name Ascend
        // already holds locally is a profile that already carries one, so the
        // read could only ever conclude `.discard` - and this runs on the sign-in
        // path, ahead of the authenticated UI, where every launch would pay for
        // it. The capture has done its job either way, so it stops taking up
        // room on disk here rather than outliving the install.
        //
        // Deliberately no `adoptableName` guard below it: half a name is not
        // publishable, but it still has to reach `.writePlaceholder`. There is no
        // name step left for it to fall through to.
        if carriesKnownDisplayName {
            forgetSuppliedIdentity()
            return false
        }

        let storedName: StoredProfileName
        do {
            let storedProfile = try await UserDataRepository.shared.getUserFromFirestore(
                userId: user.uid
            )
            storedName = storedProfile.resolvedDisplayName?.isEmpty == false ? .present : .absent
        } catch {
            storedName = .unreadable
        }

        switch SuppliedNameAdoption.decide(supplied: suppliedIdentity, storedName: storedName) {
        case .write(let firstName, let lastName):
            guard await writeResolvedName(firstName: firstName, lastName: lastName) else {
                return false
            }
            forgetSuppliedIdentity()
            return true

        case .writePlaceholder:
            // The one name nobody supplied. It is written rather than asked for,
            // because the screen that used to ask is what App Review rejected.
            guard await writeResolvedName(
                firstName: SignInNamePlaceholder.firstName,
                lastName: SignInNamePlaceholder.lastName
            ) else {
                return false
            }
            // A capture that could not compose a publishable name has done all it
            // will ever do; keeping it would leave the climber's Apple email on
            // disk indefinitely and keep it outranking the account's own values.
            forgetSuppliedIdentity()
            return true

        case .discard:
            forgetSuppliedIdentity()
            return false

        case .retryLater:
            return false
        }
    }

    /// Writes a resolved name and reports a failure where production can see it.
    ///
    /// Scoped, because this runs behind a sign-in nobody is watching: an app-wide
    /// `errorMessage` left here would surface under whatever screen the climber
    /// lands on next. And reported through telemetry rather than `debugLog`,
    /// which compiles to nothing outside DEBUG - a climber silently left with no
    /// name is exactly the outcome this whole path exists to prevent, so it may
    /// not be invisible in the builds that matter.
    private func writeResolvedName(firstName: String, lastName: String) async -> Bool {
        let failure = await scopedProfileUpdate(
            fallback: "Failed to save the name your sign-in supplied"
        ) {
            await self.updateProfileName(firstName: firstName, lastName: lastName)
        }

        guard let failure else { return true }

        // Nothing caches a name that never landed, so the next launch retries.
        // Apple will never hand its copy back again, so any capture stays put.
        debugLog("Deferred resolved name: \(failure)")
        TelemetryManager.shared.recordError(
            AuthenticationError.signInFailed(failure),
            context: .firestore,
            code: "resolved_name_write_failed"
        )
        return false
    }

    /// Drops the in-memory copy, and the persisted one if this identity came from
    /// there. An identity derived from the Firebase account is keyed by the
    /// Firebase `uid`, which is never a key in the store, so the disk half is a
    /// no-op for it - the account keeps supplying it on every sign-in and there
    /// is nothing to expire.
    ///
    /// Called from every point a name reaches the profile, whoever supplied it.
    /// A capture that can no longer do anything - the climber typed their own
    /// name, or shared only half of one and then skipped - is a climber's email
    /// address sitting in `UserDefaults` for the life of the install otherwise.
    private func forgetSuppliedIdentity() {
        guard let supplied = suppliedIdentity else { return }
        signInIdentityStore.forget(providerUserID: supplied.providerUserID)
        suppliedIdentity = nil
    }

    /// Whether Ascend already holds a display name for this account without
    /// asking Firestore - the cached one this session opened with, or one just
    /// written.
    ///
    /// Seeded from `UserDataRepository.getCachedDisplayName()` before any await
    /// on the sign-in path, and cleared on sign-out through `clearUserCache()`,
    /// so it cannot carry one account's name into the next climber's session and
    /// suppress their resolution.
    private var carriesKnownDisplayName: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The address to record on the profile.
    ///
    /// Firebase carries Apple's email - relay addresses included - on every
    /// sign-in, because it comes from the identity token. The captured copy is
    /// the fallback for the one case where it does not.
    private func profileEmail(for user: User) -> String? {
        let firebaseEmail = user.email?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let firebaseEmail, !firebaseEmail.isEmpty {
            return firebaseEmail
        }
        return suppliedIdentity?.email
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
            email: profileEmail(for: user),
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
                email: profileEmail(for: user),
                firstName: normalizedFirstName,
                lastName: normalizedLastName
            )
            hasRemoteDisplayName = true
            forgetSuppliedIdentity()
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
            forgetSuppliedIdentity()

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

private extension User {
    /// The Apple ID this account is linked to, which is the key a Sign in with
    /// Apple capture is stored under.
    var appleProviderUserID: String? {
        providerData
            .first { $0.providerID == AuthProviderID.apple.rawValue }?
            .uid
    }
}

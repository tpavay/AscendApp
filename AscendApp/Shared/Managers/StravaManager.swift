//
//  StravaManager.swift
//  AscendApp
//
//  Created by Claude Code on 12/9/24.
//

import Foundation
import Observation
import AuthenticationServices
import FirebaseAuth
import FirebaseCore
@preconcurrency import FirebaseFirestore

/// Manages Strava integration state and communication with Cloud Functions
@MainActor
@Observable
final class StravaManager: NSObject {
    static let shared = StravaManager()

    // MARK: - Configuration

    private nonisolated let region = "us-central1"

    private nonisolated var baseURL: String {
        guard let projectId = FirebaseApp.app()?.options.projectID else {
            fatalError("Firebase not configured")
        }
        return "https://\(region)-\(projectId).cloudfunctions.net"
    }

    // MARK: - Cache Keys

    private nonisolated let isConnectedKey = "stravaIsConnected"
    private nonisolated let athleteNameKey = "stravaAthleteName"

    // MARK: - UI State

    var isConnected: Bool = false {
        didSet {
            UserDefaults.standard.set(isConnected, forKey: isConnectedKey)
        }
    }
    var athleteName: String = "" {
        didSet {
            UserDefaults.standard.set(athleteName, forKey: athleteNameKey)
        }
    }
    var isConnecting: Bool = false
    var connectionError: String? = nil

    // MARK: - Local Preferences

    var autoSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoSyncEnabled, forKey: "stravaAutoSyncEnabled")
        }
    }

    // MARK: - Private State

    private nonisolated let db = Firestore.firestore()
    private var authSession: ASWebAuthenticationSession?

    // MARK: - Initialization

    private override init() {
        self.autoSyncEnabled = UserDefaults.standard.bool(forKey: "stravaAutoSyncEnabled")
        super.init()

        // Load cached connection status immediately for instant UI
        isConnected = UserDefaults.standard.bool(forKey: isConnectedKey)
        athleteName = UserDefaults.standard.string(forKey: athleteNameKey) ?? ""

        // Refresh from Firestore in background to ensure cache is up-to-date
        print("🔶 Strava: StravaManager init, cached isConnected=\(isConnected), scheduling refreshConnectionStatus")
        Task {
            await refreshConnectionStatus()
        }
    }

    // MARK: - Public API

    /// Start the OAuth flow to connect Strava
    func startOAuthFlow(presentationAnchor: ASPresentationAnchor) async {
        isConnecting = true
        connectionError = nil
        TelemetryManager.shared.log(.stravaConnectStarted)

        do {
            // 1. Get state ID from Cloud Function
            let stateResponse = try await callCreateOAuthState()

            // 2. Build auth URL
            let redirectUri = "https://\(projectId).web.app/strava/callback"
            let authURLString = """
                https://www.strava.com/oauth/authorize\
                ?client_id=\(stateResponse.clientId)\
                &redirect_uri=\(redirectUri.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? redirectUri)\
                &response_type=code\
                &scope=activity:write\
                &state=\(stateResponse.stateId)
                """

            guard let authURL = URL(string: authURLString) else {
                throw StravaError.authenticationFailed("Invalid auth URL")
            }

            // 3. Present auth session
            await withCheckedContinuation { continuation in
                let session = ASWebAuthenticationSession(
                    url: authURL,
                    callbackURLScheme: "ascendapp"
                ) { [weak self] callbackURL, error in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }

                        if let error = error as? ASWebAuthenticationSessionError,
                           error.code == .canceledLogin {
                            // User cancelled - no need to show error
                            self.isConnecting = false
                        } else if error != nil {
                            self.connectionError = "Connection failed"
                            self.isConnecting = false
                        } else if let url = callbackURL {
                            // Parse callback URL for status
                            self.handleOAuthCallback(url: url)
                        }

                        continuation.resume()
                    }
                }

                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                self.authSession = session

                if !session.start() {
                    Task {
                        self.connectionError = "Failed to start authentication"
                        self.isConnecting = false
                    }
                    continuation.resume()
                }
            }

        } catch {
            connectionError = error.localizedDescription
            isConnecting = false
        }
    }

    /// Handle the OAuth callback deep link
    func handleOAuthCallback(url: URL) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let status = components?.queryItems?.first(where: { $0.name == "status" })?.value

        if status == "success" {
            TelemetryManager.shared.log(.stravaConnectSuccess)
            // Refresh connection status from Firestore
            Task {
                await self.refreshConnectionStatus()
                self.isConnecting = false
            }
        } else {
            TelemetryManager.shared.log(.stravaConnectFailed)
            let message = components?.queryItems?.first(where: { $0.name == "message" })?.value
            connectionError = message ?? "Connection failed"
            isConnecting = false
        }
    }

    /// Disconnect from Strava
    func disconnect() async throws {
        try await callDisconnect()
        // Setting these will trigger didSet which updates the cache
        isConnected = false
        athleteName = ""
    }

    /// Sync a workout to Strava
    /// - Parameters:
    ///   - workout: The workout to sync
    ///   - primaryMetric: The user's preferred primary metric for display
    /// - Returns: The Strava activity ID
    func syncWorkout(_ workout: Workout, primaryMetric: WorkoutMetric) async throws -> Int {
        TelemetryManager.shared.log(.stravaSyncStarted)

        let payload = StravaWorkoutPayload(workout: workout, primaryMetric: primaryMetric)

        let response: CreateActivityResponse
        do {
            response = try await callCreateActivity(workout: payload)
        } catch {
            // Network/API error - log failure and record non-fatal
            TelemetryManager.shared.log(.stravaSyncFailed)
            TelemetryManager.shared.recordError(error, context: .strava, code: "sync_failed")
            throw error
        }

        // Handle response cases
        if response.success {
            if let activityId = response.stravaActivityId {
                TelemetryManager.shared.log(.stravaSyncCompleted)
                return activityId
            } else if response.alreadyExists == true {
                // Activity was already synced - this is a success, not a failure
                TelemetryManager.shared.log(.stravaSyncCompleted)
                throw StravaError.activityCreationFailed("Already synced")
            }
        }

        // Response indicated failure (but not a network error)
        TelemetryManager.shared.log(.stravaSyncFailed)
        throw StravaError.activityCreationFailed(response.message ?? "Unknown error")
    }

    /// Refresh connection status from Firestore
    func refreshConnectionStatus() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("🔶 Strava: No current user, setting disconnected")
            isConnected = false
            athleteName = ""
            return
        }

        print("🔶 Strava: Checking connection for user: \(userId)")

        do {
            let docRef = db.collection("users").document(userId)
                .collection("integrations").document("strava")
            let doc = try await docRef.getDocument()

            print("🔶 Strava: Doc exists=\(doc.exists), data=\(String(describing: doc.data()))")

            if doc.exists, let data = doc.data() {
                let name = data["athleteName"] as? String ?? ""
                print("🔶 Strava: Setting connected=true, name=\(name)")
                isConnected = true
                athleteName = name
            } else {
                print("🔶 Strava: No document, setting disconnected")
                isConnected = false
                athleteName = ""
            }
        } catch {
            print("🔶 Strava: Error checking connection: \(error)")
            isConnected = false
            athleteName = ""
        }
    }

    /// Clear local state (called on logout)
    func clearLocalState() {
        isConnected = false
        athleteName = ""
        connectionError = nil
        isConnecting = false
    }

    // MARK: - Cloud Function Calls

    private func callCreateOAuthState() async throws -> CreateOAuthStateResponse {
        guard let user = Auth.auth().currentUser else {
            throw StravaError.notConfigured
        }

        let idToken: String
        do {
            idToken = try await user.getIDToken()
        } catch {
            throw StravaError.networkError("Connection error. Please try again.")
        }

        let url = URL(string: "\(baseURL)/stravaCreateOAuthState")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["data": [:]])

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw StravaError.authenticationFailed("Failed to create OAuth state")
        }

        // Callable functions return {"result": {...}}
        struct CallableResponse: Decodable {
            let result: CreateOAuthStateResponse
        }

        let decoded = try JSONDecoder().decode(CallableResponse.self, from: data)
        return decoded.result
    }

    private func callCreateActivity(workout: StravaWorkoutPayload) async throws -> CreateActivityResponse {
        guard let idToken = try? await Auth.auth().currentUser?.getIDToken() else {
            throw StravaError.notConnected
        }

        let url = URL(string: "\(baseURL)/stravaCreateActivity")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Encode workout as data payload
        let encoder = JSONEncoder()
        let workoutData = try encoder.encode(workout)
        let workoutDict = try JSONSerialization.jsonObject(with: workoutData) as? [String: Any] ?? [:]

        let body: [String: Any] = ["data": ["workout": workoutDict]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StravaError.networkError("Invalid response")
        }

        if httpResponse.statusCode == 200 {
            struct CallableResponse: Decodable {
                let result: CreateActivityResponse
            }
            let decoded = try JSONDecoder().decode(CallableResponse.self, from: data)
            return decoded.result
        } else {
            throw StravaError.activityCreationFailed("HTTP \(httpResponse.statusCode)")
        }
    }

    private func callDisconnect() async throws {
        guard let idToken = try? await Auth.auth().currentUser?.getIDToken() else {
            throw StravaError.notConnected
        }

        let url = URL(string: "\(baseURL)/stravaDisconnect")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["data": [:]])

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw StravaError.networkError("Failed to disconnect")
        }
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension StravaManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Return the key window as the presentation anchor
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            return window
        }
        return ASPresentationAnchor()
    }
}

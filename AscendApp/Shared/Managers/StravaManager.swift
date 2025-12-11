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
@preconcurrency import FirebaseFirestore

/// Manages Strava integration state and communication with Cloud Functions
@MainActor
@Observable
final class StravaManager: NSObject {
    static let shared = StravaManager()

    // MARK: - Configuration

    private nonisolated let projectId = "ascend-f2e4f"
    private nonisolated let region = "us-central1"

    private nonisolated var baseURL: String {
        "https://\(region)-\(projectId).cloudfunctions.net"
    }

    // MARK: - UI State

    var isConnected: Bool = false
    var athleteName: String = ""
    var isConnecting: Bool = false
    var connectionError: String? = nil

    // MARK: - Local Preferences

    var autoSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoSyncEnabled, forKey: "stravaAutoSyncEnabled")
            UserDefaults.standard.synchronize()
        }
    }

    // MARK: - Private State

    private nonisolated let db = Firestore.firestore()
    private var authSession: ASWebAuthenticationSession?

    // MARK: - Initialization

    private override init() {
        self.autoSyncEnabled = UserDefaults.standard.bool(forKey: "stravaAutoSyncEnabled")
        super.init()

        // Check connection status on init
        print("🔶 Strava: StravaManager init, scheduling refreshConnectionStatus")
        Task {
            await refreshConnectionStatus()
        }
    }

    // MARK: - Public API

    /// Start the OAuth flow to connect Strava
    func startOAuthFlow(presentationAnchor: ASPresentationAnchor) async {
        isConnecting = true
        connectionError = nil

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
                            self.connectionError = "Connection cancelled"
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
            // Refresh connection status from Firestore
            Task {
                await self.refreshConnectionStatus()
                self.isConnecting = false
            }
        } else {
            let message = components?.queryItems?.first(where: { $0.name == "message" })?.value
            connectionError = message ?? "Connection failed"
            isConnecting = false
        }
    }

    /// Disconnect from Strava
    func disconnect() async throws {
        try await callDisconnect()
        isConnected = false
        athleteName = ""
    }

    /// Sync a workout to Strava
    /// - Parameters:
    ///   - workout: The workout to sync
    ///   - primaryMetric: The user's preferred primary metric for display
    /// - Returns: The Strava activity ID
    func syncWorkout(_ workout: Workout, primaryMetric: WorkoutMetric) async throws -> Int {
        let payload = StravaWorkoutPayload(workout: workout, primaryMetric: primaryMetric)
        let response = try await callCreateActivity(workout: payload)

        if response.success {
            if let activityId = response.stravaActivityId {
                return activityId
            } else if response.alreadyExists == true {
                // Activity was already synced - this is fine
                throw StravaError.activityCreationFailed("Already synced")
            }
        }

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

//
//  HevyManager.swift
//  AscendApp
//
//  Created by Claude Code on 12/12/24.
//

import Foundation
import Security
import Observation

@MainActor
@Observable
final class HevyManager {
    static let shared = HevyManager()

    private let baseURL = "https://api.hevyapp.com/v1"
    private let keychainService = "com.ascendapp.hevy"
    private let keychainAccount = "apiKey"

    // Connection state - computed from Keychain presence
    var isConnected: Bool {
        hasApiKey && HevySyncState.templateId != nil
    }

    var isConnecting = false
    var connectionError: HevyError?

    private var hasApiKey: Bool {
        getApiKey() != nil
    }

    // MARK: - Auto-Link Apple Health Setting

    private let autoLinkAppleHealthKey = "hevyAutoLinkAppleHealth"

    /// When enabled, Hevy workouts are automatically enhanced with Apple Health data (HR, calories)
    /// Default: true for new AND existing users
    var autoLinkAppleHealth: Bool {
        get {
            // Default true for new AND existing users
            if UserDefaults.standard.object(forKey: autoLinkAppleHealthKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: autoLinkAppleHealthKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: autoLinkAppleHealthKey)
        }
    }

    private init() {}

    // MARK: - Connection Management

    /// Connects to Hevy with the provided API key
    /// Validates the key by fetching templates and discovering the stairmaster template
    func connect(apiKey: String) async throws {
        isConnecting = true
        connectionError = nil

        defer { isConnecting = false }

        // Validate API key by fetching templates
        let templates = try await fetchExerciseTemplates(apiKey: apiKey)

        // Find stairmaster template based on user's preferred metric
        let preferredMetric = SettingsManager.shared.preferredWorkoutMetric
        let searchTitle = preferredMetric == .floors ? "Stair Machine (Floors)" : "Stair Machine (Steps)"

        guard let stairmasterTemplate = templates.first(where: { $0.title == searchTitle }) else {
            // Try alternate title patterns
            let alternateTemplate = templates.first { template in
                let title = template.title.lowercased()
                return title.contains("stair machine") || title.contains("stairmaster") || title.contains("stair stepper")
            }

            if let template = alternateTemplate {
                // Found a stairmaster template with different naming
                try saveApiKey(apiKey)
                HevySyncState.templateId = template.id
                HevySyncState.templateType = template.title.lowercased().contains("floor") ? "floors" : "steps"
                return
            }

            throw HevyError.noStairmasterTemplateFound
        }

        // Save API key to Keychain
        try saveApiKey(apiKey)

        // Store template info in UserDefaults
        HevySyncState.templateId = stairmasterTemplate.id
        HevySyncState.templateType = preferredMetric == .floors ? "floors" : "steps"
    }

    /// Disconnects from Hevy by clearing stored credentials
    func disconnect() {
        deleteApiKey()
        HevySyncState.clear()
        connectionError = nil
    }

    // MARK: - API Calls

    /// Fetches exercise history for the configured template
    func fetchExerciseHistory() async throws -> [HevyExerciseHistory] {
        guard let apiKey = getApiKey() else {
            throw HevyError.invalidApiKey
        }

        guard let templateId = HevySyncState.templateId else {
            throw HevyError.noStairmasterTemplateFound
        }

        var allExercises: [HevyExerciseHistory] = []
        var currentPage = 1
        var totalPages = 1

        repeat {
            let url = URL(string: "\(baseURL)/exercise_history/\(templateId)?page=\(currentPage)&pageSize=20")!
            let response: HevyExerciseHistoryResponse = try await makeRequest(url: url, apiKey: apiKey)

            allExercises.append(contentsOf: response.exercise_history)
            totalPages = response.page_count ?? 1
            currentPage += 1
        } while currentPage <= totalPages

        return allExercises
    }

    /// Fetches exercises newer than the last sync date
    func fetchPendingExercises() async throws -> [HevyExerciseHistory] {
        let allExercises = try await fetchExerciseHistory()

        // Filter to exercises newer than last sync
        guard let lastSync = HevySyncState.lastSyncAt else {
            // First sync - return all exercises
            return allExercises
        }

        return allExercises.filter { exercise in
            guard let endDate = exercise.endDate ?? exercise.startDate else { return false }
            return endDate > lastSync
        }
    }

    /// Fetches all exercise templates to discover stairmaster template ID
    private func fetchExerciseTemplates(apiKey: String) async throws -> [HevyExerciseTemplate] {
        var allTemplates: [HevyExerciseTemplate] = []
        var currentPage = 1
        var totalPages = 1

        repeat {
            let url = URL(string: "\(baseURL)/exercise_templates?page=\(currentPage)&pageSize=100")!
            let response: HevyExerciseTemplatesResponse = try await makeRequest(url: url, apiKey: apiKey)

            allTemplates.append(contentsOf: response.exercise_templates)
            totalPages = response.page_count ?? 1
            currentPage += 1
        } while currentPage <= totalPages

        return allTemplates
    }

    // MARK: - Network Layer

    private func makeRequest<T: Decodable>(url: URL, apiKey: String) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "api-key")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HevyError.networkError(URLError(.badServerResponse))
        }

        switch httpResponse.statusCode {
        case 200...299:
            do {
                let decoder = JSONDecoder()
                return try decoder.decode(T.self, from: data)
            } catch let decodingError as DecodingError {
                // Log detailed decoding error
                switch decodingError {
                case .keyNotFound(let key, let context):
                    print("❌ Hevy decoding: Key '\(key.stringValue)' not found: \(context.debugDescription)")
                case .typeMismatch(let type, let context):
                    print("❌ Hevy decoding: Type mismatch for \(type): \(context.debugDescription)")
                case .valueNotFound(let type, let context):
                    print("❌ Hevy decoding: Value not found for \(type): \(context.debugDescription)")
                case .dataCorrupted(let context):
                    print("❌ Hevy decoding: Data corrupted: \(context.debugDescription)")
                @unknown default:
                    print("❌ Hevy decoding: Unknown error: \(decodingError)")
                }
                // Log the raw response for debugging
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("❌ Hevy API Response:\n\(jsonString.prefix(2000))")
                }
                throw HevyError.decodingError(decodingError)
            } catch {
                print("❌ Hevy unexpected error: \(error)")
                throw HevyError.decodingError(error)
            }

        case 401:
            throw HevyError.invalidApiKey

        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw HevyError.rateLimited(retryAfter: retryAfter)

        default:
            throw HevyError.unknownError(statusCode: httpResponse.statusCode)
        }
    }

    // MARK: - Keychain Operations

    private func saveApiKey(_ apiKey: String) throws {
        // Delete existing key first
        deleteApiKey()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: apiKey.data(using: .utf8)!
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw HevyError.networkError(NSError(domain: "KeychainError", code: Int(status)))
        }
    }

    private func getApiKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let apiKey = String(data: data, encoding: .utf8) else {
            return nil
        }

        return apiKey
    }

    private func deleteApiKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]

        SecItemDelete(query as CFDictionary)
    }
}

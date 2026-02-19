//
//  WorkoutParsingService.swift
//  AscendApp
//
//  Created by Claude on 2/19/26.
//

import Foundation

/// Parsed workout data from voice input
struct ParsedWorkoutData: Codable {
    var durationMinutes: Int?
    var steps: Int?
    var floors: Int?
    var weightEquipment: [WeightEquipmentItem]?
    var intervals: [IntervalItem]?
    var heartRateAvg: Int?
    var heartRateMax: Int?
    var calories: Int?
    var notes: String?
    
    struct WeightEquipmentItem: Codable {
        let type: String
        let weightLbs: Double
        let quantity: Int?
        
        enum CodingKeys: String, CodingKey {
            case type
            case weightLbs = "weight_lbs"
            case quantity
        }
    }
    
    struct IntervalItem: Codable {
        let durationMinutes: Int?
        let steps: Int?
        
        enum CodingKeys: String, CodingKey {
            case durationMinutes = "duration_minutes"
            case steps
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case durationMinutes = "duration_minutes"
        case steps
        case floors
        case weightEquipment = "weight_equipment"
        case intervals
        case heartRateAvg = "heart_rate_avg"
        case heartRateMax = "heart_rate_max"
        case calories
        case notes
    }
}

/// Service for parsing natural language workout descriptions using LLM
actor WorkoutParsingService {
    
    // MARK: - Configuration
    
    /// API endpoint - defaults to Anthropic Claude
    private let apiEndpoint = "https://api.anthropic.com/v1/messages"
    
    /// Model to use - Claude Haiku for cost efficiency
    private let model = "claude-3-haiku-20240307"
    
    /// API key stored in environment or config
    /// In production, this should come from secure storage
    private var apiKey: String? {
        // Try to get from UserDefaults (set during onboarding or settings)
        if let key = UserDefaults.standard.string(forKey: "anthropic_api_key"), !key.isEmpty {
            return key
        }
        // Fallback to environment variable (for development)
        return ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
    }
    
    // MARK: - Parsing
    
    /// Parse a natural language workout description into structured data
    /// - Parameter text: The transcribed voice input
    /// - Returns: Parsed workout data
    func parseWorkoutDescription(_ text: String) async throws -> ParsedWorkoutData {
        guard let apiKey = apiKey else {
            throw ParsingError.noApiKey
        }
        
        let prompt = buildPrompt(for: text)
        let response = try await callClaudeAPI(prompt: prompt, apiKey: apiKey)
        let parsed = try parseResponse(response)
        
        return parsed
    }
    
    /// Build the system prompt and user message for the LLM
    private func buildPrompt(for userInput: String) -> String {
        """
        Extract workout data from this voice input. Return ONLY valid JSON, no other text.
        
        Fields to extract (all optional):
        - duration_minutes: number (total workout duration)
        - steps: number (total steps climbed)
        - floors: number (total floors climbed)
        - weight_equipment: array of objects with:
          - type: string (e.g., "vest", "ankle_weights", "backpack", "dumbbells")
          - weight_lbs: number
          - quantity: number (default 1, use 2 for "both ankles" etc.)
        - intervals: array of objects with:
          - duration_minutes: number
          - steps: number (optional)
        - heart_rate_avg: number
        - heart_rate_max: number
        - calories: number
        - notes: string (any other details)
        
        Examples:
        Input: "30 minutes, 3000 steps, wore my 20 pound vest"
        Output: {"duration_minutes": 30, "steps": 3000, "weight_equipment": [{"type": "vest", "weight_lbs": 20, "quantity": 1}]}
        
        Input: "did three intervals, 5 minutes then 10 minutes then 5 minutes, 2000 total steps, had 2.5 pound ankle weights on both ankles"
        Output: {"duration_minutes": 20, "steps": 2000, "intervals": [{"duration_minutes": 5}, {"duration_minutes": 10}, {"duration_minutes": 5}], "weight_equipment": [{"type": "ankle_weights", "weight_lbs": 2.5, "quantity": 2}]}
        
        Input: "quick 20 minute session, felt really good, got my heart rate up to 165"
        Output: {"duration_minutes": 20, "heart_rate_max": 165, "notes": "felt really good"}
        
        Now parse this input:
        \(userInput)
        """
    }
    
    /// Call the Claude API
    private func callClaudeAPI(prompt: String, apiKey: String) async throws -> String {
        var request = URLRequest(url: URL(string: apiEndpoint)!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 500,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ParsingError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ParsingError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }
        
        // Parse Claude's response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            throw ParsingError.invalidResponse
        }
        
        return text
    }
    
    /// Parse the LLM response into structured data
    private func parseResponse(_ response: String) throws -> ParsedWorkoutData {
        // Clean up response - remove any markdown code blocks if present
        var cleanedResponse = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try to find JSON in the response
        if let startIndex = cleanedResponse.firstIndex(of: "{"),
           let endIndex = cleanedResponse.lastIndex(of: "}") {
            cleanedResponse = String(cleanedResponse[startIndex...endIndex])
        }
        
        guard let jsonData = cleanedResponse.data(using: .utf8) else {
            throw ParsingError.invalidJSON
        }
        
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(ParsedWorkoutData.self, from: jsonData)
        } catch {
            print("JSON parsing error: \(error)")
            print("Response was: \(cleanedResponse)")
            throw ParsingError.invalidJSON
        }
    }
}

// MARK: - Errors

enum ParsingError: LocalizedError {
    case noApiKey
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case invalidJSON
    
    var errorDescription: String? {
        switch self {
        case .noApiKey:
            return "No API key configured. Please add your Anthropic API key in Settings."
        case .invalidResponse:
            return "Received an invalid response from the server."
        case .apiError(let statusCode, let message):
            return "API error (\(statusCode)): \(message)"
        case .invalidJSON:
            return "Could not parse the workout data. Please try again."
        }
    }
}

// MARK: - Fallback Regex Parser

/// Simple regex-based parser for when LLM is not available
struct FallbackWorkoutParser {
    
    static func parse(_ text: String) -> ParsedWorkoutData {
        var data = ParsedWorkoutData()
        let lowercased = text.lowercased()
        
        // Extract duration
        if let match = lowercased.range(of: #"(\d+)\s*(minutes?|mins?|min)"#, options: .regularExpression) {
            let numStr = String(lowercased[match]).components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            data.durationMinutes = Int(numStr)
        }
        
        // Extract steps
        if let match = lowercased.range(of: #"(\d+)\s*steps?"#, options: .regularExpression) {
            let numStr = String(lowercased[match]).components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            data.steps = Int(numStr)
        }
        
        // Extract floors
        if let match = lowercased.range(of: #"(\d+)\s*floors?"#, options: .regularExpression) {
            let numStr = String(lowercased[match]).components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            data.floors = Int(numStr)
        }
        
        // Extract vest weight
        if let match = lowercased.range(of: #"(\d+)\s*(pound|lb)s?\s*(weighted\s*)?vest"#, options: .regularExpression) {
            let numStr = String(lowercased[match]).components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            if let weight = Double(numStr) {
                data.weightEquipment = [ParsedWorkoutData.WeightEquipmentItem(type: "vest", weightLbs: weight, quantity: 1)]
            }
        }
        
        return data
    }
}

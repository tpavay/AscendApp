//
//  ConversationalHomeView.swift
//  AscendApp
//
//  Created by Claude on 2/19/26.
//

import SwiftUI
import SwiftData

/// Voice-first home screen for logging workouts conversationally
struct ConversationalHomeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthenticationViewModel.self) private var authVM
    
    @State private var themeManager = ThemeManager.shared
    @State private var voiceManager = VoiceInputManager()
    @State private var userInput: String = ""
    @State private var isProcessing = false
    @State private var showConfirmation = false
    @State private var parsedData: ParsedWorkoutData?
    @State private var errorMessage: String?
    @State private var showError = false
    
    @Query(sort: \Workout.date, order: .reverse)
    private var recentWorkouts: [Workout]
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    private let examplePhrases = [
        "I did 30 minutes on the stairstepper...",
        "3000 steps with my 20lb vest...",
        "Three intervals: 5, 10, and 5 minutes...",
        "Quick 20 min session, felt great...",
        "45 minutes, 4500 steps, wore ankle weights..."
    ]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection
                
                // Voice/Text Input Card
                inputCard
                
                // Recent Workouts
                if !recentWorkouts.isEmpty {
                    recentWorkoutsSection
                }
                
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        .scrollIndicators(.hidden)
        .themedBackground()
        .sheet(isPresented: $showConfirmation) {
            if let data = parsedData {
                WorkoutConfirmationView(
                    parsedData: data,
                    originalText: userInput,
                    onConfirm: { confirmedData in
                        saveWorkout(confirmedData)
                        showConfirmation = false
                        userInput = ""
                    },
                    onCancel: {
                        showConfirmation = false
                    }
                )
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "Something went wrong")
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("Log Workout")
                .font(.montserratBold(size: 28))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
            
            Text("Speak or type to log your session")
                .font(.montserratRegular(size: 15))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }
    
    // MARK: - Input Card
    
    private var inputCard: some View {
        VStack(spacing: 16) {
            // Animated placeholder or user input
            if userInput.isEmpty && !voiceManager.isRecording {
                TypewriterTextWithCursor(
                    phrases: examplePhrases,
                    typingSpeed: 0.04,
                    pauseDuration: 2.5,
                    gradient: LinearGradient(
                        colors: [
                            Color(red: 0.4, green: 0.7, blue: 1.0),
                            Color(red: 0.6, green: 0.5, blue: 1.0),
                            Color(red: 0.9, green: 0.5, blue: 0.8)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(minHeight: 60)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            } else {
                // Show transcribed/typed text
                TextField("Describe your workout...", text: $userInput, axis: .vertical)
                    .font(.montserratMedium(size: 17))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    .lineLimit(3...6)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            
            // Live transcription indicator
            if voiceManager.isRecording {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .opacity(voiceManager.isRecording ? 1 : 0)
                        .animation(.easeInOut(duration: 0.5).repeatForever(), value: voiceManager.isRecording)
                    
                    Text("Listening...")
                        .font(.montserratMedium(size: 14))
                        .foregroundStyle(.red)
                }
                .padding(.bottom, 8)
            }
            
            Divider()
                .background(effectiveColorScheme == .dark ? Color.white.opacity(0.1) : Color.gray.opacity(0.2))
            
            // Action buttons
            HStack(spacing: 16) {
                // Voice button
                Button {
                    handleVoiceButton()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: voiceManager.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                            .font(.system(size: 24))
                        Text(voiceManager.isRecording ? "Stop" : "Speak")
                            .font(.montserratSemiBold(size: 15))
                    }
                    .foregroundStyle(voiceManager.isRecording ? .red : .accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(voiceManager.isRecording 
                                  ? Color.red.opacity(0.15) 
                                  : Color.accentColor.opacity(0.15))
                    )
                }
                .disabled(isProcessing)
                
                // Submit button
                Button {
                    processInput()
                } label: {
                    HStack(spacing: 8) {
                        if isProcessing {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 24))
                        }
                        Text(isProcessing ? "Processing" : "Log")
                            .font(.montserratSemiBold(size: 15))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(userInput.isEmpty ? Color.gray : Color.accentColor)
                    )
                }
                .disabled(userInput.isEmpty || isProcessing)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(effectiveColorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(effectiveColorScheme == .dark ? Color.white.opacity(0.1) : Color.gray.opacity(0.15), lineWidth: 1)
                )
        )
        .onChange(of: voiceManager.transcribedText) { _, newValue in
            if !newValue.isEmpty {
                userInput = newValue
            }
        }
    }
    
    // MARK: - Recent Workouts
    
    private var recentWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Workouts")
                .font(.montserratSemiBold(size: 18))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
            
            ForEach(recentWorkouts.prefix(3)) { workout in
                NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                    RecentWorkoutRow(workout: workout, colorScheme: effectiveColorScheme)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    // MARK: - Actions
    
    private func handleVoiceButton() {
        HapticsManager.shared.trigger(.selection)
        
        if voiceManager.isRecording {
            voiceManager.stopRecording()
        } else {
            do {
                try voiceManager.startRecording()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
    
    private func processInput() {
        guard !userInput.isEmpty else { return }
        
        HapticsManager.shared.trigger(.selection)
        isProcessing = true
        
        Task {
            do {
                let service = WorkoutParsingService()
                let parsed = try await service.parseWorkoutDescription(userInput)
                
                await MainActor.run {
                    parsedData = parsed
                    showConfirmation = true
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    // Fallback to regex parser
                    let fallbackData = FallbackWorkoutParser.parse(userInput)
                    if fallbackData.durationMinutes != nil || fallbackData.steps != nil {
                        parsedData = fallbackData
                        showConfirmation = true
                    } else {
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                    isProcessing = false
                }
            }
        }
    }
    
    private func saveWorkout(_ data: ParsedWorkoutData) {
        let settingsManager = SettingsManager.shared
        
        // Convert parsed data to workout
        let duration = TimeInterval((data.durationMinutes ?? 0) * 60)
        let steps = data.steps ?? 0
        let floors = data.floors ?? Workout.stepsToFloors(steps, stepsPerFloor: settingsManager.stepsPerFloor)
        
        let workout = Workout(
            name: Workout.generateDefaultName(for: Date()),
            date: Date(),
            duration: duration,
            steps: steps,
            floors: floors,
            stepsPerFloor: settingsManager.stepsPerFloor,
            avgHeartRate: data.heartRateAvg,
            maxHeartRate: data.heartRateMax,
            caloriesBurned: data.calories,
            notes: data.notes
        )
        
        // Add weight configuration if present
        if let weightItems = data.weightEquipment, !weightItems.isEmpty {
            var entries: [WeightConfiguration.Entry] = []
            for item in weightItems {
                if let type = WeightEquipmentType.fromString(item.type) {
                    entries.append(WeightConfiguration.Entry(
                        equipmentType: type,
                        weightLbs: item.weightLbs,
                        isEnabled: true
                    ))
                }
            }
            if !entries.isEmpty {
                workout.weightConfiguration = WeightConfiguration(entries: entries)
            }
        }
        
        modelContext.insert(workout)
        
        do {
            try modelContext.save()
            HapticsManager.shared.trigger(.success)
        } catch {
            print("Failed to save workout: \(error)")
        }
    }
}

// MARK: - Recent Workout Row

private struct RecentWorkoutRow: View {
    let workout: Workout
    let colorScheme: ColorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.name)
                    .font(.montserratSemiBold(size: 15))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .lineLimit(1)
                
                Text(formattedDate)
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .gray)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(workout.steps) steps")
                    .font(.montserratSemiBold(size: 14))
                    .foregroundStyle(.accent)
                
                Text(formattedDuration)
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .gray)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.02))
        )
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(workout.date) {
            formatter.dateFormat = "'Today at' h:mm a"
        } else if Calendar.current.isDateInYesterday(workout.date) {
            formatter.dateFormat = "'Yesterday at' h:mm a"
        } else {
            formatter.dateFormat = "MMM d 'at' h:mm a"
        }
        return formatter.string(from: workout.date)
    }
    
    private var formattedDuration: String {
        let minutes = Int(workout.duration / 60)
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes) min"
    }
}

// MARK: - Weight Equipment Type Extension

extension WeightEquipmentType {
    static func fromString(_ string: String) -> WeightEquipmentType? {
        let lowercased = string.lowercased()
        switch lowercased {
        case "vest", "weighted vest", "weight vest":
            return .vest
        case "ankle_weights", "ankle weights", "ankleweights":
            return .ankleWeights
        case "backpack", "weighted backpack":
            return .backpack
        case "dumbbells", "dumbbell":
            return .dumbbells
        case "wrist_weights", "wrist weights", "wristweights":
            return .wristWeights
        default:
            return nil
        }
    }
}

#Preview {
    NavigationStack {
        ConversationalHomeView()
    }
    .environment(AuthenticationViewModel())
}

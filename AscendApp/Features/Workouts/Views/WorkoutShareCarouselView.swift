//
//  WorkoutShareCarouselView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 11/26/25.
//

import Photos
import SwiftData
import SwiftUI
import UIKit

/// Unified carousel view for workout completion and sharing
/// Replaces both WorkoutCompletedView and ShareWorkoutView
struct WorkoutShareCarouselView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \Workout.date, order: .reverse) private var allWorkouts: [Workout]
    
    @State private var viewModel: WorkoutShareCarouselViewModel
    @State private var themeManager = ThemeManager.shared
    @State private var settingsManager = SettingsManager.shared
    
    @State private var sharePayload: ActivitySharePayload?
    @State private var showingShareError = false
    
    /// Whether this is shown after completing a workout (vs just sharing)
    let isCompletionFlow: Bool
    let onDismiss: (() -> Void)?
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    private var primaryBestEffort: RankedBestEffort? {
        BestEffortRankingBuilder.primaryEffort(for: viewModel.workout, from: allWorkouts)
    }
    
    // MARK: - Initializers
    
    /// Initialize for workout completion flow
    init(workout: Workout, workoutCount: Int, onDismiss: @escaping () -> Void) {
        _viewModel = State(initialValue: WorkoutShareCarouselViewModel(workout: workout, workoutCount: workoutCount))
        self.isCompletionFlow = true
        self.onDismiss = onDismiss
    }
    
    /// Initialize for share flow (from workout detail)
    init(workout: Workout, liveClimbRank: Int? = nil, liveClimbRankTotal: Int? = nil) {
        _viewModel = State(initialValue: WorkoutShareCarouselViewModel(
            workout: workout,
            liveClimbRank: liveClimbRank,
            liveClimbRankTotal: liveClimbRankTotal
        ))
        self.isCompletionFlow = false
        self.onDismiss = nil
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header for completion flow
                if isCompletionFlow {
                    completionHeader
                }
                
                Spacer(minLength: 8)
                
                // Card carousel
                cardCarousel
                
                // Page indicator
                if viewModel.availableCards.count > 1 {
                    pageIndicator
                        .padding(.top, 12)
                }
                
                // Share prompt text
                Text("Share workout - Logged with Ascend")
                    .font(.montserratMedium(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
                    .padding(.top, 16)
                
                // Action buttons
                actionButtonsRow
                    .padding(.top, 16)
                    .padding(.horizontal, 20)
                
                Spacer(minLength: 16)
                
                // Done button (only in completion flow)
                if isCompletionFlow {
                    doneButton
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }
            }
            .padding(.top, isCompletionFlow ? 0 : 20)
            .navigationTitle(isCompletionFlow ? "" : "Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isCompletionFlow {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                        .foregroundStyle(.accent)
                    }
                }
            }
        }
        .themedBackground()
        .sheet(item: $sharePayload) { payload in
            ActivityView(
                activityItems: payload.items,
                excludedActivityTypes: payload.excludedTypes,
                completion: { _, completed, _, _ in
                    guard let climb = payload.analyticsClimb else { return }
                    TelemetryManager.shared.track(
                        LiveClimbAnalyticsEvent.shareActivityCompleted(
                            climb: climb,
                            surface: .systemSheet,
                            cardType: payload.analyticsCardType,
                            completed: completed
                        )
                    )
                }
            )
                .ignoresSafeArea()
        }
        .alert("Unable to Share", isPresented: $showingShareError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.shareErrorMessage ?? "An error occurred while sharing.")
        }
        .overlay(alignment: .top) {
            copyConfirmationOverlay
        }
        .task(id: viewModel.workout.id) {
            await viewModel.loadLiveClimbCompletionRankIfNeeded()
        }
        .onAppear {
            if isCompletionFlow {
                HapticsManager.shared.trigger(.heavyImpact)
                Task {
                    try await Task.sleep(for: .milliseconds(100))
                    HapticsManager.shared.trigger(.success)
                }
            }
        }
    }
    
    // MARK: - Completion Header
    
    private var completionHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Text("Nice work!")
                    .font(.montserratBold(size: 26))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                
                Text("🎉")
                    .font(.system(size: 28))
                    .background(
                        Circle()
                            .fill(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1))
                            .frame(width: 44, height: 44)
                    )
            }
            
            if let workoutCount = viewModel.workoutCount {
                Text("This is your \(workoutCount.ordinalString) workout")
                    .font(.montserratMedium(size: 15))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
            }
        }
        .padding(.top, 20)
    }
    
    // MARK: - Card Carousel
    
    private var cardCarousel: some View {
        TabView(selection: $viewModel.currentCardIndex) {
            ForEach(Array(viewModel.availableCards.enumerated()), id: \.element.id) { index, cardType in
                cardView(for: cardType)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(
            width: WorkoutShareCarouselViewModel.displayCardWidth + 24,
            height: WorkoutShareCarouselViewModel.displayCardHeight + 20
        )
    }
    
    @ViewBuilder
    private func cardView(for cardType: ShareCardType) -> some View {
        let shadowColor = effectiveColorScheme == .dark ? Color.black.opacity(0.3) : Color.black.opacity(0.1)

        switch cardType {
        case .poster, .liveClimb:
            viewModel.cardView(
                for: cardType,
                measurementSystem: settingsManager.measurementSystem,
                stepHeight: settingsManager.stepHeight,
                preferredMetric: settingsManager.preferredWorkoutMetric,
                bestEffort: primaryBestEffort
            )
            .frame(
                width: WorkoutShareCarouselViewModel.displayCardWidth,
                height: WorkoutShareCarouselViewModel.displayCardHeight
            )
            .shadow(color: shadowColor, radius: 20, x: 0, y: 10)
        }
    }
    
    // MARK: - Page Indicator
    
    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<viewModel.availableCards.count, id: \.self) { index in
                Circle()
                    .fill(index == viewModel.currentCardIndex ? .accent : (effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.3)))
                    .frame(width: 8, height: 8)
            }
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtonsRow: some View {
        HStack(spacing: 16) {
            // Instagram Stories
            CarouselActionButton(
                icon: "instagram-icon",
                label: "Stories",
                foregroundColor: actionForeground,
                backgroundColor: actionBackground,
                isAssetImage: true
            ) {
                shareToInstagramStories()
            }
            
            // More (Apple share sheet)
            CarouselActionButton(
                icon: "square.and.arrow.up",
                label: "More",
                foregroundColor: actionForeground,
                backgroundColor: actionBackground
            ) {
                shareViaSystemSheet()
            }
            
            // Copy Text
            CarouselActionButton(
                icon: "doc.on.doc",
                label: "Copy Text",
                foregroundColor: actionForeground,
                backgroundColor: actionBackground
            ) {
                trackLiveClimbShareAction(.copyText)
                viewModel.copyShareText(
                    measurementSystem: settingsManager.measurementSystem,
                    stepHeight: settingsManager.stepHeight,
                    preferredMetric: settingsManager.preferredWorkoutMetric,
                    bestEffort: primaryBestEffort
                )
            }
            
            // Twitter/X
            CarouselActionButton(
                icon: "x-icon",
                label: "X",
                foregroundColor: .white,
                backgroundColor: .black,
                isAssetImage: true
            ) {
                shareToTwitter()
            }

            // Strava Sync (only shown when connected, auto-sync off, and not already synced)
            if viewModel.shouldShowStravaSyncButton {
                StravaActionButton(
                    syncState: viewModel.stravaSyncState,
                    foregroundColor: actionForeground,
                    backgroundColor: actionBackground
                ) {
                    trackLiveClimbShareAction(.strava)
                    viewModel.syncToStrava(preferredMetric: settingsManager.preferredWorkoutMetric)
                }
            }
        }
    }
    
    private var actionForeground: Color {
        effectiveColorScheme == .dark ? .white : .black
    }
    
    private var actionBackground: Color {
        effectiveColorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
    }
    
    // MARK: - Done Button

    private var doneButton: some View {
        Button(action: {
            // Check if we should prompt for a rating
            if let workoutCount = viewModel.workoutCount {
                AppStoreRatingManager.shared.checkAndRequestReviewIfNeeded(currentWorkoutCount: workoutCount)
            }

            onDismiss?()
        }) {
            Text("Done")
                .font(.montserratSemiBold(size: 16))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.accent)
                )
        }
    }
    
    // MARK: - Copy Confirmation
    
    private var copyConfirmationOverlay: some View {
        Group {
            if let text = viewModel.copyConfirmationText {
                Text(text)
                    .font(.montserratSemiBold(size: 14))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.8))
                    )
                    .foregroundStyle(.white)
                    .padding(.top, 60)
                    .transition(.opacity.combined(with: .scale))
            }
        }
    }
    
    // MARK: - Share Actions
    
    private func shareViaSystemSheet() {
        trackLiveClimbShareAction(.systemSheet)

        guard let image = viewModel.renderCurrentCard(
            measurementSystem: settingsManager.measurementSystem,
            stepHeight: settingsManager.stepHeight,
            preferredMetric: settingsManager.preferredWorkoutMetric,
            bestEffort: primaryBestEffort
        ) else {
            viewModel.shareErrorMessage = "We couldn't render the card. Please try again."
            showingShareError = true
            return
        }
        
        var items: [Any] = [image]
        let text = viewModel.shareText(
            measurementSystem: settingsManager.measurementSystem,
            stepHeight: settingsManager.stepHeight,
            preferredMetric: settingsManager.preferredWorkoutMetric,
            bestEffort: primaryBestEffort
        )
        items.append(ShareTextActivityItemSource(text: text))
        
        sharePayload = ActivitySharePayload(
            items: items,
            analyticsClimb: liveClimbAnalyticsClimb,
            analyticsCardType: currentShareCardAnalyticsType
        )
    }
    
    private func shareToInstagramStories() {
        trackLiveClimbShareAction(.instagramStories)

        guard let image = viewModel.renderCurrentCard(
            measurementSystem: settingsManager.measurementSystem,
            stepHeight: settingsManager.stepHeight,
            preferredMetric: settingsManager.preferredWorkoutMetric,
            bestEffort: primaryBestEffort
        ) else {
            viewModel.shareErrorMessage = "We couldn't render the card. Please try again."
            showingShareError = true
            return
        }
        
        // Facebook App ID is required for Instagram Stories sharing (as of January 2023)
        guard let facebookAppID = Bundle.main.object(forInfoDictionaryKey: "FacebookAppID") as? String,
              !facebookAppID.isEmpty else {
            viewModel.shareErrorMessage = "Instagram sharing is not configured. Missing Facebook App ID."
            showingShareError = true
            return
        }

        guard let instagramURL = URL(string: "instagram-stories://share?source_application=\(facebookAppID)"),
              UIApplication.shared.canOpenURL(instagramURL) else {
            viewModel.shareErrorMessage = "Instagram is not installed on this device."
            showingShareError = true
            return
        }

        guard let imageData = image.pngData() else {
            viewModel.shareErrorMessage = "We couldn't process the image. Please try again."
            showingShareError = true
            return
        }

        let pasteboardItems: [[String: Any]] = [[
            "com.instagram.sharedSticker.stickerImage": imageData,
            "com.instagram.sharedSticker.backgroundTopColor": "#000000",
            "com.instagram.sharedSticker.backgroundBottomColor": "#000000"
        ]]

        let pasteboardOptions: [UIPasteboard.OptionsKey: Any] = [
            .expirationDate: Date().addingTimeInterval(60 * 5)
        ]

        UIPasteboard.general.setItems(pasteboardItems, options: pasteboardOptions)
        UIApplication.shared.open(instagramURL, options: [:], completionHandler: nil)
    }
    
    private func shareToTwitter() {
        trackLiveClimbShareAction(.x)

        let text = viewModel.shareText(
            measurementSystem: settingsManager.measurementSystem,
            stepHeight: settingsManager.stepHeight,
            preferredMetric: settingsManager.preferredWorkoutMetric,
            bestEffort: primaryBestEffort
        )

        let encodedText = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        // Try X/Twitter app first
        if let twitterAppURL = URL(string: "twitter://post?message=\(encodedText)"),
           UIApplication.shared.canOpenURL(URL(string: "twitter://")!) {
            UIApplication.shared.open(twitterAppURL, options: [:], completionHandler: nil)
        } else {
            // Fall back to web intent
            if let webURL = URL(string: "https://x.com/intent/tweet?text=\(encodedText)") {
                UIApplication.shared.open(webURL, options: [:], completionHandler: nil)
            }
        }
    }

    private var liveClimbAnalyticsClimb: Climb? {
        viewModel.availableCards.compactMap { cardType -> Climb? in
            if case .liveClimb(let climb) = cardType {
                return climb
            }
            return nil
        }.first
    }

    private var currentShareCardAnalyticsType: LiveClimbAnalyticsEvent.ShareCardAnalyticsType {
        switch viewModel.currentCardType {
        case .liveClimb:
            return .liveClimb
        case .poster:
            return .poster
        }
    }

    private func trackLiveClimbShareAction(_ surface: LiveClimbAnalyticsEvent.ShareSurface) {
        guard let climb = liveClimbAnalyticsClimb else { return }
        TelemetryManager.shared.track(
            LiveClimbAnalyticsEvent.shareActionTapped(
                climb: climb,
                surface: surface,
                cardType: currentShareCardAnalyticsType
            )
        )
    }
}

// MARK: - Action Button Component

private struct CarouselActionButton: View {
    private enum Metrics {
        static let circleSize: CGFloat = 56
        static let assetIconSize: CGFloat = 21
        static let systemIconSize: CGFloat = 20
    }

    let icon: String
    let label: String
    let foregroundColor: Color
    let backgroundColor: Color
    var isDisabled: Bool = false
    var isAssetImage: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(backgroundColor)
                        .frame(width: Metrics.circleSize, height: Metrics.circleSize)

                    if isAssetImage {
                        Image(icon)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: Metrics.assetIconSize, height: Metrics.assetIconSize)
                            .foregroundStyle(foregroundColor)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: Metrics.systemIconSize, weight: .semibold))
                            .foregroundStyle(foregroundColor)
                    }
                }
                
                Text(label)
                    .font(.montserratMedium(size: 10))
                    .foregroundStyle(foregroundColor.opacity(isDisabled ? 0.4 : 1))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
    }
}

// MARK: - Strava Action Button

private struct StravaActionButton: View {
    private enum Metrics {
        static let circleSize: CGFloat = 56
        static let stravaIconSize: CGFloat = 23
        static let checkmarkSize: CGFloat = 20
        static let errorSize: CGFloat = 18
    }

    let syncState: WorkoutShareCarouselViewModel.StravaSyncState
    let foregroundColor: Color
    let backgroundColor: Color
    let action: () -> Void

    private let stravaOrange = Color(red: 252/255, green: 76/255, blue: 2/255)

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(circleBackground)
                        .frame(width: Metrics.circleSize, height: Metrics.circleSize)

                    content
                }

                Text(label)
                    .font(.montserratMedium(size: 10))
                    .foregroundStyle(foregroundColor)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    @ViewBuilder
    private var content: some View {
        switch syncState {
        case .idle:
            Image("strava-icon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: Metrics.stravaIconSize, height: Metrics.stravaIconSize)
                .foregroundStyle(stravaOrange)
        case .syncing:
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: stravaOrange))
                .scaleEffect(0.9)
        case .synced:
            Image(systemName: "checkmark")
                .font(.system(size: Metrics.checkmarkSize, weight: .bold))
                .foregroundStyle(.green)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: Metrics.errorSize, weight: .semibold))
                .foregroundStyle(.red)
        }
    }

    private var circleBackground: Color {
        switch syncState {
        case .synced:
            return .green.opacity(0.15)
        case .error:
            return .red.opacity(0.15)
        default:
            return backgroundColor
        }
    }

    private var label: String {
        switch syncState {
        case .idle:
            return "Strava"
        case .syncing:
            return "Syncing..."
        case .synced:
            return "Synced!"
        case .error:
            return "Failed"
        }
    }

    private var isDisabled: Bool {
        switch syncState {
        case .idle:
            return false
        case .syncing, .synced, .error:
            return true
        }
    }
}

// MARK: - Supporting Types

private struct ActivitySharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
    var excludedTypes: [UIActivity.ActivityType]? = nil
    var analyticsClimb: Climb?
    var analyticsCardType: LiveClimbAnalyticsEvent.ShareCardAnalyticsType = .poster
}

// MARK: - Int Extension for Ordinals

private extension Int {
    var ordinalString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}

// MARK: - Previews

#Preview("Completion Flow") {
    WorkoutShareCarouselView(
        workout: Workout(
            name: "Morning Stair Climb",
            duration: 1800,
            steps: 2500,
            floors: 156,
            stepsPerFloor: 16,
            avgHeartRate: 145,
            maxHeartRate: 165,
            caloriesBurned: 320
        ),
        workoutCount: 535,
        onDismiss: {}
    )
}

#Preview("Share Flow") {
    WorkoutShareCarouselView(
        workout: Workout(
            name: "Evening Session",
            duration: 2400,
            steps: 3200,
            floors: 200,
            stepsPerFloor: 16,
            caloriesBurned: 450
        )
    )
}

#Preview("With Photo - Dark") {
    WorkoutShareCarouselView(
        workout: Workout(
            name: "Upper",
            duration: 5040, // 1h 24min
            steps: 1200,
            floors: 75,
            stepsPerFloor: 16
        ),
        workoutCount: 535,
        onDismiss: {}
    )
    .preferredColorScheme(.dark)
}

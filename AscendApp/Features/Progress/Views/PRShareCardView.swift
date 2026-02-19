//
//  PRShareCardView.swift
//  AscendApp
//
//  Created by Claude on 2/19/26.
//

import SwiftUI

/// A shareable card displaying a personal record achievement
struct PRShareCardView: View {
    let effort: BestEffort
    let previousValue: String?
    let displayName: String
    
    // Card dimensions for Instagram Stories
    private let cardWidth: CGFloat = 390
    private let cardHeight: CGFloat = 520
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.2),
                    Color(red: 0.05, green: 0.15, blue: 0.25)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Content
            VStack(spacing: 0) {
                Spacer()
                
                // NEW PR Badge
                HStack(spacing: 8) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 16))
                    Text("NEW PERSONAL RECORD")
                        .font(.montserratBold(size: 14))
                        .tracking(2)
                }
                .foregroundStyle(.yellow)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.yellow.opacity(0.2))
                )
                
                Spacer()
                    .frame(height: 32)
                
                // Icon
                Image(systemName: effort.iconName)
                    .font(.system(size: 60, weight: .medium))
                    .foregroundStyle(.accent)
                    .padding(.bottom, 16)
                
                // PR Type
                Text(effort.title)
                    .font(.montserratSemiBold(size: 18))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                
                Spacer()
                    .frame(height: 20)
                
                // Value
                Text(effort.valueText)
                    .font(.montserratBold(size: 48))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                
                // Previous value comparison
                if let previous = previousValue {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 14))
                        Text("Previous: \(previous)")
                            .font(.montserratMedium(size: 14))
                    }
                    .foregroundStyle(.green)
                    .padding(.top, 8)
                }
                
                Spacer()
                    .frame(height: 20)
                
                // Date
                Text(formattedDate)
                    .font(.montserratMedium(size: 14))
                    .foregroundStyle(.white.opacity(0.6))
                
                Spacer()
                
                // Footer with branding
                HStack {
                    Text(displayName)
                        .font(.montserratMedium(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                    
                    Spacer()
                    
                    HStack(spacing: 6) {
                        Image("AscendLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 18)
                        Text("Ascend")
                            .font(.montserratSemiBold(size: 13))
                    }
                    .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: effort.date)
    }
}

// MARK: - Image Rendering Extension

extension PRShareCardView {
    /// Render the card as a UIImage for sharing
    @MainActor
    func renderAsImage() -> UIImage? {
        let renderer = ImageRenderer(content: self)
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
    }
}

// MARK: - PR Share Sheet

struct PRShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    let effort: BestEffort
    let previousValue: String?
    let displayName: String
    
    @State private var themeManager = ThemeManager.shared
    @State private var isSharing = false
    @State private var shareImage: UIImage?
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                
                // Preview card
                PRShareCardView(
                    effort: effort,
                    previousValue: previousValue,
                    displayName: displayName
                )
                .scaleEffect(0.85)
                
                Spacer()
                
                // Share button
                Button {
                    shareCard()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                    }
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.accentColor)
                    )
                }
                .disabled(isSharing)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .themedBackground()
            .navigationTitle("Share PR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.accent)
                }
            }
        }
    }
    
    private func shareCard() {
        isSharing = true
        
        let cardView = PRShareCardView(
            effort: effort,
            previousValue: previousValue,
            displayName: displayName
        )
        
        guard let image = cardView.renderAsImage() else {
            isSharing = false
            return
        }
        
        let activityVC = UIActivityViewController(
            activityItems: [image],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            // Find the topmost presented view controller
            var topController = rootVC
            while let presented = topController.presentedViewController {
                topController = presented
            }
            
            // For iPad
            activityVC.popoverPresentationController?.sourceView = topController.view
            activityVC.popoverPresentationController?.sourceRect = CGRect(
                x: topController.view.bounds.midX,
                y: topController.view.bounds.midY,
                width: 0,
                height: 0
            )
            
            topController.present(activityVC, animated: true) {
                isSharing = false
            }
        } else {
            isSharing = false
        }
    }
}

#Preview {
    let sampleWorkout = Workout(
        name: "Morning Climb",
        date: Date(),
        duration: 45 * 60,
        steps: 5200,
        floors: 40,
        stepsPerFloor: 16,
        avgHeartRate: 135,
        maxHeartRate: 168,
        caloriesBurned: 520
    )
    
    let effort = BestEffort(
        type: .mostSteps,
        title: "Most Steps in a Workout",
        valueText: "5,200 steps",
        detailText: "Feb 19, 2026",
        date: Date(),
        workout: sampleWorkout,
        iconName: "figure.stairs"
    )
    
    return PRShareSheet(
        effort: effort,
        previousValue: "4,800 steps",
        displayName: "Tyler"
    )
}

#Preview("Card Only") {
    let sampleWorkout = Workout(
        name: "Morning Climb",
        date: Date(),
        duration: 45 * 60,
        steps: 5200,
        floors: 40,
        stepsPerFloor: 16
    )
    
    let effort = BestEffort(
        type: .highestStepsPerMinute,
        title: "Highest Steps per Minute",
        valueText: "115 / min",
        detailText: "Feb 19, 2026",
        date: Date(),
        workout: sampleWorkout,
        iconName: "speedometer"
    )
    
    return PRShareCardView(
        effort: effort,
        previousValue: "108 / min",
        displayName: "Tyler"
    )
    .padding()
    .background(Color.gray)
}

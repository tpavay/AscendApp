//
//  OnboardingFlow.swift
//  AscendApp
//
//  A reusable framework for multi-page onboarding flows.
//  Use this to create consistent onboarding experiences across the app.
//

import SwiftUI

// MARK: - Onboarding Page Protocol

/// Protocol for individual onboarding pages
protocol OnboardingPageContent: View {
    var canProceed: Bool { get }
}

// MARK: - Onboarding Page Model

/// A single page in an onboarding flow
struct OnboardingPage<Content: View>: Identifiable {
    let id = UUID()
    let content: Content
    let canProceed: () -> Bool

    init(@ViewBuilder content: () -> Content, canProceed: @escaping () -> Bool = { true }) {
        self.content = content()
        self.canProceed = canProceed
    }
}

// MARK: - Onboarding Flow View

/// A reusable container for multi-page onboarding flows
struct OnboardingFlow<Content: View>: View {
    let pages: [OnboardingPage<Content>]
    let onComplete: () -> Void
    let showSkipButton: Bool
    let primaryButtonTitle: String
    let completeButtonTitle: String

    @State private var currentPageIndex = 0
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    init(
        pages: [OnboardingPage<Content>],
        showSkipButton: Bool = false,
        primaryButtonTitle: String = "Continue",
        completeButtonTitle: String = "Get Started",
        onComplete: @escaping () -> Void
    ) {
        self.pages = pages
        self.showSkipButton = showSkipButton
        self.primaryButtonTitle = primaryButtonTitle
        self.completeButtonTitle = completeButtonTitle
        self.onComplete = onComplete
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator (if multiple pages)
            if pages.count > 1 {
                progressIndicator
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
            }

            // Current page content
            pages[currentPageIndex].content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Navigation buttons
            navigationButtons
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
        }
        .themedBackground()
    }

    // MARK: - Progress Indicator

    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<pages.count, id: \.self) { index in
                Capsule()
                    .fill(index <= currentPageIndex ? Color.accent : Color.gray.opacity(0.3))
                    .frame(height: 4)
            }
        }
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        VStack(spacing: 12) {
            // Primary button (Continue / Get Started)
            Button {
                if currentPageIndex == pages.count - 1 {
                    onComplete()
                } else {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        currentPageIndex += 1
                    }
                }
            } label: {
                Text(currentPageIndex == pages.count - 1 ? completeButtonTitle : primaryButtonTitle)
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 55)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(pages[currentPageIndex].canProceed() ? Color.accent : Color.gray)
                    )
            }
            .disabled(!pages[currentPageIndex].canProceed())

            // Back button (if not first page)
            if currentPageIndex > 0 {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        currentPageIndex -= 1
                    }
                } label: {
                    Text("Back")
                        .font(.montserratMedium(size: 14))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                }
            }

            // Skip button (optional)
            if showSkipButton && currentPageIndex < pages.count - 1 {
                Button {
                    onComplete()
                } label: {
                    Text("Skip")
                        .font(.montserratMedium(size: 14))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray.opacity(0.7))
                }
            }
        }
    }
}

// MARK: - Single Page Onboarding Convenience

/// A simpler onboarding view for single-page flows
struct SinglePageOnboarding<Content: View>: View {
    let content: Content
    let buttonTitle: String
    let canProceed: Bool
    let onComplete: () -> Void

    init(
        buttonTitle: String = "Get Started",
        canProceed: Bool = true,
        onComplete: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.buttonTitle = buttonTitle
        self.canProceed = canProceed
        self.onComplete = onComplete
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                onComplete()
            } label: {
                Text(buttonTitle)
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 55)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(canProceed ? Color.accent : Color.gray)
                    )
            }
            .disabled(!canProceed)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .themedBackground()
    }
}

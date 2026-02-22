//
//  PrivacyPolicyView.swift
//  AscendApp
//
//  Created by Claude on 2/22/26.
//

import SwiftUI

/// Configuration for legal documents
enum LegalDocuments {
    /// Privacy Policy URL - Update this when you host the policy
    /// Options:
    /// - GitHub Pages: https://yourusername.github.io/ascend-legal/privacy
    /// - Your domain: https://ascendapp.com/privacy
    /// - Notion public page: https://notion.so/your-privacy-policy
    static let privacyPolicyURL = URL(string: "https://ascendapp.com/privacy")
    
    /// Terms of Service URL
    static let termsOfServiceURL = URL(string: "https://ascendapp.com/terms")
    
    /// Last updated date for fallback content
    static let lastUpdated = "February 22, 2026"
    
    /// Company info placeholders - Replace with real info after LLC formation
    static let companyName = "[Company Name]"  // e.g., "Ascend Fitness LLC"
    static let supportEmail = "support@ascendapp.com"
}

struct PrivacyPolicyView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var isLoading = true
    @State private var loadError: Error?
    @State private var showFallback = false
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    var body: some View {
        Group {
            if let url = LegalDocuments.privacyPolicyURL, !showFallback {
                webContent(url: url)
            } else {
                fallbackContent
            }
        }
        .themedBackground()
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Web Content
    
    @ViewBuilder
    private func webContent(url: URL) -> some View {
        ZStack {
            WebView(url: url, isLoading: $isLoading, error: $loadError)
                .onChange(of: loadError) { _, error in
                    if error != nil {
                        showFallback = true
                    }
                }
            
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
            }
        }
    }
    
    // MARK: - Fallback Content
    
    private var fallbackContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                
                ForEach(PrivacySection.allSections, id: \.title) { section in
                    policySection(title: section.title, content: section.content)
                }
                
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Privacy Policy")
                .font(.montserratBold(size: 28))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
            
            Text("Last updated: \(LegalDocuments.lastUpdated)")
                .font(.montserratRegular(size: 14))
                .foregroundStyle(.gray)
            
            if showFallback {
                Text("Showing offline version")
                    .font(.montserratRegular(size: 12))
                    .foregroundStyle(.orange)
                    .padding(.top, 4)
            }
        }
        .padding(.top, 8)
    }
    
    private func policySection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.montserratSemiBold(size: 20))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
            
            Text(LocalizedStringKey(content))
                .font(.montserratRegular(size: 15))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.85) : .black.opacity(0.8))
                .lineSpacing(4)
        }
    }
}

// MARK: - Privacy Sections (Fallback Content)

private struct PrivacySection {
    let title: String
    let content: String
    
    static let allSections: [PrivacySection] = [
        PrivacySection(
            title: "1. Introduction",
            content: """
            \(LegalDocuments.companyName) ("Ascend," "we," "our," or "us") is committed to protecting your privacy. This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our stairstepper workout tracking application.
            
            By using the Service, you consent to the practices described in this Privacy Policy.
            """
        ),
        PrivacySection(
            title: "2. Information We Collect",
            content: """
            **Information You Provide:**
            • Account information (email via Sign in with Apple)
            • Workout data (steps, floors, duration, heart rate, calories)
            • Photos and videos attached to workouts
            • Profile information and preferences
            
            **Information Collected Automatically:**
            • Device information and identifiers
            • Usage data and analytics
            • Crash reports and performance data
            
            **Third-Party Sources:**
            • Apple HealthKit data (with your permission)
            • Strava integration (if connected)
            """
        ),
        PrivacySection(
            title: "3. Apple HealthKit",
            content: """
            With your permission, Ascend may read and write health data including heart rate, calories, workouts, and flights climbed.
            
            **We will NOT:**
            • Use HealthKit data for advertising
            • Sell HealthKit data to third parties
            • Share HealthKit data for marketing purposes
            
            **We will:**
            • Store HealthKit data securely with encryption
            • Only use data to provide the Service
            • Follow Apple's HealthKit guidelines
            
            You can revoke access anytime in Settings → Health → Data Access.
            """
        ),
        PrivacySection(
            title: "4. How We Use Your Information",
            content: """
            • To track and display your workout progress
            • To calculate personal records and statistics
            • To sync your data across devices
            • To provide leaderboard functionality (optional)
            • To improve the app experience
            • To send important service updates
            """
        ),
        PrivacySection(
            title: "5. Data Sharing",
            content: """
            **We do not sell your personal information.**
            
            We may share data with:
            • **Service providers**: Firebase (storage), Apple (authentication)
            • **At your request**: Strava (workout sync)
            • **Leaderboards**: If you opt in, your stats may be visible
            • **Legal requirements**: If required by law
            
            Third-party services have their own privacy policies.
            """
        ),
        PrivacySection(
            title: "6. Data Security",
            content: """
            We implement appropriate security measures:
            • Encryption in transit (TLS/SSL)
            • Encryption at rest
            • Secure authentication via Sign in with Apple
            • Regular security monitoring
            
            No system is 100% secure, but we strive to protect your data.
            """
        ),
        PrivacySection(
            title: "7. Your Rights",
            content: """
            You have the right to:
            • **Access**: View your data in the app
            • **Export**: Export your workout data
            • **Delete**: Delete your account and all data
            • **Opt-out**: Disable leaderboards, revoke HealthKit access
            
            To delete your account: Settings → Account → Delete Account
            """
        ),
        PrivacySection(
            title: "8. Data Retention",
            content: """
            We retain your data while your account is active. After deletion:
            • Data is removed from servers within 30 days
            • Some data may be retained for legal compliance
            • Anonymized analytics may be retained indefinitely
            """
        ),
        PrivacySection(
            title: "9. Children's Privacy",
            content: """
            Ascend is not intended for children under 13. We do not knowingly collect information from children under 13. If you believe we have collected such information, please contact us immediately.
            """
        ),
        PrivacySection(
            title: "10. Changes to This Policy",
            content: """
            We may update this Privacy Policy from time to time. We will notify you of material changes by updating the "Last Updated" date and through in-app notifications for significant changes.
            """
        ),
        PrivacySection(
            title: "11. Contact Us",
            content: """
            Questions about this Privacy Policy? Contact us at:
            
            **Email:** \(LegalDocuments.supportEmail)
            """
        )
    ]
}

// MARK: - Previews

#Preview {
    NavigationStack {
        PrivacyPolicyView()
    }
}

#Preview("Dark Mode") {
    NavigationStack {
        PrivacyPolicyView()
            .preferredColorScheme(.dark)
    }
}

#Preview("Fallback Content") {
    NavigationStack {
        PrivacyPolicyView()
    }
}

//
//  PrivacyPolicyView.swift
//  AscendApp
//
//  Created by Claude on 2/19/26.
//

import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Privacy Policy")
                        .font(.montserratBold(size: 28))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    
                    Text("Last updated: February 19, 2026")
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(.gray)
                }
                .padding(.top, 8)
                
                // Introduction
                policySection(
                    title: "Introduction",
                    content: "Ascend (\"we\", \"our\", or \"us\") is committed to protecting your privacy. This Privacy Policy explains how we collect, use, and safeguard your information when you use our stairstepper workout tracking application."
                )
                
                // Information We Collect
                policySection(
                    title: "Information We Collect",
                    content: """
                    We collect the following types of information:
                    
                    • **Workout Data**: Steps climbed, floors climbed, duration, heart rate, calories burned, and other fitness metrics you log.
                    
                    • **Health Data**: With your permission, we access HealthKit data including heart rate and workout information.
                    
                    • **Account Information**: Email address and display name when you create an account.
                    
                    • **Photos and Videos**: Media you attach to your workouts, stored securely in the cloud.
                    
                    • **Device Information**: Basic device identifiers for app functionality and crash reporting.
                    """
                )
                
                // How We Use Your Information
                policySection(
                    title: "How We Use Your Information",
                    content: """
                    Your information is used to:
                    
                    • Track and display your workout progress
                    • Calculate personal records and statistics
                    • Sync your data across devices
                    • Provide leaderboard functionality (optional)
                    • Improve the app experience
                    • Send important service updates
                    """
                )
                
                // Data Storage and Security
                policySection(
                    title: "Data Storage & Security",
                    content: """
                    • Your workout data is stored locally on your device and synced to secure cloud servers (Firebase).
                    
                    • Photos and videos are encrypted in transit and at rest.
                    
                    • We use industry-standard security measures to protect your data.
                    
                    • We do not sell your personal information to third parties.
                    """
                )
                
                // Third-Party Services
                policySection(
                    title: "Third-Party Services",
                    content: """
                    Ascend may integrate with third-party services:
                    
                    • **Apple HealthKit**: To read/write health and workout data (with your permission).
                    
                    • **Strava**: To sync workouts to your Strava account (optional).
                    
                    • **Firebase**: For secure cloud storage and authentication.
                    
                    These services have their own privacy policies that govern their use of your data.
                    """
                )
                
                // Your Rights
                policySection(
                    title: "Your Rights",
                    content: """
                    You have the right to:
                    
                    • Access your personal data
                    • Export your workout data
                    • Delete your account and all associated data
                    • Opt out of optional features like leaderboards
                    • Revoke HealthKit permissions at any time
                    """
                )
                
                // Data Retention
                policySection(
                    title: "Data Retention",
                    content: "We retain your data for as long as your account is active. If you delete your account, your data will be permanently removed from our servers within 30 days."
                )
                
                // Children's Privacy
                policySection(
                    title: "Children's Privacy",
                    content: "Ascend is not intended for children under 13. We do not knowingly collect personal information from children under 13."
                )
                
                // Changes to This Policy
                policySection(
                    title: "Changes to This Policy",
                    content: "We may update this Privacy Policy from time to time. We will notify you of any changes by posting the new Privacy Policy in the app and updating the \"Last updated\" date."
                )
                
                // Contact Us
                policySection(
                    title: "Contact Us",
                    content: "If you have questions about this Privacy Policy, please contact us through the app's Contact Us feature or email us at privacy@ascendapp.com."
                )
                
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .themedBackground()
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
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

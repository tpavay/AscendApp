//
//  WorkoutEntrySelectionView.swift
//  AscendApp
//
//  Created by Claude on 12/8/25.
//

import SwiftUI

/// Selection sheet for choosing how to log a workout
struct WorkoutEntrySelectionView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    let onManualEntry: () -> Void
    let onScanConsole: () -> Void

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text("Add Workout")
                .font(.montserratBold(size: 20))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                .padding(.top, 8)

            VStack(spacing: 12) {
                // Manual Entry option
                Button {
                    onManualEntry()
                } label: {
                    SelectionRow(
                        icon: "pencil.line",
                        title: "Log Manually",
                        subtitle: "Enter workout details yourself",
                        effectiveColorScheme: effectiveColorScheme
                    )
                }

                // Scan Console option
                Button {
                    onScanConsole()
                } label: {
                    SelectionRow(
                        icon: "camera.viewfinder",
                        title: "Scan Console",
                        subtitle: "Take a photo of your machine's display",
                        effectiveColorScheme: effectiveColorScheme,
                        isAccent: true
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(effectiveColorScheme == .dark ? Color.jet : Color.white)
    }
}

// MARK: - Selection Row

struct SelectionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let effectiveColorScheme: ColorScheme
    var isAccent: Bool = false

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(isAccent ? .accent : (effectiveColorScheme == .dark ? .white : .black))
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(isAccent ? .accent.opacity(0.15) : (effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1)))
                )

            // Text
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                Text(subtitle)
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
            }

            Spacer()

            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.4) : .gray.opacity(0.5))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.3) : .gray.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isAccent ? .accent.opacity(0.3) : .clear, lineWidth: 1)
        )
    }
}

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
    let onImportWorkouts: () -> Void
    let pendingImportCount: Int

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        AppSheetScaffold(title: "Add Workout", layout: .menu) {
            VStack(spacing: 10) {
                Button {
                    onManualEntry()
                } label: {
                    AppSheetOptionRow(
                        systemImage: "pencil.line",
                        title: "Log Manually",
                        iconTint: effectiveColorScheme == .dark ? .white : .black,
                        trailingSymbol: "chevron.right"
                    )
                }
                .buttonStyle(.plain)

                Button {
                    onImportWorkouts()
                } label: {
                    AppSheetOptionRow(
                        assetImage: "appleHealth-icon",
                        title: "Import or Review",
                        badgeCount: pendingImportCount,
                        trailingSymbol: "chevron.right"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

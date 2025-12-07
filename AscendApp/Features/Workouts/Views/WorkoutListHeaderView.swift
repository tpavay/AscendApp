//
//  WorkoutListHeaderView.swift
//  AscendApp
//
//  Created by Codex on 3/14/24.
//

import SwiftUI

struct WorkoutListHeaderView<SearchTrigger: View>: View {
    let isInDeleteMode: Bool
    let totalCount: Int
    let selectedCount: Int
    let allSelected: Bool
    let effectiveColorScheme: ColorScheme
    let pendingImportCount: Int
    let canDelete: Bool
    let onToggleSelectAll: () -> Void
    let onCancelDelete: () -> Void
    let onDeleteTapped: () -> Void
    let onImportTapped: () -> Void
    let onEnterDeleteMode: () -> Void
    @ViewBuilder let searchTrigger: () -> SearchTrigger

    @State private var isSearchExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            headerRow
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, isSearchExpanded ? 12 : 16)

            // Expandable search trigger
            if isSearchExpanded && !isInDeleteMode && totalCount > 0 {
                searchTrigger()
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .move(edge: .top))
                    ))
            }

            Rectangle()
                .fill(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.2))
                .frame(height: 1)
        }
        .background(
            (effectiveColorScheme == .dark ? Color.jet : Color.white)
                .opacity(0.95)
        )
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            if isInDeleteMode {
                // Delete mode title and controls
                VStack(alignment: .leading, spacing: 4) {
                    Text("Select Workouts")
                        .font(.montserratBold(size: 18))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                    Button(action: onToggleSelectAll) {
                        Text(allSelected ? "Deselect All" : "Select All")
                            .font(.montserratMedium(size: 14))
                            .foregroundStyle(.accent)
                    }
                }

                Spacer()

                deleteModeControls
            } else {
                // Normal mode - compact header like leaderboard
                Text("Workouts")
                    .font(.montserratBold(size: 18))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                Spacer()

                if totalCount > 0 {
                    // Search button
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isSearchExpanded.toggle()
                        }
                        HapticsManager.shared.trigger(.lightImpact)
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    }

                    // Overflow menu
                    overflowMenu
                }
            }
        }
    }

    private var deleteModeControls: some View {
        HStack(spacing: 16) {
            Button("Cancel", action: onCancelDelete)
                .foregroundStyle(.accent)
                .font(.montserratMedium(size: 16))

            Button("Delete", action: onDeleteTapped)
                .foregroundStyle(canDelete ? .red : .gray)
                .font(.montserratMedium(size: 16))
                .disabled(!canDelete)
        }
    }

    private var overflowMenu: some View {
        Menu {
            Button(action: onImportTapped) {
                HStack {
                    Label("Import Workouts", systemImage: "square.and.arrow.down")
                    if pendingImportCount > 0 {
                        Text("(\(pendingImportCount))")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
            }

            Button(action: onEnterDeleteMode) {
                Label("Delete Workouts", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
        }
    }
}

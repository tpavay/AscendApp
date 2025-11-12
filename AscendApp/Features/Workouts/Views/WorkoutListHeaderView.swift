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
    
    var body: some View {
        VStack(spacing: 0) {
            headerRow
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 16)
            
            if !isInDeleteMode && totalCount > 0 {
                searchTrigger()
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
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
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(isInDeleteMode ? "Select Workouts" : "Workouts")
                    .font(.montserratBold(size: 32))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                
                if isInDeleteMode {
                    Button(action: onToggleSelectAll) {
                        Text(allSelected ? "Deselect All" : "Select All")
                            .font(.montserratMedium(size: 14))
                            .foregroundStyle(.accent)
                    }
                }
            }
            
            Spacer()
            
            if totalCount > 0 {
                if isInDeleteMode {
                    deleteModeControls
                } else {
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
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
    }
}

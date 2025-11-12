//
//  WorkoutListSearchTriggerView.swift
//  AscendApp
//
//  Created by Codex on 3/14/24.
//

import SwiftUI

struct WorkoutListSearchTriggerView<Destination: View>: View {
    @ObservedObject var filterState: WorkoutListFilterState
    let effectiveColorScheme: ColorScheme
    @ViewBuilder let destination: () -> Destination
    
    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.accent)
                
                Text(filterState.searchText.isEmpty ? "Search By Keyword" : filterState.searchText)
                    .font(.montserratMedium(size: 14))
                    .foregroundStyle(filterState.searchText.isEmpty ? .secondary : textColor)
                
                Spacer()
                
                if filterState.hasAdvancedFilters {
                    Text("Filters On")
                        .font(.montserratSemiBold(size: 12))
                        .foregroundStyle(.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(.accent.opacity(0.15))
                        )
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(effectiveColorScheme == .dark ? Color.white.opacity(0.08) : Color.gray.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(effectiveColorScheme == .dark ? Color.white.opacity(0.12) : Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var textColor: Color {
        effectiveColorScheme == .dark ? .white : .black
    }
}

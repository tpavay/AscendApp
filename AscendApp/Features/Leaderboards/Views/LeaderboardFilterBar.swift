//
//  LeaderboardFilterBar.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import SwiftUI

struct LeaderboardFilterBar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var searchText: String
    @Binding var selectedMetric: LeaderboardMetric
    @Binding var selectedTimeFrame: LeaderboardTimeFrame
    @FocusState private var isSearchFocused: Bool
    @State private var activeSheet: FilterSheet?

    private enum FilterSheet: Identifiable {
        case timeFrame
        case metric

        var id: String {
            switch self {
            case .timeFrame: return "timeFrame"
            case .metric: return "metric"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            searchField

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    FilterChipButton(
                        title: "Time Frame",
                        value: selectedTimeFrame.displayName
                    ) {
                        activeSheet = .timeFrame
                    }

                    FilterChipButton(
                        title: "Metric",
                        value: selectedMetric.displayName
                    ) {
                        activeSheet = .metric
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    isSearchFocused = false
                } label: {
                    Text("Done")
                        .font(.montserratSemiBold(size: 16))
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .timeFrame:
                LeaderboardSingleSelectSheet(
                    title: "Time Frame",
                    subtitle: "Choose which period to view.",
                    options: LeaderboardTimeFrame.allCases,
                    selectedOption: selectedTimeFrame,
                    displayName: { $0.displayName },
                    onSelect: { newSelection in
                        selectedTimeFrame = newSelection
                    },
                    detents: [.height(420)]
                )
            case .metric:
                LeaderboardSingleSelectSheet(
                    title: "Metric",
                    subtitle: "Choose the metric to rank competitors.",
                    options: LeaderboardMetric.allCases,
                    selectedOption: selectedMetric,
                    displayName: { $0.displayName },
                    onSelect: { newSelection in
                        selectedMetric = newSelection
                    },
                    detents: [.height(420)]
                )
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search for a player", text: $searchText)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .font(.montserratRegular(size: 15))
                .focused($isSearchFocused)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(searchBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(searchBorderColor, lineWidth: 1)
        )
    }

    private var searchBackgroundColor: Color {
        colorScheme == .dark ? Color("Jet") : Color.gray.opacity(0.08)
    }

    private var searchBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05)
    }
}

private struct FilterChipButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.montserratSemiBold(size: 11))
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.montserratMedium(size: 15))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? Color("Jet") : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.gray.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.05), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

private struct LeaderboardSingleSelectSheet<Option: Identifiable & Equatable>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let subtitle: String
    let options: [Option]
    let selectedOption: Option
    let displayName: (Option) -> String
    let onSelect: (Option) -> Void
    let detents: Set<PresentationDetent>

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.montserratBold(size: 20))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)

                Text(subtitle)
                    .font(.montserratRegular(size: 14))
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(options) { option in
                        Button {
                            onSelect(option)
                            dismiss()
                        } label: {
                            HStack {
                                Text(displayName(option))
                                    .font(.montserratMedium(size: 16))
                                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                                    .lineLimit(1)

                                Spacer()

                                Image(systemName: option == selectedOption ? "largecircle.fill.circle" : "circle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(option == selectedOption ? Color.accent : .secondary)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(colorScheme == .dark ? Color("Jet") : Color.gray.opacity(0.1))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .padding(.top, 32)
        .padding(.bottom, 12)
        .presentationDetents(detents)
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    LeaderboardFilterBar(
        searchText: .constant(""),
        selectedMetric: .constant(.steps),
        selectedTimeFrame: .constant(.weekly)
    )
    .padding()
    .themedBackground()
}

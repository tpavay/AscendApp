//
//  IntegrationManageToggleCard.swift
//  AscendApp
//
//  Created by Codex on 3/12/26.
//

import SwiftUI

struct IntegrationManageToggleCard: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var themeManager = ThemeManager.shared

    let title: String
    let subtitle: String?
    @Binding var isOn: Bool
    let isEnabled: Bool

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: systemColorScheme)
    }

    private var titleColor: Color {
        effectiveColorScheme == .dark ? .white : .black
    }

    private var subtitleColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.68) : .gray
    }

    var body: some View {
        VStack(alignment: .leading, spacing: subtitle == nil ? 0 : 8) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: subtitle == nil ? 0 : 4) {
                    Text(title)
                        .font(.montserratSemiBold(size: 16))
                        .foregroundStyle(titleColor)

                    if let subtitle {
                        Text(subtitle)
                            .font(.montserratRegular(size: 13))
                            .foregroundStyle(subtitleColor)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 12)

                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .tint(.accent)
                    .disabled(!isEnabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .appSheetCardStyle()
        .opacity(isEnabled ? 1 : 0.65)
    }
}

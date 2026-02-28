//
//  SelectionActionBar.swift
//  AscendApp
//
//  Created by Codex on 2/28/26.
//

import SwiftUI

struct SelectionActionBar: View {
    let effectiveColorScheme: ColorScheme
    let secondaryTitle: String
    let onSecondaryTapped: () -> Void
    let isSecondaryDisabled: Bool
    let primaryTitle: String
    let onPrimaryTapped: () -> Void
    let isPrimaryDisabled: Bool
    let primaryColor: Color

    init(
        effectiveColorScheme: ColorScheme,
        secondaryTitle: String,
        onSecondaryTapped: @escaping () -> Void,
        isSecondaryDisabled: Bool,
        primaryTitle: String,
        onPrimaryTapped: @escaping () -> Void,
        isPrimaryDisabled: Bool,
        primaryColor: Color = .accent
    ) {
        self.effectiveColorScheme = effectiveColorScheme
        self.secondaryTitle = secondaryTitle
        self.onSecondaryTapped = onSecondaryTapped
        self.isSecondaryDisabled = isSecondaryDisabled
        self.primaryTitle = primaryTitle
        self.onPrimaryTapped = onPrimaryTapped
        self.isPrimaryDisabled = isPrimaryDisabled
        self.primaryColor = primaryColor
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.2))
                .frame(height: 1)

            HStack(spacing: 10) {
                Button(action: onSecondaryTapped) {
                    Text(secondaryTitle)
                        .font(.montserratSemiBold(size: 15))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(effectiveColorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.06))
                        )
                }
                .disabled(isSecondaryDisabled)

                Button(action: onPrimaryTapped) {
                    Text(primaryTitle)
                        .font(.montserratSemiBold(size: 15))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(primaryColor)
                        )
                }
                .disabled(isPrimaryDisabled)
                .opacity(isPrimaryDisabled ? 0.45 : 1)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(effectiveColorScheme == .dark ? .black.opacity(0.95) : .white.opacity(0.97))
    }
}


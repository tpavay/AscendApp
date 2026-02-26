//
//  FormButton.swift
//  AscendApp
//
//  Reusable form button component for pickers, selectors, and actions
//

import SwiftUI

struct FormButton: View {
    let label: String
    let isRequired: Bool
    let icon: String?
    let value: String?
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    init(
        label: String,
        isRequired: Bool = false,
        icon: String? = nil,
        value: String? = nil,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.isRequired = isRequired
        self.icon = icon
        self.value = value
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.gray)
                        .frame(width: 24)
                }

                if let value = value, !value.isEmpty {
                    Text(value)
                        .font(.montserratRegular(size: 16))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                } else {
                    Text(displayLabel)
                        .font(.montserratRegular(size: 16))
                        .foregroundStyle(.gray)
                }

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.gray)
            }
            .padding(16)
            .background(fieldBackground)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var displayLabel: String {
        isRequired ? "\(label) *" : label
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(effectiveColorScheme == .dark ? .white.opacity(0.05) : .gray.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1)
            )
    }
}

#Preview {
    VStack(spacing: 16) {
        FormButton(
            label: "Select Date",
            isRequired: true,
            icon: "calendar",
            value: "Today at 5:34 AM",
            action: {}
        )

        FormButton(
            label: "Add effort rating",
            isRequired: false,
            value: nil,
            action: {}
        )

        FormButton(
            label: "Duration",
            isRequired: true,
            icon: "clock",
            value: "00:45:30",
            action: {}
        )
    }
    .padding()
    .themedBackground()
}

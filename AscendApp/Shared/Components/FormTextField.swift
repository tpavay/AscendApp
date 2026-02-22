//
//  FormTextField.swift
//  AscendApp
//
//  Reusable form text field component with consistent styling
//

import SwiftUI

struct FormTextField: View {
    let label: String
    let isRequired: Bool
    let icon: String?
    let placeholder: String?
    let keyboardType: UIKeyboardType
    @Binding var text: String
    @FocusState.Binding var focusedField: AnyHashable?
    let fieldIdentifier: AnyHashable?
    let maxLength: Int?

    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    init(
        label: String,
        isRequired: Bool = false,
        icon: String? = nil,
        placeholder: String? = nil,
        keyboardType: UIKeyboardType = .default,
        text: Binding<String>,
        focusedField: FocusState<AnyHashable?>.Binding? = nil,
        fieldIdentifier: AnyHashable? = nil,
        maxLength: Int? = nil
    ) {
        self.label = label
        self.isRequired = isRequired
        self.icon = icon
        self.placeholder = placeholder
        self.keyboardType = keyboardType
        self._text = text
        self._focusedField = focusedField ?? FocusState<AnyHashable?>().projectedValue
        self.fieldIdentifier = fieldIdentifier
        self.maxLength = maxLength
    }

    var body: some View {
        HStack(spacing: 12) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.gray)
                    .frame(width: 24)
            }

            TextField(effectivePlaceholder, text: $text)
                .focused($focusedField, equals: fieldIdentifier)
                .keyboardType(keyboardType)
                .font(.montserratRegular(size: 16))
                .onSubmit { focusedField = nil }
        }
        .padding(16)
        .background(fieldBackground)
        .onChange(of: text) { _, newValue in
            if let maxLength = maxLength {
                text = String(newValue.prefix(maxLength))
            }
        }
    }

    private var effectivePlaceholder: String {
        if let placeholder = placeholder {
            return placeholder
        }
        return isRequired ? "\(label) *" : label
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

// Multi-line text field variant
struct FormTextEditor: View {
    let label: String
    let isRequired: Bool
    let placeholder: String?
    let lineLimit: ClosedRange<Int>
    @Binding var text: String
    @FocusState.Binding var focusedField: AnyHashable?
    let fieldIdentifier: AnyHashable?
    let maxLength: Int?

    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    init(
        label: String,
        isRequired: Bool = false,
        placeholder: String? = nil,
        lineLimit: ClosedRange<Int> = 3...6,
        text: Binding<String>,
        focusedField: FocusState<AnyHashable?>.Binding? = nil,
        fieldIdentifier: AnyHashable? = nil,
        maxLength: Int? = nil
    ) {
        self.label = label
        self.isRequired = isRequired
        self.placeholder = placeholder
        self.lineLimit = lineLimit
        self._text = text
        self._focusedField = focusedField ?? FocusState<AnyHashable?>().projectedValue
        self.fieldIdentifier = fieldIdentifier
        self.maxLength = maxLength
    }

    var body: some View {
        TextField(effectivePlaceholder, text: $text, axis: .vertical)
            .focused($focusedField, equals: fieldIdentifier)
            .lineLimit(lineLimit)
            .font(.montserratRegular(size: 16))
            .padding(16)
            .background(fieldBackground)
            .onChange(of: text) { _, newValue in
                if let maxLength = maxLength {
                    text = String(newValue.prefix(maxLength))
                }
            }
    }

    private var effectivePlaceholder: String {
        if let placeholder = placeholder {
            return placeholder
        }
        return isRequired ? "\(label) *" : label
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
        FormTextField(
            label: "Workout Name",
            isRequired: true,
            text: .constant("")
        )

        FormTextField(
            label: "Enter steps",
            isRequired: false,
            icon: "figure.stairs",
            text: .constant("")
        )

        FormTextEditor(
            label: "Add a description",
            isRequired: false,
            text: .constant("")
        )
    }
    .padding()
    .themedBackground()
}

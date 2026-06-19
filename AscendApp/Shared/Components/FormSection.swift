//
//  FormSection.swift
//  AscendApp
//
//  Reusable form section header component
//

import SwiftUI

struct FormSection<Content: View>: View {
    let title: String
    let content: Content

    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.montserratMedium(size: 12))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)
                .padding(.leading, 4)

            content
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        FormSection(title: "Workout Details") {
            VStack(spacing: 12) {
                FormTextField<Never>(
                    label: "Workout Name",
                    isRequired: true,
                    text: .constant("")
                )

                FormButton(
                    label: "Select Date",
                    isRequired: true,
                    icon: "calendar",
                    value: "Today at 5:34 AM",
                    action: {}
                )
            }
        }

        FormSection(title: "Health Metrics") {
            VStack(spacing: 12) {
                FormTextField<Never>(
                    label: "Average heart rate (BPM)",
                    keyboardType: .numberPad,
                    text: .constant("")
                )

                FormTextField<Never>(
                    label: "Calories burned",
                    keyboardType: .numberPad,
                    text: .constant("")
                )
            }
        }
    }
    .padding()
    .themedBackground()
}

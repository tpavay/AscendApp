//
//  AppleHealthAutoImportPromptBanner.swift
//  AscendApp
//
//  Created by Codex on 5/1/26.
//

import SwiftUI

struct AppleHealthAutoImportPromptBanner: View {
    let effectiveColorScheme: ColorScheme
    let isEnabling: Bool
    let onTurnOn: () -> Void
    let onDismiss: () -> Void

    private var primaryTextColor: Color {
        effectiveColorScheme == .dark ? .white : .black
    }

    private var cardFillColor: Color {
        effectiveColorScheme == .dark ? Color.white.opacity(0.06) : Color.white
    }

    private var cardStrokeColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image("appleHealth-icon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Auto-import new workouts")
                        .font(.montserratSemiBold(size: 16))
                        .foregroundStyle(primaryTextColor)

                    Text("New Apple Health stair-stepper workouts can save automatically in Ascend. Review the latest one once to fix steps, notes, or media.")
                        .font(.montserratRegular(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                Button("Not Now", action: onDismiss)
                    .appSheetButtonStyle(tone: .secondary)
                    .disabled(isEnabling)

                Button(isEnabling ? "Turning On..." : "Turn On", action: onTurnOn)
                    .appSheetButtonStyle()
                    .disabled(isEnabling)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(cardFillColor)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(cardStrokeColor, lineWidth: 1)
        }
    }
}

#Preview {
    AppleHealthAutoImportPromptBanner(
        effectiveColorScheme: .light,
        isEnabling: false,
        onTurnOn: {},
        onDismiss: {}
    )
    .padding()
    .themedBackground()
}

//
//  EditWorkoutPermanentHeader.swift
//  AscendApp
//

import SwiftUI

struct EditWorkoutPermanentHeader: View {
    let title: String
    let primaryActionTitle: String
    let cancelActionTitle: String?
    let effectiveColorScheme: ColorScheme
    let isFormValid: Bool
    let isSaving: Bool
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let cancelActionTitle {
                    Button(cancelActionTitle, action: onCancel)
                        .font(.montserratRegular)
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                        .frame(minWidth: 80, alignment: .leading)
                } else {
                    Color.clear
                        .frame(width: 80, height: 1)
                }

                Spacer()

                Text(title)
                    .font(.montserratSemiBold(size: 18))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                Spacer()

                Button(action: onSave) {
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.8)
                            .progressViewStyle(CircularProgressViewStyle(tint: .accent))
                    } else {
                        Text(primaryActionTitle)
                    }
                }
                .font(.montserratSemiBold)
                .foregroundStyle(isFormValid ? .accent : .gray)
                .disabled(!isFormValid)
                .frame(minWidth: 80)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .background(effectiveColorScheme == .dark ? .black : .white)

            Divider()
                .background(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.2))
        }
        .background(effectiveColorScheme == .dark ? .black : .white)
    }
}

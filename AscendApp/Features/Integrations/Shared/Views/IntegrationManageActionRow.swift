//
//  IntegrationManageActionRow.swift
//  AscendApp
//
//  Created by Codex on 3/12/26.
//

import SwiftUI

struct IntegrationManageActionRow: View {
    let action: IntegrationManageAction

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: action.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(action.iconTint)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(action.iconTint.opacity(0.14))
                )

            Text(action.title)
                .font(.montserratSemiBold(size: 16))
                .foregroundStyle(titleColor)

            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .appSheetCardStyle(tone: action.tone)
    }

    private var titleColor: Color {
        action.isEnabled ? .white : .white.opacity(0.45)
    }
}

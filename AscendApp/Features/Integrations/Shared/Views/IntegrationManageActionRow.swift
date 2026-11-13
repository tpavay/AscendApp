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
            IntegrationManageRowLabel(
                systemImage: action.systemImage,
                title: action.title,
                subtitle: action.subtitle,
                iconTint: action.iconTint,
                titleColor: titleColor
            )

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

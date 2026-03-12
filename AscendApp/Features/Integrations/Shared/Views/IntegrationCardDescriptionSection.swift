//
//  IntegrationCardDescriptionSection.swift
//  AscendApp
//
//  Created by Codex on 3/12/26.
//

import SwiftUI

struct IntegrationCardDescriptionSection: View {
    let style: IntegrationCardStyle
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
                .overlay(style.divider)

            Text(text)
                .font(.montserratRegular(size: 14))
                .foregroundStyle(style.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

//
//  LeadingAccentStripe.swift
//  AscendApp
//
//  Created by Codex on 5/11/26.
//

import SwiftUI

struct LeadingAccentStripe: View {
    let color: Color
    var width: CGFloat = 4
    var cornerRadius: CGFloat = 12

    var body: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: cornerRadius,
            bottomLeadingRadius: cornerRadius,
            bottomTrailingRadius: 0,
            topTrailingRadius: 0,
            style: .continuous
        )
        .fill(color)
        .frame(width: width)
        .frame(maxHeight: .infinity)
    }
}


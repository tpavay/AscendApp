//
//  AppIcon.swift
//  AscendApp
//
//  Created by Codex on 2/28/26.
//

import SwiftUI

struct AppIcon: View {
    let token: AppIconToken
    var pointSize: CGFloat? = nil
    var weight: Font.Weight = .regular

    var body: some View {
        switch token.source {
        case .asset(let name):
            if let pointSize {
                Image(name)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: pointSize, height: pointSize)
            } else {
                Image(name)
                    .renderingMode(.template)
            }

        case .systemSymbol(let name):
            if let pointSize {
                Image(systemName: name)
                    .font(.system(size: pointSize, weight: weight))
            } else {
                Image(systemName: name)
            }
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        AppIcon(token: .tabHome)
            .foregroundStyle(.accent)

        AppIcon(token: .settingsWorkoutMetric, pointSize: 20, weight: .medium)
            .foregroundStyle(.accent)
    }
    .padding()
    .themedBackground()
}

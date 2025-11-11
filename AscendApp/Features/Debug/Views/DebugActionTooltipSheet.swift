//
//  DebugActionTooltipSheet.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import SwiftUI

#if DEBUG
struct DebugActionTooltipSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    let action: DebugAction

    var body: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: action.icon)
                .font(.system(size: 50))
                .foregroundStyle(action.iconColor)

            // Title
            Text(action.title)
                .font(.montserratBold(size: 24))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
                .multilineTextAlignment(.center)

            // Description
            Text(action.description)
                .font(.montserratRegular(size: 16))
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.8) : .gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            // Close button
            Button("Got It") {
                dismiss()
            }
            .font(.montserratSemiBold(size: 16))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.accent)
            .cornerRadius(12)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .themedBackground()
        .presentationDetents([.height(380)])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    Text("Background")
        .sheet(isPresented: .constant(true)) {
            DebugActionTooltipSheet(
                action: DebugAction(
                    title: "Seed Test Data",
                    description: "This will create fake leaderboard entries for 15 test users.",
                    icon: "arrow.down.doc.fill"
                )
            )
        }
}
#endif

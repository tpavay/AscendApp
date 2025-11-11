//
//  DebugActionRow.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import SwiftUI

#if DEBUG
struct DebugActionRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var showTooltip = false

    let action: DebugAction
    let isExecuting: Bool
    let onExecute: () -> Void

    var body: some View {
        Button {
            onExecute()
        } label: {
            HStack(spacing: 16) {
                // Icon
                Image(systemName: action.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(action.isDestructive ? .red : action.iconColor)

                // Title
                Text(action.title)
                    .font(.montserratMedium(size: 16))
                    .foregroundStyle(action.isDestructive ? .red : (colorScheme == .dark ? .white : .black))

                Spacer()

                // Info button
                Button {
                    showTooltip = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .gray)
                }
                .buttonStyle(.plain)

                // Loading indicator - only shows if THIS action is executing
                if isExecuting {
                    ProgressView()
                        .tint(.accent)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color("Jet") : .white)
            )
        }
        .buttonStyle(.plain)
        .disabled(isExecuting)
        .sheet(isPresented: $showTooltip) {
            DebugActionTooltipSheet(action: action)
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        DebugActionRow(
            action: DebugAction(
                title: "Seed Test Data",
                description: "Creates fake data",
                icon: "arrow.down.doc.fill"
            ),
            isExecuting: false,
            onExecute: {}
        )

        DebugActionRow(
            action: DebugAction(
                title: "Clear Test Data",
                description: "Removes test data",
                icon: "trash.fill",
                iconColor: .red,
                isDestructive: true
            ),
            isExecuting: true,
            onExecute: {}
        )
    }
    .padding()
    .themedBackground()
}
#endif

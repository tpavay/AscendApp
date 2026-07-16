//
//  IntegrationManageSheet.swift
//  AscendApp
//
//  Created by Codex on 3/12/26.
//

import SwiftUI

struct IntegrationManageSheet: View {
    let assetImage: String
    let title: String
    let message: String?
    let actions: [IntegrationManageAction]
    let dismissButtonTitle: String
    let onDismiss: () -> Void

    init(
        assetImage: String,
        title: String,
        message: String? = nil,
        actions: [IntegrationManageAction],
        dismissButtonTitle: String = "Close",
        onDismiss: @escaping () -> Void
    ) {
        self.assetImage = assetImage
        self.title = title
        self.message = message
        self.actions = actions
        self.dismissButtonTitle = dismissButtonTitle
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            IntegrationManageHeader(assetImage: assetImage, title: title)

            if let message {
                Text(message)
                    .font(.montserratRegular(size: 16))
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(spacing: 12) {
                ForEach(actions) { action in
                    Button(action: action.action) {
                        IntegrationManageActionRow(action: action)
                    }
                    .buttonStyle(.plain)
                    .disabled(!action.isEnabled)
                    .opacity(action.isEnabled ? 1 : 0.55)
                }
            }

            Button(dismissButtonTitle, action: onDismiss)
                .appSheetButtonStyle(tone: .subtle)
        }
        .padding(.top, 24)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .appSheetBackground()
        .appSheetStyle(.actionMenu)
    }
}

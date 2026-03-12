//
//  IntegrationManageHeader.swift
//  AscendApp
//
//  Created by Codex on 3/12/26.
//

import SwiftUI

struct IntegrationManageHeader: View {
    let assetImage: String
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Image(assetImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 36, height: 36)
                .clipShape(.rect(cornerRadius: 10))

            Text(title)
                .font(.montserratSemiBold(size: 18))
                .foregroundStyle(.white)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

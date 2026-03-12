//
//  IntegrationCardHeader.swift
//  AscendApp
//
//  Created by Codex on 3/12/26.
//

import SwiftUI

struct IntegrationCardHeader<Accessory: View>: View {
    let assetImage: String
    let title: String
    let subtitle: String?
    let titleColor: Color
    let subtitleColor: Color
    let accessory: Accessory

    init(
        assetImage: String,
        title: String,
        subtitle: String? = nil,
        titleColor: Color,
        subtitleColor: Color = .secondary,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.assetImage = assetImage
        self.title = title
        self.subtitle = subtitle
        self.titleColor = titleColor
        self.subtitleColor = subtitleColor
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(assetImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 44, height: 44)
                .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: subtitle == nil ? 0 : 4) {
                Text(title)
                    .font(.montserratSemiBold(size: 17))
                    .foregroundStyle(titleColor)

                if let subtitle {
                    Text(subtitle)
                        .font(.montserratMedium(size: 13))
                        .foregroundStyle(subtitleColor)
                }
            }

            Spacer()

            accessory
        }
    }
}

extension IntegrationCardHeader where Accessory == EmptyView {
    init(
        assetImage: String,
        title: String,
        subtitle: String? = nil,
        titleColor: Color,
        subtitleColor: Color = .secondary
    ) {
        self.init(
            assetImage: assetImage,
            title: title,
            subtitle: subtitle,
            titleColor: titleColor,
            subtitleColor: subtitleColor
        ) {
            EmptyView()
        }
    }
}

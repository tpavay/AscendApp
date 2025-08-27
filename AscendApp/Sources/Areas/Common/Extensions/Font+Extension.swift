//
//  Font+Extension.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/9/25.
//

import SwiftUI

extension Font {
    static func montserratBold(size: CGFloat = 48) -> Font {
        return Font.custom("Montserrat-Bold", size: size, relativeTo: .largeTitle)
    }

    static var montserratBold: Font {
        Font.custom("Montserrat-Bold", size: 48, relativeTo: .largeTitle)
    }

    static func montserratSemiBold(size: CGFloat = 20) -> Font {
        return Font.custom("Montserrat-SemiBold", size: size, relativeTo: .title3)
    }

    static var montserratSemiBold: Font {
        Font.custom("Montserrat-SemiBold", size: 20, relativeTo: .title3)
    }

    static func montserratMedium(size: CGFloat = 17) -> Font {
        return Font.custom("Montserrat-Medium", size: size, relativeTo: .body)
    }

    static var montserratMedium: Font {
        Font.custom("Montserrat-Medium", size: 17, relativeTo: .body)
    }

    static func montserratRegular(size: CGFloat = 17) -> Font {
        return Font.custom("Montserrat-Regular", size: size, relativeTo: .body)
    }

    static var montserratRegular: Font {
        Font.custom("Montserrat-Regular", size: 17, relativeTo: .body)
    }

    static var montserratLight: Font {
        Font.custom("Montserrat-Light", size: 15, relativeTo: .callout)
    }

    static var montserratItalic: Font {
        Font.custom("Montserrat-Italic", size: 17, relativeTo: .body)
    }
}

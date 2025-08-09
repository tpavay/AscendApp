//
//  Font+Extension.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/9/25.
//

import SwiftUI

extension Font {
    static var montserratBold: Font {
        Font.custom("Montserrat-Bold", size: 48, relativeTo: .largeTitle)
    }

    static var montserratSemiBold: Font {
        Font.custom("Montserrat-SemiBold", size: 20, relativeTo: .title3)
    }

    static var montserratMedium: Font {
        Font.custom("Montserrat-Medium", size: 17, relativeTo: .body)
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

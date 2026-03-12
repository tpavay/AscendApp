//
//  IntegrationCardStyle.swift
//  AscendApp
//
//  Created by Codex on 3/12/26.
//

import SwiftUI

struct IntegrationCardStyle {
    let effectiveColorScheme: ColorScheme

    var backgroundFill: Color {
        effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.05)
    }

    var backgroundStroke: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1)
    }

    var primaryText: Color {
        effectiveColorScheme == .dark ? .white : .black
    }

    var secondaryText: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.72) : .gray.opacity(0.9)
    }

    var tertiaryText: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.6) : .secondary
    }

    var divider: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.2)
    }

    var subtleActionText: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.68) : .black.opacity(0.68)
    }

    var subtleActionBorder: Color {
        divider
    }
}

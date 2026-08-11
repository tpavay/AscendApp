import SwiftUI

/// The accent fill and the foreground that stays legible on it.
///
/// `AppSheetButtonTone.primary` puts white on the same lime, which lands near 1.9:1. Any sheet
/// action that needs a readable label on the accent reaches for `.accentContrast` instead of
/// growing a third near-duplicate tone.
enum AppSheetAccentContrastColors {
    static let background = Color.ascendAccent
    static let foreground = Color.black
}

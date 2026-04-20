//
//  AppSheet.swift
//  AscendApp
//
//  Created by Codex on 3/11/26.
//

import SwiftUI

struct AppSheetConfiguration {
    let sizing: AppSheetSizing
    let dragIndicator: Visibility
}

enum AppSheetSizing {
    case detents(Set<PresentationDetent>)
    case contentHeight(minHeight: CGFloat = 150, extraPadding: CGFloat = 0)
}

enum AppSheetCardTone {
    case standard
    case accent
    case destructive
}

enum AppSheetButtonTone {
    case primary
    case secondary
    case subtle
    case destructive
}

enum AppSheetOptionRowStyle {
    case standard
    case compact
}

enum AppSheetPreset {
    case compactConfirmation
    case destructiveConfirmation
    case actionMenu
    case dialog(height: CGFloat, dragIndicator: Visibility = .visible)
    case menu(height: CGFloat, dragIndicator: Visibility = .visible)
    case filterMenu(height: CGFloat)
    case dateFilter
    case dateTimePicker
    case effortRating
    case durationPicker
    case settingsPicker
    case medium
    case large
    case mediumLarge
    case fitted(dragIndicator: Visibility = .visible)
    case height(CGFloat, dragIndicator: Visibility = .visible)
    case fraction(CGFloat, dragIndicator: Visibility = .visible)
    case detents(Set<PresentationDetent>, dragIndicator: Visibility = .visible)

    var configuration: AppSheetConfiguration {
        switch self {
        case .compactConfirmation:
            return AppSheetConfiguration(sizing: .contentHeight(minHeight: 170, extraPadding: -8), dragIndicator: .visible)
        case .destructiveConfirmation:
            return AppSheetConfiguration(sizing: .contentHeight(minHeight: 182, extraPadding: 8), dragIndicator: .visible)
        case .actionMenu:
            return AppSheetConfiguration(sizing: .contentHeight(minHeight: 150, extraPadding: -18), dragIndicator: .visible)
        case .dialog(let height, let dragIndicator), .menu(let height, let dragIndicator), .height(let height, let dragIndicator):
            return AppSheetConfiguration(sizing: .detents([.height(height)]), dragIndicator: dragIndicator)
        case .filterMenu(let height):
            return AppSheetConfiguration(sizing: .detents([.height(height)]), dragIndicator: .visible)
        case .dateFilter:
            return AppSheetConfiguration(sizing: .detents([.fraction(0.85)]), dragIndicator: .visible)
        case .dateTimePicker:
            return AppSheetConfiguration(sizing: .contentHeight(minHeight: 280, extraPadding: -12), dragIndicator: .visible)
        case .effortRating:
            return AppSheetConfiguration(sizing: .contentHeight(minHeight: 240, extraPadding: -12), dragIndicator: .visible)
        case .durationPicker:
            return AppSheetConfiguration(sizing: .detents([.height(340)]), dragIndicator: .visible)
        case .settingsPicker:
            return AppSheetConfiguration(sizing: .detents([.height(320)]), dragIndicator: .visible)
        case .medium:
            return AppSheetConfiguration(sizing: .detents([.medium]), dragIndicator: .visible)
        case .large:
            return AppSheetConfiguration(sizing: .detents([.large]), dragIndicator: .visible)
        case .mediumLarge:
            return AppSheetConfiguration(sizing: .detents([.medium, .large]), dragIndicator: .visible)
        case .fitted(let dragIndicator):
            return AppSheetConfiguration(sizing: .contentHeight(minHeight: 180, extraPadding: -12), dragIndicator: dragIndicator)
        case .fraction(let value, let dragIndicator):
            return AppSheetConfiguration(sizing: .detents([.fraction(value)]), dragIndicator: dragIndicator)
        case .detents(let detents, let dragIndicator):
            return AppSheetConfiguration(sizing: .detents(detents), dragIndicator: dragIndicator)
        }
    }
}

private struct AppSheetModifier: ViewModifier {
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var themeManager = ThemeManager.shared

    let configuration: AppSheetConfiguration
    let isInteractiveDismissDisabled: Bool
    @State private var measuredContentHeight: CGFloat = 0

    private var palette: AppSheetPalette {
        AppSheetPalette(
            effectiveColorScheme: themeManager.effectiveColorScheme(for: systemColorScheme)
        )
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        let base = content
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: AppSheetHeightPreferenceKey.self, value: proxy.size.height)
                }
            )
            .onPreferenceChange(AppSheetHeightPreferenceKey.self) { height in
                guard abs(height - measuredContentHeight) > 1 else { return }
                measuredContentHeight = height
            }
            .presentationDragIndicator(configuration.dragIndicator)
            .presentationBackground(palette.background)
            .interactiveDismissDisabled(isInteractiveDismissDisabled)

        switch configuration.sizing {
        case .detents(let detents):
            base.presentationDetents(detents)
        case .contentHeight(let minHeight, let extraPadding):
            base.presentationDetents([.height(max(measuredContentHeight + extraPadding, minHeight))])
        }
    }
}

extension View {
    func appSheetStyle(_ preset: AppSheetPreset, isInteractiveDismissDisabled: Bool = false) -> some View {
        modifier(
            AppSheetModifier(
                configuration: preset.configuration,
                isInteractiveDismissDisabled: isInteractiveDismissDisabled
            )
        )
    }

    func appSheetBackground() -> some View {
        modifier(AppSheetBackgroundModifier())
    }

    func appSheetCardStyle(tone: AppSheetCardTone = .standard) -> some View {
        modifier(AppSheetCardModifier(tone: tone))
    }

    func appSheetButtonStyle(tone: AppSheetButtonTone = .primary) -> some View {
        modifier(AppSheetButtonModifier(tone: tone))
    }
}

private struct AppSheetBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var themeManager = ThemeManager.shared

    private var palette: AppSheetPalette {
        AppSheetPalette(
            effectiveColorScheme: themeManager.effectiveColorScheme(for: systemColorScheme)
        )
    }

    func body(content: Content) -> some View {
        content
            .background(palette.background.ignoresSafeArea())
    }
}

private struct AppSheetCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var themeManager = ThemeManager.shared

    let tone: AppSheetCardTone

    private var palette: AppSheetPalette {
        AppSheetPalette(
            effectiveColorScheme: themeManager.effectiveColorScheme(for: systemColorScheme)
        )
    }

    private var fillColor: Color {
        switch tone {
        case .standard:
            return palette.cardFill
        case .accent:
            return .accent.opacity(palette.effectiveColorScheme == .dark ? 0.16 : 0.1)
        case .destructive:
            return .red.opacity(palette.effectiveColorScheme == .dark ? 0.16 : 0.1)
        }
    }

    private var strokeColor: Color {
        switch tone {
        case .standard:
            return palette.cardStroke
        case .accent:
            return .accent.opacity(0.28)
        case .destructive:
            return .red.opacity(0.24)
        }
    }

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(strokeColor, lineWidth: 1)
            )
    }
}

private struct AppSheetButtonModifier: ViewModifier {
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var themeManager = ThemeManager.shared

    let tone: AppSheetButtonTone

    private var palette: AppSheetPalette {
        AppSheetPalette(
            effectiveColorScheme: themeManager.effectiveColorScheme(for: systemColorScheme)
        )
    }

    private var foregroundColor: Color {
        switch tone {
        case .primary, .destructive:
            return .white
        case .secondary:
            return palette.primaryText
        case .subtle:
            return palette.secondaryText
        }
    }

    private var fillColor: Color {
        switch tone {
        case .primary:
            return .accent
        case .secondary:
            return .clear
        case .subtle:
            return palette.cardFill
        case .destructive:
            return .red
        }
    }

    private var strokeColor: Color {
        switch tone {
        case .primary, .destructive:
            return .clear
        case .secondary:
            return palette.effectiveColorScheme == .dark ? .white.opacity(0.28) : .black.opacity(0.16)
        case .subtle:
            return palette.cardStroke
        }
    }

    func body(content: Content) -> some View {
        content
            .font(.montserratSemiBold)
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(strokeColor, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct AppSheetPalette {
    let effectiveColorScheme: ColorScheme

    var background: Color {
        effectiveColorScheme == .dark ? .jet : .white
    }

    var primaryText: Color {
        effectiveColorScheme == .dark ? .white : .black
    }

    var cardFill: Color {
        effectiveColorScheme == .dark ? .jetLighter.opacity(0.24) : .black.opacity(0.04)
    }

    var cardStroke: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08)
    }

    var secondaryText: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.68) : .gray
    }
}

struct AppSheetLayout {
    let sectionSpacing: CGFloat
    let contentPadding: EdgeInsets

    static let dialog = AppSheetLayout(
        sectionSpacing: 14,
        contentPadding: EdgeInsets(top: 30, leading: 20, bottom: 4, trailing: 20)
    )

    static let menu = AppSheetLayout(
        sectionSpacing: 12,
        contentPadding: EdgeInsets(top: 28, leading: 20, bottom: 4, trailing: 20)
    )

    static let actionMenu = AppSheetLayout(
        sectionSpacing: 10,
        contentPadding: EdgeInsets(top: 24, leading: 20, bottom: 0, trailing: 20)
    )

    static let picker = AppSheetLayout(
        sectionSpacing: 10,
        contentPadding: EdgeInsets(top: 28, leading: 20, bottom: 4, trailing: 20)
    )
}

private struct AppSheetHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct AppSheetOptionRow: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var themeManager = ThemeManager.shared

    let icon: AppSheetOptionIcon
    let title: String
    let subtitle: String?
    let iconTint: Color?
    let tone: AppSheetCardTone
    let style: AppSheetOptionRowStyle
    let badgeCount: Int
    let trailingSymbol: String?
    let trailingTint: Color?

    enum AppSheetOptionIcon {
        case system(String)
        case asset(String)
    }

    init(
        systemImage: String,
        title: String,
        subtitle: String? = nil,
        iconTint: Color,
        tone: AppSheetCardTone = .standard,
        style: AppSheetOptionRowStyle = .standard,
        badgeCount: Int = 0,
        trailingSymbol: String? = nil,
        trailingTint: Color? = nil
    ) {
        self.icon = .system(systemImage)
        self.title = title
        self.subtitle = subtitle
        self.iconTint = iconTint
        self.tone = tone
        self.style = style
        self.badgeCount = badgeCount
        self.trailingSymbol = trailingSymbol
        self.trailingTint = trailingTint
    }

    init(
        assetImage: String,
        title: String,
        subtitle: String? = nil,
        tone: AppSheetCardTone = .standard,
        style: AppSheetOptionRowStyle = .standard,
        badgeCount: Int = 0,
        trailingSymbol: String? = nil,
        trailingTint: Color? = nil
    ) {
        self.icon = .asset(assetImage)
        self.title = title
        self.subtitle = subtitle
        self.iconTint = nil
        self.tone = tone
        self.style = style
        self.badgeCount = badgeCount
        self.trailingSymbol = trailingSymbol
        self.trailingTint = trailingTint
    }

    private var palette: AppSheetPalette {
        AppSheetPalette(
            effectiveColorScheme: themeManager.effectiveColorScheme(for: systemColorScheme)
        )
    }

    private var titleColor: Color {
        switch tone {
        case .standard:
            return palette.primaryText
        case .accent:
            return .accent
        case .destructive:
            return .red
        }
    }

    private var subtitleColor: Color {
        switch tone {
        case .destructive:
            return .red.opacity(0.72)
        case .standard, .accent:
            return palette.secondaryText
        }
    }

    private var accessoryColor: Color {
        trailingTint ?? (tone == .standard ? palette.secondaryText.opacity(0.8) : titleColor)
    }

    private var iconBackgroundColor: Color {
        switch tone {
        case .standard:
            return palette.effectiveColorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.06)
        case .accent:
            return .accent.opacity(palette.effectiveColorScheme == .dark ? 0.16 : 0.12)
        case .destructive:
            return .red.opacity(palette.effectiveColorScheme == .dark ? 0.14 : 0.12)
        }
    }

    private var iconSize: CGFloat {
        switch style {
        case .standard:
            return 44
        case .compact:
            return 36
        }
    }

    private var rowSpacing: CGFloat {
        switch style {
        case .standard:
            return 16
        case .compact:
            return 14
        }
    }

    private var horizontalPadding: CGFloat {
        switch style {
        case .standard:
            return 16
        case .compact:
            return 14
        }
    }

    private var verticalPadding: CGFloat {
        switch style {
        case .standard:
            return subtitle == nil ? 14 : 16
        case .compact:
            return subtitle == nil ? 12 : 14
        }
    }

    private var iconFont: Font {
        switch style {
        case .standard:
            return .system(size: 20, weight: .medium)
        case .compact:
            return .system(size: 18, weight: .medium)
        }
    }

    private var trailingFont: Font {
        switch style {
        case .standard:
            return .system(size: 14, weight: .semibold)
        case .compact:
            return .system(size: 13, weight: .semibold)
        }
    }

    @ViewBuilder
    private var iconView: some View {
        switch icon {
        case .system(let systemImage):
            Image(systemName: systemImage)
                .font(iconFont)
                .foregroundStyle(iconTint ?? palette.primaryText)
                .frame(width: iconSize, height: iconSize)
                .background(
                    Circle()
                        .fill(iconBackgroundColor)
                )
        case .asset(let assetImage):
            Image(assetImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSize, height: iconSize)
                .clipShape(.rect(cornerRadius: 10))
        }
    }

    var body: some View {
        HStack(spacing: rowSpacing) {
            ZStack(alignment: .topTrailing) {
                iconView

                if badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(Circle().fill(.red))
                        .offset(x: 4, y: -4)
                }
            }

            VStack(alignment: .leading, spacing: subtitle == nil ? 0 : 4) {
                Text(title)
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(titleColor)

                if let subtitle {
                    Text(subtitle)
                        .font(.montserratRegular(size: 13))
                        .foregroundStyle(subtitleColor)
                }
            }

            Spacer(minLength: 12)

            if let trailingSymbol {
                Image(systemName: trailingSymbol)
                    .font(trailingFont)
                    .foregroundStyle(accessoryColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .appSheetCardStyle(tone: tone)
    }
}

struct AppSheetScaffold<Content: View, Footer: View>: View {
    let title: String
    let message: String?
    let headerAlignment: HorizontalAlignment
    let contentAlignment: HorizontalAlignment
    let layout: AppSheetLayout
    let content: Content
    let footer: Footer

    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    init(
        title: String,
        message: String? = nil,
        headerAlignment: HorizontalAlignment = .center,
        contentAlignment: HorizontalAlignment = .center,
        layout: AppSheetLayout = .dialog,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.message = message
        self.headerAlignment = headerAlignment
        self.contentAlignment = contentAlignment
        self.layout = layout
        self.content = content()
        self.footer = footer()
    }

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    private var textAlignment: TextAlignment {
        headerAlignment == .leading ? .leading : .center
    }

    private var headerFrameAlignment: Alignment {
        headerAlignment == .leading ? .leading : .center
    }

    private var contentFrameAlignment: Alignment {
        contentAlignment == .leading ? .leading : .center
    }

    var body: some View {
        VStack(alignment: contentAlignment, spacing: layout.sectionSpacing) {
            VStack(alignment: headerAlignment, spacing: 8) {
                Text(title)
                    .font(.montserratBold(size: 20))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    .multilineTextAlignment(textAlignment)
                    .fixedSize(horizontal: false, vertical: true)

                if let message {
                    Text(message)
                        .font(.montserratRegular(size: 16))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.8) : .gray)
                        .multilineTextAlignment(textAlignment)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: headerFrameAlignment)

            if Content.self != EmptyView.self {
                content
                    .frame(maxWidth: .infinity, alignment: contentFrameAlignment)
            }

            if Footer.self != EmptyView.self {
                footer
                    .frame(maxWidth: .infinity, alignment: contentFrameAlignment)
            }
        }
        .frame(maxWidth: .infinity, alignment: contentFrameAlignment)
        .padding(layout.contentPadding)
        .appSheetBackground()
    }
}

extension AppSheetScaffold where Footer == EmptyView {
    init(
        title: String,
        message: String? = nil,
        headerAlignment: HorizontalAlignment = .center,
        contentAlignment: HorizontalAlignment = .center,
        layout: AppSheetLayout = .dialog,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            message: message,
            headerAlignment: headerAlignment,
            contentAlignment: contentAlignment,
            layout: layout,
            content: content
        ) {
            EmptyView()
        }
    }
}

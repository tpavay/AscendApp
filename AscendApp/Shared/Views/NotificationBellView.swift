//
//  NotificationBellView.swift
//  AscendApp
//
//  Created by Claude on 9/1/25.
//

import SwiftUI

extension View {
    func apply<V: View>(@ViewBuilder _ block: (Self) -> V) -> V {
        return block(self)
    }
}

struct NotificationBellView: View {
    let pendingImports: Int
    let isHighlighted: Bool
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHighlightAnimating = false

    init(
        pendingImports: Int,
        isHighlighted: Bool = false,
        action: @escaping () -> Void
    ) {
        self.pendingImports = pendingImports
        self.isHighlighted = isHighlighted
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                
                if pendingImports > 0 {
                    let displayText = pendingImports > 99 ? "99+" : "\(pendingImports)"
                    let isWideText = pendingImports > 99
                    
                    Text(displayText)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(minWidth: isWideText ? 24 : 18, minHeight: 18)
                        .background(
                            RoundedRectangle(cornerRadius: isWideText ? 9 : 18)
                                .fill(.red)
                                .overlay(
                                    RoundedRectangle(cornerRadius: isWideText ? 9 : 18)
                                        .stroke(.white, lineWidth: 1.5)
                                        .opacity(0.3)
                                )
                        )
                        .offset(x: 10, y: -10)
                        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                }
            }
            .frame(width: 44, height: 44)
            .background {
                if isHighlighted {
                    Circle()
                        .fill(.accent.opacity(reduceMotion ? 0.14 : (isHighlightAnimating ? 0.08 : 0.18)))
                        .frame(width: 44, height: 44)
                }
            }
            .overlay {
                if isHighlighted {
                    Circle()
                        .stroke(.accent.opacity(reduceMotion ? 0.5 : (isHighlightAnimating ? 0.06 : 0.7)), lineWidth: 2)
                        .frame(width: 44, height: 44)
                        .scaleEffect(reduceMotion ? 1 : (isHighlightAnimating ? 1.18 : 0.94))
                        .opacity(reduceMotion ? 1 : (isHighlightAnimating ? 0 : 1))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Import or review workouts")
        .accessibilityHint("Opens Apple Health and connected workout imports")
        .onAppear {
            syncHighlightAnimation()
            if pendingImports > 0 {
                debugLog("🔔 NotificationBellView showing badge: \(pendingImports)")
            } else {
                debugLog("🔔 NotificationBellView no badge - count: \(pendingImports)")
            }
        }
        .onChange(of: isHighlighted) { _, _ in
            syncHighlightAnimation()
        }
    }

    private func syncHighlightAnimation() {
        guard isHighlighted, !reduceMotion else {
            isHighlightAnimating = false
            return
        }

        withAnimation(.easeOut(duration: 1.05).repeatForever(autoreverses: false)) {
            isHighlightAnimating = true
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        NotificationBellView(pendingImports: 0) {
            debugLog("Bell tapped - no badge")
        }
        
        NotificationBellView(pendingImports: 3) {
            debugLog("Bell tapped - 3 imports")
        }
        
        NotificationBellView(pendingImports: 99) {
            debugLog("Bell tapped - 99 imports")
        }
        
        NotificationBellView(pendingImports: 150) {
            debugLog("Bell tapped - 150 imports")
        }
    }
    .padding()
}

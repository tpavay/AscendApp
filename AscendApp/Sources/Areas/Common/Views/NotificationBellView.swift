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
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
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
                        .foregroundColor(.white)
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
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            if pendingImports > 0 {
                print("🔔 NotificationBellView showing badge: \(pendingImports)")
            } else {
                print("🔔 NotificationBellView no badge - count: \(pendingImports)")
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        NotificationBellView(pendingImports: 0) {
            print("Bell tapped - no badge")
        }
        
        NotificationBellView(pendingImports: 3) {
            print("Bell tapped - 3 imports")
        }
        
        NotificationBellView(pendingImports: 99) {
            print("Bell tapped - 99 imports")
        }
        
        NotificationBellView(pendingImports: 150) {
            print("Bell tapped - 150 imports")
        }
    }
    .padding()
}

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
            Image(systemName: "bell")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
        }
        .buttonStyle(PlainButtonStyle())
        .apply { view in
            if pendingImports > 0 {
                view.badge(pendingImports)
            } else {
                view
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

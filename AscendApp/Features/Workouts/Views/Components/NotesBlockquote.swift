//
//  NotesBlockquote.swift
//  AscendApp
//
//  Created by Tyler Pavay on 4/2/26.
//

import SwiftUI

/// Displays workout notes in a blockquote style with a left accent border.
/// Supports expand/collapse for long text.
struct NotesBlockquote: View {
    let text: String
    let effectiveColorScheme: ColorScheme

    @State private var isExpanded = false

    private var needsTruncation: Bool {
        text.count > 240 || text.components(separatedBy: "\n").count > 3
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Left accent border
            RoundedRectangle(cornerRadius: 1.5)
                .fill(.accent)
                .frame(width: 3)

            // Notes text
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(.montserratRegular(size: 15))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.7))
                    .lineLimit(isExpanded ? nil : 3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if needsTruncation {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Text(isExpanded ? "Show less" : "Show more")
                            .font(.montserratMedium(size: 13))
                            .foregroundStyle(.accent)
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    VStack(spacing: 24) {
        NotesBlockquote(
            text: "This is a note",
            effectiveColorScheme: .dark
        )

        NotesBlockquote(
            text: "Great morning workout! Felt really strong and maintained a good pace throughout the entire session. Pushed hard on the last 10 minutes and managed to hit a new personal record for steps.",
            effectiveColorScheme: .dark
        )
    }
    .padding(20)
    .background(Color.black)
}

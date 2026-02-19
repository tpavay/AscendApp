//
//  TypewriterText.swift
//  AscendApp
//
//  Created by Claude on 2/19/26.
//

import SwiftUI

/// Animated typewriter text with gradient coloring
/// Cycles through example phrases with a typing animation
struct TypewriterText: View {
    let phrases: [String]
    let typingSpeed: Double // seconds per character
    let pauseDuration: Double // seconds to pause after typing complete
    let gradient: LinearGradient
    
    @State private var displayedText: String = ""
    @State private var currentPhraseIndex: Int = 0
    @State private var isTyping: Bool = true
    @State private var charIndex: Int = 0
    
    init(
        phrases: [String],
        typingSpeed: Double = 0.05,
        pauseDuration: Double = 2.0,
        gradient: LinearGradient = LinearGradient(
            colors: [
                Color(red: 0.4, green: 0.6, blue: 1.0),
                Color(red: 0.6, green: 0.4, blue: 1.0),
                Color(red: 0.8, green: 0.5, blue: 1.0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    ) {
        self.phrases = phrases
        self.typingSpeed = typingSpeed
        self.pauseDuration = pauseDuration
        self.gradient = gradient
    }
    
    var body: some View {
        Text(displayedText)
            .font(.montserratMedium(size: 18))
            .foregroundStyle(gradient)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear {
                startTypingAnimation()
            }
    }
    
    private func startTypingAnimation() {
        guard !phrases.isEmpty else { return }
        typeNextCharacter()
    }
    
    private func typeNextCharacter() {
        let currentPhrase = phrases[currentPhraseIndex]
        
        if charIndex < currentPhrase.count {
            // Still typing current phrase
            let index = currentPhrase.index(currentPhrase.startIndex, offsetBy: charIndex)
            displayedText = String(currentPhrase[...index])
            charIndex += 1
            
            DispatchQueue.main.asyncAfter(deadline: .now() + typingSpeed) {
                typeNextCharacter()
            }
        } else {
            // Finished typing, pause then move to next phrase
            DispatchQueue.main.asyncAfter(deadline: .now() + pauseDuration) {
                eraseText()
            }
        }
    }
    
    private func eraseText() {
        if displayedText.count > 0 {
            displayedText = String(displayedText.dropLast())
            DispatchQueue.main.asyncAfter(deadline: .now() + typingSpeed / 2) {
                eraseText()
            }
        } else {
            // Move to next phrase
            currentPhraseIndex = (currentPhraseIndex + 1) % phrases.count
            charIndex = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                typeNextCharacter()
            }
        }
    }
}

/// A more advanced typewriter with cursor blink
struct TypewriterTextWithCursor: View {
    let phrases: [String]
    let typingSpeed: Double
    let pauseDuration: Double
    let gradient: LinearGradient
    
    @State private var displayedText: String = ""
    @State private var currentPhraseIndex: Int = 0
    @State private var charIndex: Int = 0
    @State private var showCursor: Bool = true
    
    init(
        phrases: [String],
        typingSpeed: Double = 0.05,
        pauseDuration: Double = 2.0,
        gradient: LinearGradient = LinearGradient(
            colors: [
                Color(red: 0.4, green: 0.6, blue: 1.0),
                Color(red: 0.6, green: 0.4, blue: 1.0),
                Color(red: 0.8, green: 0.5, blue: 1.0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    ) {
        self.phrases = phrases
        self.typingSpeed = typingSpeed
        self.pauseDuration = pauseDuration
        self.gradient = gradient
    }
    
    var body: some View {
        HStack(spacing: 0) {
            Text(displayedText)
                .font(.montserratMedium(size: 18))
                .foregroundStyle(gradient)
            
            // Blinking cursor
            Text("|")
                .font(.montserratMedium(size: 18))
                .foregroundStyle(gradient)
                .opacity(showCursor ? 1 : 0)
                .animation(.easeInOut(duration: 0.5).repeatForever(), value: showCursor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            showCursor = true
            startTypingAnimation()
            startCursorBlink()
        }
    }
    
    private func startCursorBlink() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            // Cursor blink handled by animation
        }
    }
    
    private func startTypingAnimation() {
        guard !phrases.isEmpty else { return }
        typeNextCharacter()
    }
    
    private func typeNextCharacter() {
        let currentPhrase = phrases[currentPhraseIndex]
        
        if charIndex < currentPhrase.count {
            let index = currentPhrase.index(currentPhrase.startIndex, offsetBy: charIndex)
            displayedText = String(currentPhrase[...index])
            charIndex += 1
            
            DispatchQueue.main.asyncAfter(deadline: .now() + typingSpeed) {
                typeNextCharacter()
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + pauseDuration) {
                eraseText()
            }
        }
    }
    
    private func eraseText() {
        if displayedText.count > 0 {
            displayedText = String(displayedText.dropLast())
            DispatchQueue.main.asyncAfter(deadline: .now() + typingSpeed / 2) {
                eraseText()
            }
        } else {
            currentPhraseIndex = (currentPhraseIndex + 1) % phrases.count
            charIndex = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                typeNextCharacter()
            }
        }
    }
}

// MARK: - Shimmer Gradient Animation

struct ShimmerGradientText: View {
    let text: String
    let font: Font
    
    @State private var gradientOffset: CGFloat = -1
    
    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.4, green: 0.6, blue: 1.0),
                        Color(red: 0.7, green: 0.5, blue: 1.0),
                        Color(red: 1.0, green: 0.6, blue: 0.8),
                        Color(red: 0.7, green: 0.5, blue: 1.0),
                        Color(red: 0.4, green: 0.6, blue: 1.0)
                    ],
                    startPoint: UnitPoint(x: gradientOffset, y: 0),
                    endPoint: UnitPoint(x: gradientOffset + 1, y: 0)
                )
            )
            .onAppear {
                withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                    gradientOffset = 1
                }
            }
    }
}

#Preview("Typewriter") {
    VStack {
        TypewriterText(phrases: [
            "I did 30 minutes on the stairstepper...",
            "3000 steps with my 20lb vest...",
            "Three intervals: 5, 10, and 5 minutes...",
            "Quick session, felt great today..."
        ])
        .padding()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black)
}

#Preview("With Cursor") {
    VStack {
        TypewriterTextWithCursor(phrases: [
            "I did 30 minutes on the stairstepper...",
            "3000 steps with my 20lb vest...",
            "Three intervals: 5, 10, and 5 minutes..."
        ])
        .padding()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black)
}

#Preview("Shimmer") {
    ShimmerGradientText(
        text: "Log your workout with voice...",
        font: .montserratMedium(size: 18)
    )
    .padding()
    .background(Color.black)
}

import SwiftUI

/// The twelve-key pad under the Log a climb fields. Digits and backspace only: the number being
/// typed is a step count or a console time, and a decimal point or a sign would mean neither.
struct LogClimbKeypad: View {
    let onDigit: (Int) -> Void
    let onDelete: () -> Void

    private static let rows: [[Key]] = [
        [.digit(1), .digit(2), .digit(3)],
        [.digit(4), .digit(5), .digit(6)],
        [.digit(7), .digit(8), .digit(9)],
        [.blank, .digit(0), .delete]
    ]

    private enum Key: Hashable {
        case digit(Int)
        case delete
        case blank
    }

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Self.rows.indices, id: \.self) { rowIndex in
                HStack(spacing: 6) {
                    ForEach(Self.rows[rowIndex].indices, id: \.self) { columnIndex in
                        key(Self.rows[rowIndex][columnIndex])
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func key(_ key: Key) -> some View {
        switch key {
        case .digit(let digit):
            Button {
                HapticsManager.shared.trigger(.selection)
                onDigit(digit)
            } label: {
                Text("\(digit)")
                    .font(.montserratBold(size: 24))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(keyBackground)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(digit)")

        case .delete:
            Button {
                HapticsManager.shared.trigger(.selection)
                onDelete()
            } label: {
                Image(systemName: "delete.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(keyBackground)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete")

        case .blank:
            keyBackground
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .accessibilityHidden(true)
        }
    }

    private var keyBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white.opacity(0.07))
    }
}

#Preview {
    LogClimbKeypad(onDigit: { _ in }, onDelete: {})
        .padding()
        .background(Color.black)
}

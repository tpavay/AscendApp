import SwiftUI

/// Grid: steps and up to three stats in two columns of ruled cells, each value at 30 points
/// sitting on the cell's bottom edge.
struct PresetGridLayout: View {
    let model: PresetCardModel

    private struct Cell: Identifiable {
        let id: String
        let label: String
        let value: String
        let isSteps: Bool
    }

    private var cells: [Cell] {
        let steps = Cell(id: "steps", label: "STEPS", value: model.subject.stepsText, isSteps: true)
        let rest = model.gridStats.map { Cell(id: $0.id.rawValue, label: $0.label, value: $0.value, isSteps: false) }
        return [steps] + rest
    }

    private var rows: [[Cell]] {
        let all = cells
        return stride(from: 0, to: all.count, by: 2).map { Array(all[$0..<min($0 + 2, all.count)]) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(row) { cell in
                        cellView(cell)
                    }
                    if row.count == 1 {
                        Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .overlay(alignment: .top) { hairline }
        .padding(.horizontal, 20)
        .padding(.top, 52)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func cellView(_ cell: Cell) -> some View {
        let palette = model.palette
        return VStack(alignment: .leading, spacing: 0) {
            Text(cell.label)
                .presetText(
                    model.font,
                    size: 9,
                    weight: 700,
                    trackingEm: 0.14,
                    color: Color(share: cell.isSteps ? palette.accentText : palette.secondary)
                )
                .presetOneLine(floor: PresetFitGeometry.labelFloor)
            Text(cell.value)
                .presetText(model.font, size: 30, weight: 900, trackingEm: -0.03, color: Color(share: palette.foreground))
                .presetOneLine()
                .frame(height: 30 * 1.05)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .overlay(alignment: .bottom) { hairline }
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color(share: model.palette.rule))
            .frame(height: 1)
    }
}

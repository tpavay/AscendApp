import SwiftUI

struct BaseLevelSlider: View {
    @Binding var selectedLevel: Int

    var body: some View {
        SegmentedHeatmapSlider(selectedLevel: $selectedLevel)
    }
}

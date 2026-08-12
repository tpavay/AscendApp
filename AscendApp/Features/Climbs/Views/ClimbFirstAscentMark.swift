import SwiftUI

/// The shipped cut-out gold summit flag, standing beside the First Ascent line the way it stands
/// on the profile achievement shelf: resizable, `.scaledToFit()`, no clip, no tile, no stroke.
/// Clipping a cut-out to a circle slices the flag off, and a stroke draws an edge around
/// transparency.
///
/// The art is a 3:2 landscape canvas whose opaque flag occupies the middle ~55% horizontally and
/// ~93% vertically, so `.scaledToFit()` into a square box renders a flag about 0.62 × `size` tall
/// with a transparent gutter either side - which is why the line it sits on tightens its spacing.
/// 34 is the smallest box where the finial, pole, pennant and mound all resolve (checked against a
/// rendered ladder from 20 to 40); below it the flag reads as a gold smudge, above it the mark
/// starts competing with the podium rows. It still fits the 44pt row, and First Ascent stays a
/// permanent annotation rather than the active chase.
struct ClimbFirstAscentMark: View {
    static let size: CGFloat = 34

    var body: some View {
        Image("FirstAscentBadgeDetailed")
            .resizable()
            .scaledToFit()
            .frame(width: Self.size, height: Self.size)
            .accessibilityHidden(true)
    }
}

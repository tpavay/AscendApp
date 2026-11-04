import SwiftUI

/// Everything under TIME on the Log a climb screen: what the climber has added, as cards, and
/// what they have not, as plus buttons.
///
/// Empty, it is the OPTIONAL label over a two by two grid of plus buttons. A button turns into
/// the card for what it collected - Effort and Avg heart rate side by side, the note, a Photos
/// row with an Add tile inline - and the buttons left over close ranks.
struct LogClimbOptionalSection: View {
    let viewModel: LogClimbViewModel
    /// Photos are not a sheet: this raises the system picker straight away.
    let onAddPhoto: () -> Void
    let onOpen: (LogClimbOptionalField) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            filledCards

            if viewModel.isFilled(.note) {
                noteCard
            }

            if viewModel.isFilled(.photo) {
                LogClimbPhotosSection(viewModel: viewModel, onAddPhoto: onAddPhoto)
            }

            plusButtons
        }
    }

    // MARK: - Cards

    @ViewBuilder
    private var filledCards: some View {
        let effort = viewModel.details.effortRating
        let heartRate = viewModel.details.averageHeartRate
        if effort != nil || heartRate != nil {
            HStack(spacing: 10) {
                if let effort {
                    effortCard(rating: Int(effort))
                }
                if let heartRate {
                    heartRateCard(bpm: heartRate)
                }
            }
            // Side by side the two cards are one height, whichever has less to say.
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func effortCard(rating: Int) -> some View {
        Button {
            onOpen(.effort)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                LogClimbCardLabel(title: "EFFORT")

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(rating)")
                        .font(.montserratBold(size: 26))
                        .foregroundStyle(.white)
                    Text("/ 5 · \(EffortRatingView.effortWord(for: rating))")
                        .font(.montserratSemiBold(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                HStack(spacing: 4) {
                    ForEach(1...5, id: \.self) { step in
                        Capsule()
                            .fill(step <= rating ? Color.accent : Color.white.opacity(0.12))
                            .frame(height: 4)
                    }
                }
                .accessibilityHidden(true)
            }
            .logClimbCard()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Effort")
        .accessibilityValue("\(rating) out of 5, \(EffortRatingView.effortWord(for: rating))")
        .accessibilityHint("Changes the effort")
    }

    private func heartRateCard(bpm: Int) -> some View {
        Button {
            onOpen(.heartRate)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                LogClimbCardLabel(title: "AVG HEART RATE")

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(bpm)")
                        .font(.montserratBold(size: 26))
                        .foregroundStyle(.white)
                    Text("bpm")
                        .font(.montserratSemiBold(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .logClimbCard()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Average heart rate")
        .accessibilityValue("\(bpm) beats per minute")
        .accessibilityHint("Changes the heart rate")
    }

    private var noteCard: some View {
        Button {
            onOpen(.note)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    LogClimbCardLabel(title: "NOTE")
                    Spacer()
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.55))
                        .accessibilityHidden(true)
                }

                Text(viewModel.details.note.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.montserratMedium(size: 15))
                    .foregroundStyle(.white.opacity(0.92))
                    .multilineTextAlignment(.leading)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .logClimbCard()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Note")
        .accessibilityValue(viewModel.details.note.trimmingCharacters(in: .whitespacesAndNewlines))
        .accessibilityHint("Changes the note")
    }

    // MARK: - Plus buttons

    @ViewBuilder
    private var plusButtons: some View {
        let unfilled = viewModel.unfilledOptionalFields
        if !unfilled.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("OPTIONAL")
                    .font(.montserratBold(size: 12))
                    .tracking(1.6)
                    .foregroundStyle(.white.opacity(0.55))

                // Two to a row, and a lone last button takes the whole row rather than sitting
                // half-width beside nothing.
                ForEach(Array(stride(from: 0, to: unfilled.count, by: 2)), id: \.self) { start in
                    HStack(spacing: 10) {
                        ForEach(unfilled[start..<min(start + 2, unfilled.count)]) { field in
                            plusButton(field)
                        }
                    }
                }
            }
        }
    }

    private func plusButton(_ field: LogClimbOptionalField) -> some View {
        Button {
            if field == .photo {
                onAddPhoto()
            } else {
                onOpen(field)
            }
        } label: {
            plusLabel(field)
        }
        .buttonStyle(.plain)
        .disabled(field == .photo && !viewModel.canPickMedia)
        .accessibilityLabel("Add \(field.title)")
    }

    private func plusLabel(_ field: LogClimbOptionalField) -> some View {
        HStack(spacing: 6) {
            if field == .photo, viewModel.isLoadingMedia {
                ProgressView().tint(.accent)
            } else {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.accent)
            }
            Text(field.title)
                .font(.montserratBold(size: 14))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// The PHOTOS row: each picked photo as a square tile with its remove badge, then an Add tile
/// while there is room for another.
struct LogClimbPhotosSection: View {
    let viewModel: LogClimbViewModel
    let onAddPhoto: () -> Void

    private static let tileSize: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LogClimbCardLabel(title: "PHOTOS")
                .padding(.horizontal, 4)

            HStack(spacing: 10) {
                ForEach(viewModel.selectedPhotos) { item in
                    photoTile(item)
                }

                if viewModel.canAddMorePhotos {
                    addTile
                }
            }
        }
    }

    private func photoTile(_ item: SelectedPhotoItem) -> some View {
        let isHighlighted = viewModel.highlightedPhotoId == item.id
        return Button {
            viewModel.highlightPhoto(id: item.id)
        } label: {
            // A fill reports the size it scaled to, so the picture is an overlay on a tile of the
            // size it may take.
            Color.clear
                .frame(width: Self.tileSize, height: Self.tileSize)
                .overlay {
                    item.image
                        .resizable()
                        .scaledToFill()
                }
                .overlay {
                    if item.isVideo {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            isHighlighted ? Color.accent : Color.white.opacity(0.12),
                            lineWidth: isHighlighted ? 2 : 1
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.isVideo ? "Video" : "Photo")
        .accessibilityValue(isHighlighted ? "Highlighted" : "")
        .overlay(alignment: .topTrailing) {
            MediaTileDeleteButton {
                viewModel.removePhoto(id: item.id)
            }
            .padding(5)
        }
    }

    private var addTile: some View {
        Button(action: onAddPhoto) {
            VStack(spacing: 6) {
                if viewModel.isLoadingMedia {
                    ProgressView().tint(.accent)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.accent)
                    Text("Add")
                        .font(.montserratBold(size: 13))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .frame(width: Self.tileSize, height: Self.tileSize)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canPickMedia)
        .accessibilityLabel("Add photo")
    }
}

private struct LogClimbCardLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.montserratBold(size: 12))
            .tracking(1.6)
            .foregroundStyle(.white.opacity(0.55))
    }
}

private extension View {
    /// The surface every filled detail sits on: the same dark card the steps and time fields use,
    /// a step smaller in radius because these are a step smaller in weight.
    func logClimbCard() -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

//
//  HomeImportProgressBar.swift
//  AscendApp
//

import SwiftUI

/// The slim strip Home shows while an Apple Health backfill is still landing.
///
/// Home stays fully usable throughout - the import runs a workout at a time and yields between
/// them - so this exists to answer the one question a stale-looking screen provokes: *is my
/// history missing, or is it still arriving?* It states the condition and the remaining count,
/// and gets out of the way on its own.
struct HomeImportProgressBar: View {
    let remainingCount: Int
    let totalCount: Int

    private var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(totalCount - remainingCount) / Double(totalCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pulling in your history. ^[\(remainingCount) session](inflect: true) to go.")
                .font(.montserratMedium(size: 12))
                .foregroundStyle(.secondary)

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(.accent)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Importing workouts from Apple Health")
        .accessibilityValue("\(totalCount - remainingCount) of \(totalCount) imported")
    }
}

#Preview {
    VStack {
        HomeImportProgressBar(remainingCount: 128, totalCount: 400)
        HomeImportProgressBar(remainingCount: 3, totalCount: 400)
        HomeImportProgressBar(remainingCount: 1, totalCount: 400)
    }
    .padding(.vertical, 40)
}

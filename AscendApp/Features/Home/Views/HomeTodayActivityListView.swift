import SwiftUI

/// SEE ALL: every row the server holds in the today feed, newest first.
struct HomeTodayActivityListView: View {
    let rows: [ModeratedHomeTodayActivityRow]
    let presentations: [String: HomeTodayActivityRowPresentation]
    let onOpen: (ModeratedHomeTodayActivityRow, HomeTodayActivityRowPresentation) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(rows) { row in
                    if let presentation = presentations[row.id] {
                        HomeTodayActivityRowView(row: row, presentation: presentation) {
                            onOpen(row, presentation)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("On the Globe Today")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black, for: .navigationBar)
        .preferredColorScheme(.dark)
        .trackOnce(screen: .homeTodayActivityList)
    }
}

import Foundation

/// The year the yearly stickers name. `ShareTotalsSnapshot` carries no year, and the yearly
/// standing is always the current one, so the sticker reads it from the clock.
enum StickerCalendarYear {
    static func current(calendar: Calendar = .current, now: Date = Date()) -> Int {
        calendar.component(.year, from: now)
    }
}

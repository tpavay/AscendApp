import SwiftUI

/// The composer's motion vocabulary.
///
/// Nothing on the canvas used to be animated: a deleted sticker vanished on a
/// frame boundary, and the trash zone, the add button and the edit rail popped in
/// and out on every single drag. Naming the curves in one place keeps the canvas
/// consistent and keeps the timings out of a dozen call sites.
enum ShareComposerAnimation {
    /// Chrome appearing and disappearing around a drag.
    static let chrome: Animation = .easeOut(duration: 0.18)

    /// A sticker's content reflowing — a metric added, the arrangement changed,
    /// a label moved.
    static let content: Animation = .spring(response: 0.32, dampingFraction: 0.82)

    /// Adding and removing stickers.
    static let placement: Animation = .spring(response: 0.34, dampingFraction: 0.78)

    /// Removal transition for a sticker leaving the canvas. Computed because
    /// `AnyTransition` is not `Sendable` and so cannot be a shared constant.
    static var removal: AnyTransition { .scale(scale: 0.6).combined(with: .opacity) }
}

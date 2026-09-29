import Foundation

/// Which of the climbers racing on the Mountain are drawn on the stairs this frame.
///
/// A climb can race hundreds of best climbs at once, most of them bunched around the start and
/// around the middle of the field; drawing them all buries the climber and costs every frame.
/// So the stairs carry a small, steady pack: the climbers just ahead and just behind, chosen
/// fresh every frame from where each of them is right now, plus your best and a pacer. As your
/// place changes the pack changes with it - speeding up reads as a stream of people you
/// overtake, slowing down as people passing you - and a climber already drawn keeps their place
/// against a newcomer who is only barely closer, so nobody flickers at the edge. Where the field
/// is dense, dozens of climbers share each stair; the pack is spaced out along them, so it reads
/// as people strung up the stairs ahead of you rather than a clump standing on your own step.
struct MountainPack: Sendable {
    struct Limits: Equatable, Sendable {
        /// Climbers drawn ahead of you, nearest first - with `behind`, the size of the pack and
        /// how far it leans ahead.
        var ahead = 6
        /// Climbers drawn behind you, nearest first.
        var behind = 4
        /// Steps a newcomer must be closer by to take a drawn climber's place.
        var hysteresisSteps = 3.0
        /// Climbers who carry a name, nearest first; your best and a pacer always do. Every
        /// product we looked at rations names, and a stair full of them is a wall of labels.
        var names = 4
        /// Seconds a climber stays once drawn, however the pack reshuffles around them: in a
        /// crowd of hundreds the nearest few change every moment, and a pack that turned over
        /// that fast would read as flicker.
        var minimumDwellSeconds = 1.5
        /// Steps kept between two drawn climbers who would stand in the same place across the
        /// stair. Side by side they both fit; one behind the other they climb a little over a
        /// stair apart, the way people do, rather than nose to tail.
        var spacingSteps = 1.4
    }

    struct Candidate: Equatable, Sendable {
        let id: String
        let kind: MountainGhost.Kind
        /// Steps ahead of the climber; negative behind.
        let lead: Double
        /// Metres from the middle of the stair where the climber stands.
        var lane = 0.0
    }

    /// Metres across the stair two climbers need to stand side by side.
    static let shoulderWidth = 0.45

    /// Seconds a climber takes to fade fully in or out.
    static let fadeSeconds = 0.35

    var limits = Limits()
    /// How present each climber is, from 0 (gone) to 1 (fully drawn).
    private(set) var presence: [String: Double] = [:]
    /// The climbers chosen at the last update.
    private(set) var chosen: Set<String> = []
    /// When each chosen climber joined the pack, on the pack's own clock.
    private var joinedAt: [String: Double] = [:]
    private var clock = 0.0

    init(limits: Limits = Limits()) {
        self.limits = limits
    }

    /// Chooses this frame's pack from every candidate in drawing range and moves each climber's
    /// presence toward being there or not.
    mutating func update(_ candidates: [Candidate], deltaTime: Double) {
        clock += deltaTime
        let settling = Set(joinedAt.filter { clock - $0.value < limits.minimumDwellSeconds }.keys)
        chosen = Self.choose(candidates, limits: limits, keeping: chosen, locked: settling)
        joinedAt = joinedAt.filter { chosen.contains($0.key) }
        for id in chosen where joinedAt[id] == nil {
            joinedAt[id] = clock
        }
        let step = deltaTime / Self.fadeSeconds
        var next: [String: Double] = [:]
        for candidate in candidates {
            let target = chosen.contains(candidate.id) ? 1.0 : 0.0
            let current = presence[candidate.id] ?? 0
            let moved = current < target ? min(current + step, target) : max(current - step, target)
            if moved > 0 { next[candidate.id] = moved }
        }
        presence = next
    }

    /// The pack for `candidates`: always your best and a pacer, then the nearest climbers, as
    /// many as the limits allow ahead and behind together. Distances behind count for more, so
    /// the pack leans ahead the way the limits do, but everyone is ranked on one scale: at the
    /// start, where the whole field stands on the same stair and drifts across your own step,
    /// crossing from just ahead to just behind never costs a climber their place. A drawn
    /// climber is favoured over a newcomer, a `locked` one - who joined too recently to leave -
    /// keeps their place, and nobody is drawn where another drawn climber already stands.
    static func choose(
        _ candidates: [Candidate],
        limits: Limits,
        keeping drawn: Set<String>,
        locked: Set<String> = []
    ) -> Set<String> {
        var chosen = Set(candidates.filter { $0.kind != .rival }.map(\.id))
        let rivals = candidates.filter { $0.kind == .rival }
        let behindWeight = Double(max(limits.ahead, 1)) / Double(max(limits.behind, 1))
        func score(_ candidate: Candidate) -> Double {
            let distance = candidate.lead >= 0 ? candidate.lead : -candidate.lead * behindWeight
            return distance - (drawn.contains(candidate.id) ? limits.hysteresisSteps : 0)
        }
        let staying = rivals.filter { locked.contains($0.id) }
        let open = max(limits.ahead + limits.behind - staying.count, 0)
        var standing = staying
        var nearest: [Candidate] = []
        for candidate in rivals.filter({ !locked.contains($0.id) }).sorted(by: { score($0) < score($1) }) {
            guard nearest.count < open else { break }
            let clear = standing.allSatisfy {
                abs($0.lead - candidate.lead) >= limits.spacingSteps || abs($0.lane - candidate.lane) >= shoulderWidth
            }
            guard clear else { continue }
            nearest.append(candidate)
            standing.append(candidate)
        }
        chosen.formUnion(staying.map(\.id))
        chosen.formUnion(nearest.map(\.id))
        return chosen
    }

    /// How much of a climber shows where they would stand over you: just behind you they are
    /// between you and the camera, and right beside you they cover you, so they thin out there
    /// and you always read clearly.
    static func clearance(lead: Double) -> Double {
        // Level with you a climber has stepped to the side, so they only need to thin enough that
        // yours is the athlete that reads; just behind you they stand between you and the camera.
        let thinnest = 0.35
        if lead >= 1.8 || lead <= -6.5 { return 1 }
        if lead >= 0.8 { return thinnest + (1 - thinnest) * (lead - 0.8) / 1.0 }
        if lead >= -4 { return thinnest }
        return thinnest + (1 - thinnest) * (-4 - lead) / 2.5
    }
}

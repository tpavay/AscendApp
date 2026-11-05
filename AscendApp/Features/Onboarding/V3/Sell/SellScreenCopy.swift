import Foundation

/// Every line the selling screens say, in one place so the copy contract can read all of it:
/// nothing here says "live", "race" or "field", and nothing is framed against another app.
/// Strings that carry a number read it from the real type (`BestEffortMetric`, `UnlockCopy`) at
/// the screen, not from here.
enum SellScreenCopy {
    enum Welcome {
        static let headlineLead = ["Congratulations,"]
        static let headlineAccent = ["you're on your way"]
        static let body = "to enjoying the stair stepper like never before."
        static let start = "Get started"
    }

    enum GoHarder {
        static let headlineLead = ["Go harder than"]
        static let headlineAccent = ["you would alone."]
        static let body = "Real climbers' best climbs move up beside you, step for step. There's always someone just ahead to catch."
        static let screenshotDescription = "The Ascend Mountain: your athlete on the stairs with other climbers' best climbs beside you"
    }

    enum GetBetter {
        static let headlineLead = ["See yourself"]
        static let headlineAccent = ["get better."]
        static let body = "The machine forgets every workout. Ascend remembers, and tells you the moment you beat yourself."
        static let allTimeBest = "All-time best"
    }

    enum SomethingToChase {
        static let headlineLead = ["Always something"]
        static let headlineAccent = ["to chase next."]
        static let body = "So tomorrow's climb never feels like a chore."
        static let chips = ["Best efforts to beat", "Leaderboards", "Achievements", "Monthly gear"]
        static let highlightedChip = "Monthly gear"
    }

    enum CountMethods {
        static let headlineLead = ["Climb with"]
        static let headlineAccent = ["what you've got."]
        static let body = "Nothing to buy. Every climb counts, however you track it."

        struct Method: Equatable {
            let title: String
            let detail: String
            let isBest: Bool
        }

        static let methods = [
            Method(
                title: "Headphones",
                detail: "AirPods or Beats count every step, and other climbers move up beside you.",
                isBest: true
            ),
            Method(
                title: "Apple Health",
                detail: "Track the workout with any device or app that saves to Apple Health. It shows up in Ascend on its own.",
                isBest: false
            ),
            Method(
                title: "Nothing at all",
                detail: "Type in what the machine says when you're done.",
                isBest: false
            )
        ]
        static let bestBadge = "Best"
    }

    static let continueTitle = "Continue"

    /// Every string above, for the copy contract.
    static var all: [String] {
        var strings = [continueTitle]
        strings += Welcome.headlineLead + Welcome.headlineAccent
        strings += [Welcome.body, Welcome.start]
        strings += OnboardingV3Step.welcome.alternateExits.map(\.title)
        strings += GoHarder.headlineLead + GoHarder.headlineAccent
        strings += [GoHarder.body, GoHarder.screenshotDescription]
        strings += GetBetter.headlineLead + GetBetter.headlineAccent
        strings += [GetBetter.body, GetBetter.allTimeBest]
        strings += SomethingToChase.headlineLead + SomethingToChase.headlineAccent
        strings += [SomethingToChase.body] + SomethingToChase.chips
        strings += CountMethods.headlineLead + CountMethods.headlineAccent
        strings += [CountMethods.body, CountMethods.bestBadge]
        strings += CountMethods.methods.flatMap { [$0.title, $0.detail] }
        return strings
    }
}

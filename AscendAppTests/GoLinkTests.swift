import Foundation
import Testing
@testable import AscendApp

/// `https://ascendstepper.com/go` opens the app from a lifecycle email
/// (`docs/universal-links.md`). The link has to be recognised exactly as narrowly as the
/// apple-app-site-association file promises, reported once, and reported as nothing but an event.
@MainActor
struct GoLinkTests {
    // MARK: - Recognising a link

    @Test("The paths the apple-app-site-association file claims are recognised",
          arguments: [
            "https://ascendstepper.com/go",
            "https://ascendstepper.com/go?src=email-trial-reminder",
            "https://ascendstepper.com/go/",
            "https://ascendstepper.com/go/anything/below?src=instagram",
            "https://ASCENDSTEPPER.com/go?src=email-trial-reminder"
          ])
    func recognisesGoLinks(_ link: String) throws {
        let url = try #require(URL(string: link))
        #expect(GoLink(url: url) != nil)
    }

    @Test("Anything else on the domain, and any other domain or scheme, is not a go link",
          arguments: [
            "https://ascendstepper.com/",
            "https://ascendstepper.com/privacy",
            "https://ascendstepper.com/going",
            "https://ascendstepper.com/go-away",
            "https://ascendstepper.com/about/go",
            "https://www.ascendstepper.com/go",
            "https://ascendstepper.com.example.com/go",
            "https://example.com/go?src=email-trial-reminder",
            "http://ascendstepper.com/go",
            "ascendapp://go",
            "ascendapp-dev://live-climb?sessionID=abc"
          ])
    func rejectsOtherLinks(_ link: String) throws {
        let url = try #require(URL(string: link))
        #expect(GoLink(url: url) == nil)
    }

    @Test("Each lifecycle email's source tag is reported as itself")
    func reportsTheEmailTags() throws {
        let expected: [(String, GoLink.Source)] = [
            ("email-paywall-abandoned", .emailPaywallAbandoned),
            ("email-free-week-unused", .emailFreeWeekUnused),
            ("email-trial-reminder", .emailTrialReminder),
            ("instagram", .instagram),
            ("tiktok", .tiktok),
            ("youtube", .youtube),
            ("facebook", .facebook)
        ]
        for (tag, source) in expected {
            let url = try #require(URL(string: "https://ascendstepper.com/go?src=\(tag)"))
            #expect(GoLink(url: url)?.source == source)
            #expect(source.rawValue == tag)
        }
    }

    @Test("A missing, blank or unregistered tag never becomes an analytics value of its own")
    func boundsTheSourceTag() throws {
        let cases: [(String, GoLink.Source)] = [
            ("https://ascendstepper.com/go", .missing),
            ("https://ascendstepper.com/go?src=", .missing),
            ("https://ascendstepper.com/go?src=%20", .missing),
            ("https://ascendstepper.com/go?src=Email-Trial-Reminder", .emailTrialReminder),
            ("https://ascendstepper.com/go?src=a-stranger-wrote-this", .unrecognized),
            ("https://ascendstepper.com/go?src=none", .unrecognized),
            ("https://ascendstepper.com/go?src=other", .unrecognized),
            ("https://ascendstepper.com/go?utm_source=email-trial-reminder", .missing)
        ]
        for (link, source) in cases {
            let url = try #require(URL(string: link))
            #expect(GoLink(url: url)?.source == source, "\(link)")
        }
    }

    // MARK: - Reporting a link

    @Test("A link that starts the process reports a cold launch, and a later one a foreground")
    func reportsHowTheAppWasOpened() throws {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let clock = AppActivityClock()
        let handler = GoLinkHandler(
            telemetry: makeTestTelemetry(sink: sink),
            activityClock: clock
        )

        #expect(handler.handle(try #require(URL(string: "https://ascendstepper.com/go?src=email-paywall-abandoned"))))
        clock.recordDidEnterBackground()
        #expect(handler.handle(try #require(URL(string: "https://ascendstepper.com/go?src=email-trial-reminder"))))

        let records = sink.records
        #expect(records.map(\.name) == ["go_link_opened", "go_link_opened"])
        #expect(records[0].parameters["src"] == .string("email-paywall-abandoned"))
        #expect(records[0].parameters["session_type"] == .string("cold_launch"))
        #expect(records[1].parameters["src"] == .string("email-trial-reminder"))
        #expect(records[1].parameters["session_type"] == .string("foreground"))
        let envelopeKeys: Set<String> = ["app_environment", "build_config", "app_version", "build_number"]
        #expect(Set(records[0].parameters.keys).subtracting(envelopeKeys) == ["src", "session_type"])
    }

    @Test("One link delivered through both SwiftUI callbacks is one open")
    func absorbsTheDuplicateDelivery() throws {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        var moment = Date(timeIntervalSince1970: 1_000)
        let handler = GoLinkHandler(
            telemetry: makeTestTelemetry(sink: sink),
            activityClock: AppActivityClock(),
            now: { moment }
        )
        let url = try #require(URL(string: "https://ascendstepper.com/go?src=email-free-week-unused"))

        #expect(handler.handle(url))
        moment.addTimeInterval(0.2)
        #expect(handler.handle(url), "a duplicate is still consumed so no other handler sees it")
        #expect(sink.records.count == 1)

        moment.addTimeInterval(GoLinkHandler.duplicateWindow + 1)
        #expect(handler.handle(url))
        #expect(sink.records.count == 2, "the same email tapped again later is a second open")
    }

    @Test("A different link inside the window is not a duplicate")
    func reportsDifferentLinksSeparately() throws {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let handler = GoLinkHandler(
            telemetry: makeTestTelemetry(sink: sink),
            activityClock: AppActivityClock()
        )

        handler.handle(try #require(URL(string: "https://ascendstepper.com/go?src=email-free-week-unused")))
        handler.handle(try #require(URL(string: "https://ascendstepper.com/go?src=email-trial-reminder")))

        #expect(sink.records.count == 2)
    }

    @Test("Links that are not go links are left for the app's other handlers")
    func leavesOtherLinksAlone() throws {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let handler = GoLinkHandler(
            telemetry: makeTestTelemetry(sink: sink),
            activityClock: AppActivityClock()
        )

        for link in [
            "https://ascendstepper.com/privacy",
            "ascendapp://live-climb?sessionID=abc",
            "com.googleusercontent.apps.123:/oauth2callback?code=x"
        ] {
            #expect(handler.handle(try #require(URL(string: link))) == false)
        }
        #expect(sink.records.isEmpty)
    }
}

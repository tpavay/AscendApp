//
//  RemoteMediaLoaderTests.swift
//  AscendAppTests
//
//  Created by Codex on 3/30/26.
//

import Foundation
import Testing
import UIKit
@testable import AscendApp

struct RemoteMediaLoaderTests {
    @Test
    func loadPhotoCachesSuccessfulResponses() async throws {
        ImageCache.shared.clearAll()

        let url = URL(string: "https://example.com/cache-photo.jpg")!
        let callCounter = RequestCounter()
        let imageData = try #require(makeImageData())

        let loader = RemoteMediaLoader(
            requestTimeoutSeconds: 1.0,
            photoRequest: { request in
                #expect(request.timeoutInterval == 1.0)
                await callCounter.increment()

                let response = try #require(
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
                )
                return (imageData, response)
            },
            videoPlayableRequest: { _ in },
            errorRecorder: { _, _ in }
        )

        let firstImage = await loader.loadPhoto(from: url)
        let secondImage = await loader.loadPhoto(from: url)

        #expect(firstImage != nil)
        #expect(secondImage != nil)
        #expect(await callCounter.value == 1)
    }

    @Test
    func loadPhotoRejectsInvalidResponses() async throws {
        ImageCache.shared.clearAll()

        let url = URL(string: "https://example.com/forbidden-photo.jpg")!
        let imageData = try #require(makeImageData())

        let loader = RemoteMediaLoader(
            requestTimeoutSeconds: 1.0,
            photoRequest: { _ in
                let response = try #require(
                    HTTPURLResponse(url: url, statusCode: 403, httpVersion: nil, headerFields: nil)
                )
                return (imageData, response)
            },
            videoPlayableRequest: { _ in },
            errorRecorder: { _, _ in }
        )

        let image = await loader.loadPhoto(from: url)
        #expect(image == nil)
    }

    @Test
    func canPrepareVideoTimesOutWhenReadinessNeverFinishes() async {
        let url = URL(string: "https://example.com/hanging-video.mov")!

        let loader = RemoteMediaLoader(
            requestTimeoutSeconds: 0.05,
            photoRequest: { _ in
                throw URLError(.badServerResponse)
            },
            videoPlayableRequest: { _ in
                // Readiness that never finishes on its own. A bounded sleep would
                // race the loader's timeout, and on a loaded machine both can
                // elapse - leaving the result up to whichever child the scheduler
                // resumes first. Only cancellation ends this wait, so the timeout
                // is the sole thing that can resolve the call.
                while true {
                    try await Task.sleep(for: .seconds(60))
                }
            },
            errorRecorder: { _, _ in }
        )

        let canPrepare = await loader.canPrepareVideo(from: url)
        #expect(canPrepare == false)
    }

    private func makeImageData() -> Data? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
        let image = renderer.image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        return image.pngData()
    }
}

private actor RequestCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

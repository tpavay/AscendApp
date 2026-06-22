#if DEBUG || STAGING
import Foundation

final class SuperwallStaticConfigCacheBusterURLProtocol: URLProtocol, @unchecked Sendable {
    private static let handledKey = "com.ascendapp.superwallStaticConfigCacheBuster.handled"
    private static let registration: Void = {
        URLProtocol.registerClass(SuperwallStaticConfigCacheBusterURLProtocol.self)
    }()

    private var dataTask: URLSessionDataTask?
    private var session: URLSession?

    static func register() {
        _ = registration
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard URLProtocol.property(forKey: handledKey, in: request) == nil else {
            return false
        }

        guard
            let url = request.url,
            url.scheme == "https",
            url.host == "api.superwall.me",
            url.path == "/api/v1/static_config",
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return false
        }

        let queryItems = components.queryItems ?? []
        let hasPublicKey = queryItems.contains { $0.name == "pk" }
        let isAlreadyCacheBusted = queryItems.contains { $0.name == "ascend_cache_bust" }
        return hasPublicKey && !isAlreadyCacheBusted
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let cacheBustedRequest = Self.cacheBustedRequest(from: request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil

        let session = URLSession(configuration: configuration)
        self.session = session
        dataTask = session.dataTask(with: cacheBustedRequest) { [weak self] data, response, error in
            guard let self else { return }

            if let error {
                self.client?.urlProtocol(self, didFailWithError: error)
                return
            }

            if let response {
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }

            if let data {
                self.client?.urlProtocol(self, didLoad: data)
            }

            self.client?.urlProtocolDidFinishLoading(self)
        }
        dataTask?.resume()
    }

    override func stopLoading() {
        dataTask?.cancel()
        session?.finishTasksAndInvalidate()
        dataTask = nil
        session = nil
    }

    private static func cacheBustedRequest(from request: URLRequest) -> URLRequest? {
        guard
            let url = request.url,
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        var queryItems = components.queryItems ?? []
        queryItems.append(
            URLQueryItem(
                name: "ascend_cache_bust",
                value: String(Int(Date().timeIntervalSince1970))
            )
        )
        components.queryItems = queryItems

        guard let cacheBustedURL = components.url else {
            return nil
        }

        let cacheBustedRequest = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest
        cacheBustedRequest?.url = cacheBustedURL
        cacheBustedRequest?.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        guard let cacheBustedRequest else {
            return nil
        }

        URLProtocol.setProperty(true, forKey: handledKey, in: cacheBustedRequest)
        return cacheBustedRequest as URLRequest
    }
}
#endif

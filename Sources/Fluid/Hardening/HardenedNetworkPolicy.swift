import Foundation

/// Central network boundary for the hardened build.
///
/// The hardened application may communicate only with services on the same Mac. Every
/// URLSession call site must validate its final URL through this policy before network I/O.
/// The source verifier enforces that coverage.
enum HardenedNetworkPolicy {
    final class RedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
#if HARDENED
            do {
                try HardenedNetworkPolicy.validate(request)
                completionHandler(request)
            } catch {
                completionHandler(nil)
            }
#else
            completionHandler(request)
#endif
        }
    }

    enum PolicyError: LocalizedError {
        case blockedExternalEndpoint
        case unsupportedScheme

        var errorDescription: String? {
            switch self {
            case .blockedExternalEndpoint:
                return "External network access is disabled in FluidVoice Local."
            case .unsupportedScheme:
                return "FluidVoice Local permits local HTTP endpoints only."
            }
        }
    }

    /// Accept HTTP(S) loopback destinations only. Private LAN ranges remain outside the
    /// boundary because they can route prompts and transcripts to another device.
    static func isLoopbackEndpoint(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return self.isLoopbackURL(url)
    }

    static func isLoopbackURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        guard var host = url.host?.lowercased(), host.isEmpty == false else { return false }
        host = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))

        if host == "localhost" || host == "::1" { return true }

        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4,
              octets.allSatisfy({ part in
                  guard let value = Int(part), value >= 0, value <= 255 else { return false }
                  return String(value) == String(part)
              }),
              octets.first == "127"
        else { return false }

        return true
    }

    static func validate(_ url: URL) throws {
#if HARDENED
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw PolicyError.unsupportedScheme
        }
        guard self.isLoopbackURL(url) else {
            throw PolicyError.blockedExternalEndpoint
        }
#else
        _ = url
#endif
    }

    static func validate(_ request: URLRequest) throws {
        guard let url = request.url else { throw PolicyError.blockedExternalEndpoint }
        try self.validate(url)
    }

    /// A session with proxying, cookies, credentials, caching, and external redirects
    /// removed from the hardened build's network path.
    static let session: URLSession = makeSession(configuration: .default)

    static func makeSession(configuration: URLSessionConfiguration) -> URLSession {
#if HARDENED
        configuration.connectionProxyDictionary = [:]
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration, delegate: RedirectDelegate(), delegateQueue: nil)
#else
        return URLSession(configuration: configuration)
#endif
    }
}

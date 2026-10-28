import Foundation

@main
struct HardenedNetworkPolicyTests {
    static func main() throws {
        let allowed = [
            "http://localhost:11434/api/chat",
            "https://localhost/v1/models",
            "http://127.0.0.1:1234/v1/chat/completions",
            "http://127.255.1.2/test",
            "http://[::1]:11434/api/chat",
        ]
        let blocked = [
            "https://api.openai.com/v1/chat/completions",
            "http://localhost.example.com/",
            "http://10.0.0.1/",
            "http://172.16.0.1/",
            "http://192.168.1.2/",
            "http://2130706433/",
            "http://127.0.0.01/",
            "ftp://localhost/file",
            "file:///tmp/transcript.txt",
        ]

        for value in allowed {
            guard HardenedNetworkPolicy.isLoopbackEndpoint(value) else {
                fatalError("Expected loopback endpoint to be allowed: \(value)")
            }
            try HardenedNetworkPolicy.validate(requireURL(value))
        }

        for value in blocked {
            if HardenedNetworkPolicy.isLoopbackEndpoint(value) {
                fatalError("Expected endpoint to be blocked: \(value)")
            }
            do {
                try HardenedNetworkPolicy.validate(requireURL(value))
                fatalError("Validation unexpectedly allowed: \(value)")
            } catch is HardenedNetworkPolicy.PolicyError {
                continue
            }
        }

        let session = HardenedNetworkPolicy.session
        guard session.delegate != nil else {
            fatalError("Hardened session must install the redirect-validation delegate")
        }
        guard session.configuration.urlCache == nil,
              session.configuration.httpCookieStorage == nil,
              session.configuration.urlCredentialStorage == nil
        else {
            fatalError("Hardened session must disable caches, cookies, and credential storage")
        }

        try verifyRedirectPolicy()

        print("PASS: hardened network policy accepted loopback and rejected every external/LAN fixture")
    }

    private static func requireURL(_ value: String) -> URL {
        guard let url = URL(string: value) else { fatalError("Invalid test fixture: \(value)") }
        return url
    }

    private static func verifyRedirectPolicy() throws {
        let sourceURL = requireURL("http://localhost:11434/start")
        let sourceSession = URLSession(configuration: .ephemeral)
        let task = sourceSession.dataTask(with: sourceURL)
        guard let response = HTTPURLResponse(
            url: sourceURL,
            statusCode: 302,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        ) else {
            fatalError("Unable to construct redirect response fixture")
        }
        let delegate = HardenedNetworkPolicy.RedirectDelegate()

        var externalResult: URLRequest?
        var externalCallbackRan = false
        delegate.urlSession(
            sourceSession,
            task: task,
            willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: requireURL("https://example.com/escape"))
        ) { request in
            externalCallbackRan = true
            externalResult = request
        }
        guard externalCallbackRan, externalResult == nil else {
            fatalError("External redirect must be cancelled")
        }

        var loopbackResult: URLRequest?
        delegate.urlSession(
            sourceSession,
            task: task,
            willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: requireURL("http://127.0.0.1:11434/final"))
        ) { request in
            loopbackResult = request
        }
        guard loopbackResult?.url?.host == "127.0.0.1" else {
            fatalError("Loopback redirect must remain available")
        }
        sourceSession.invalidateAndCancel()
    }
}

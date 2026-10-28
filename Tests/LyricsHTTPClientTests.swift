import Foundation

private final class StubLyricsProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        assert(request.cachePolicy == .reloadIgnoringLocalCacheData)
        if request.url!.path == "/timeout" {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            return
        }
        let status = Int(request.url!.lastPathComponent)!
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
                                                             httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
struct LyricsHTTPClientTests {
    static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubLyricsProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (_, success) = try await LyricsHTTPClient.data(from: URL(string: "https://test.invalid/200")!, session: session)
        assert(success == 200)
        let (_, missing) = try await LyricsHTTPClient.data(from: URL(string: "https://test.invalid/404")!, allowing: [200, 404], session: session)
        assert(missing == 404)
        do {
            _ = try await LyricsHTTPClient.data(from: URL(string: "https://test.invalid/503")!, session: session)
            assertionFailure("503 must not be treated as missing lyrics")
        } catch {
            assert(LyricsHTTPClient.failureMessage(error).contains("503"))
        }
        do {
            _ = try await LyricsHTTPClient.data(from: URL(string: "https://test.invalid/timeout")!, session: session)
            assertionFailure("Timeout must propagate")
        } catch {
            assert(LyricsHTTPClient.failureMessage(error).contains("超时"))
        }
        print("Lyrics HTTP response and cache policy tests passed")
    }
}

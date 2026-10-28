import Foundation
import OSLog

enum LyricsRequestError: Error, LocalizedError {
    case http(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .http(let status): return "歌词服务返回 HTTP \(status)"
        case .invalidResponse: return "歌词服务响应格式异常"
        }
    }
}

enum LyricsHTTPClient {
    nonisolated private static let logger = Logger(subsystem: "com.wangjiayuan.cueto", category: "LyricsHTTP")

    nonisolated static func data(from url: URL, allowing statuses: Set<Int> = [200],
                                 session: URLSession = .shared) async throws -> (Data, Int) {
        // Do not let a cached error page make the manual Retry repeat a failure.
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("Cueto (https://github.com/hnwangjy/cueto)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw LyricsRequestError.invalidResponse }
            logger.info("\(url.path, privacy: .public): HTTP \(http.statusCode), bytes \(data.count)")
            guard statuses.contains(http.statusCode) else { throw LyricsRequestError.http(http.statusCode) }
            guard data.count < 2_000_000 else { throw LyricsRequestError.invalidResponse }
            return (data, http.statusCode)
        } catch {
            logger.error("\(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    nonisolated static func failureMessage(_ error: Error) -> String {
        if let error = error as? LyricsRequestError { return error.localizedDescription }
        if error is DecodingError { return "歌词服务响应格式异常" }
        switch (error as NSError).code {
        case NSURLErrorTimedOut: return "歌词请求超时"
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost: return "歌词网络连接中断"
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: return "无法解析歌词服务地址"
        case NSURLErrorCannotConnectToHost: return "无法连接歌词服务"
        default: return "歌词请求失败（\((error as NSError).code)）"
        }
    }
}

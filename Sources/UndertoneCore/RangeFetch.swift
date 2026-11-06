import Foundation

public enum RangeFetch {
    /// One bounded `bytes=start-end` fetch of a stream, plus the stream's total size from `Content-Range`.
    ///
    /// YouTube throttles open-ended ranges but serves bounded ones at full speed, so every stream read goes through here.
    /// - Throws: `StreamRefused` when the URL itself is dead (re-resolving is the only fix); `URLError` otherwise,
    ///   including for an HTTP 200, since a server that ignores the range would send the whole file on every call.
    public static func fetch(_ url: URL, headers: [String: String], from start: Int64, through end: Int64, session: URLSession) async throws -> (data: Data, total: Int64?) {
        var request = URLRequest(url: url)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        switch http.statusCode {
        case 206:
            return (data, ByteRange.total(fromContentRange: http.value(forHTTPHeaderField: "Content-Range")))
        case 200:
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Stream ignored the byte range (HTTP 200)"])
        case let status where StreamRefused.isRefusal(status):
            throw StreamRefused(statusCode: status)
        default:
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Stream returned HTTP \(http.statusCode)"])
        }
    }

    /// An uncached session for stream bytes: they are large, signed per URL, and kept (if at all) by `AudioCache`.
    public static func makeSession(timeout: TimeInterval? = nil) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        if let timeout { config.timeoutIntervalForRequest = timeout }
        return URLSession(configuration: config)
    }
}

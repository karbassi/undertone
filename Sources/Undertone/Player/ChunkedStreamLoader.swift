import AVFoundation
import Foundation
import UndertoneCore
import UniformTypeIdentifiers
import os

/// Feeds AVPlayer a YouTube stream in bounded byte ranges.
///
/// AVPlayer asks for open-ended ranges (`bytes=N-`), which YouTube throttles to about twice real time
/// (~32 KB/s for a 128 kbps track). Short videos survive that; a two-hour mix never becomes ready, and a
/// seek into it stalls. Bounded ranges are served at full speed, so this loader sits between AVPlayer and
/// the stream and turns every request into a sequence of small `bytes=a-b` fetches.
nonisolated final class ChunkedStreamLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    /// Swapped in for `https` so AVFoundation routes the asset's loads through this delegate.
    static let scheme = "undertone-stream"
    /// Well under the ~10 MB YouTube serves unthrottled; small enough that a seek starts quickly.
    static let chunkSize: Int64 = 1 << 20

    let queue = DispatchQueue(label: "com.jverissimo.undertone.stream-loader")
    private let streamURL: URL
    private let headers: [String: String]
    private let contentType: String
    private let session: URLSession
    private let log = Logger(subsystem: "com.jverissimo.undertone", category: "stream")
    private let state = OSAllocatedUnfairLock(initialState: State())

    private struct State {
        var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
        var contentLength: Int64?
    }

    init(streamURL: URL, headers: [String: String], fileExtension: String?) {
        self.streamURL = streamURL
        self.headers = headers
        contentType = fileExtension.flatMap { UTType(filenameExtension: $0)?.identifier } ?? UTType.mpeg4Movie.identifier
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        session = URLSession(configuration: config)
        super.init()
    }

    /// The URL to hand AVURLAsset: the stream URL with the custom scheme.
    var assetURL: URL {
        var components = URLComponents(url: streamURL, resolvingAgainstBaseURL: false)!
        components.scheme = Self.scheme
        return components.url!
    }

    /// Stops every in-flight fetch (the item is being replaced or torn down).
    func cancelAll() {
        let tasks = state.withLock { state in
            defer { state.tasks.removeAll() }
            return Array(state.tasks.values)
        }
        tasks.forEach { $0.cancel() }
        session.invalidateAndCancel()
    }

    // MARK: - AVAssetResourceLoaderDelegate

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        let key = ObjectIdentifier(loadingRequest)
        let request = UncheckedRequest(value: loadingRequest)
        let task = Task { [weak self] in
            await self?.serve(request.value)
            _ = self?.state.withLock { $0.tasks.removeValue(forKey: key) }
        }
        state.withLock { $0.tasks[key] = task }
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        state.withLock { $0.tasks.removeValue(forKey: ObjectIdentifier(loadingRequest)) }?.cancel()
    }

    // MARK: - Serving

    private func serve(_ request: AVAssetResourceLoadingRequest) async {
        do {
            if let info = request.contentInformationRequest {
                info.contentType = contentType
                info.contentLength = try await contentLength()
                info.isByteRangeAccessSupported = true
            }
            if let dataRequest = request.dataRequest {
                let total = try await contentLength()
                var offset = dataRequest.currentOffset
                let end = dataRequest.requestsAllDataToEndOfResource
                    ? total
                    : min(total, dataRequest.requestedOffset + Int64(dataRequest.requestedLength))
                while offset < end {
                    try Task.checkCancellation()
                    let chunk = try await fetch(from: offset, through: min(end, offset + Self.chunkSize) - 1)
                    guard !chunk.isEmpty else {
                        throw URLError(.zeroByteResource, userInfo: [NSLocalizedDescriptionKey: "Stream returned no bytes at offset \(offset)"])
                    }
                    try Task.checkCancellation()
                    dataRequest.respond(with: chunk)
                    offset += Int64(chunk.count)
                }
            }
            request.finishLoading()
        } catch is CancellationError {
            // AVFoundation cancelled the request (seek, buffer full, item replaced); it expects no reply.
        } catch let error as URLError where error.code == .cancelled {
            // Same, surfaced by URLSession.
        } catch {
            log.error("stream fetch failed: \(error.localizedDescription, privacy: .public)")
            request.finishLoading(with: error)
        }
    }

    private func contentLength() async throws -> Int64 {
        if let known = state.withLock({ $0.contentLength }) { return known }
        _ = try await fetch(from: 0, through: 1)   // records the total from Content-Range
        guard let known = state.withLock({ $0.contentLength }) else { throw URLError(.cannotParseResponse) }
        return known
    }

    private func fetch(from start: Int64, through end: Int64) async throws -> Data {
        var request = URLRequest(url: streamURL)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        switch http.statusCode {
        case 206:
            if let total = ByteRange.total(fromContentRange: http.value(forHTTPHeaderField: "Content-Range")) {
                state.withLock { $0.contentLength = total }
            }
            return data
        case 200:
            // Server ignored the range and sent the whole resource.
            state.withLock { $0.contentLength = Int64(data.count) }
            let lower = Int(min(start, Int64(data.count)))
            let upper = Int(min(end + 1, Int64(data.count)))
            return data.subdata(in: lower..<upper)
        default:
            // 403 means the signed URL expired or was refused; the player's recovery re-resolves it.
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Stream returned HTTP \(http.statusCode)"])
        }
    }
}

/// AVAssetResourceLoadingRequest is not Sendable; each one is only touched by the task serving it.
private struct UncheckedRequest: @unchecked Sendable {
    let value: AVAssetResourceLoadingRequest
}

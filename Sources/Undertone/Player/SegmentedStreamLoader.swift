import AVFoundation
import Foundation
import UndertoneCore
import UniformTypeIdentifiers
import os

/// Streams a YouTube file as HLS: an in-memory media playlist whose segments are byte ranges of the stream.
///
/// Opened as a plain file, YouTube's fragmented MP4 gets read front to back (all 115 MB of a two-hour mix, even
/// through ChunkedStreamLoader) and AVFoundation reports double its duration. The file's `sidx` box lists every
/// segment, so this turns it into a playlist instead. AVPlayer then fetches only the segments it is about to play,
/// each as a bounded range that YouTube serves at full speed, and takes the exact duration from the list.
nonisolated final class SegmentedStreamLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    /// AVFoundation hands URLs with this scheme (only the playlist) to this delegate; segments go to YouTube directly.
    static let scheme = "undertone-hls"
    /// `ftyp`, `moov` and `sidx` together: about 9 KB for a two-hour mix, so one fetch nearly always covers them.
    static let initialFetch: Int64 = 64 << 10
    /// No index within this many leading bytes means the file is not laid out as expected.
    static let indexByteLimit: Int64 = 4 << 20
    /// Left alone, AVPlayer buffers about 15 minutes of an HLS audio stream (~15 MB) and refills that after every
    /// seek. Five minutes (~5 MB) still rides out any network hiccup.
    static let forwardBufferDuration: TimeInterval = 5 * 60

    let queue = DispatchQueue(label: "com.jverissimo.undertone.playlist-loader")
    let assetURL = URL(string: "\(scheme)://stream/playlist.m3u8")!
    private let playlist: Data
    private static let log = Logger(subsystem: "com.jverissimo.undertone", category: "stream")

    private init(playlist: Data) {
        self.playlist = playlist
        super.init()
    }

    /// Reads the stream's segment index and builds the playlist from it; nil if the stream has no index this can use.
    static func load(streamURL: URL, headers: [String: String]) async -> SegmentedStreamLoader? {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        var data = Data()
        var wanted = initialFetch
        do {
            while true {
                let (chunk, total) = try await fetch(streamURL, headers: headers, from: Int64(data.count), through: wanted - 1, session: session)
                guard !chunk.isEmpty else { throw URLError(.zeroByteResource) }
                data.append(chunk)
                switch try SegmentIndex.parse(data) {
                case .index(let index):
                    // The segments must tile the rest of the file exactly, or the index is not describing this stream.
                    // An unknown total (`bytes …/*`) cannot be checked, so it fails too.
                    guard index.coversFile(ofLength: total) else {
                        log.error("segment index does not cover the stream; using the chunked loader")
                        return nil
                    }
                    log.notice("segment index: \(index.segments.count) segments from \(data.count) leading bytes")
                    return SegmentedStreamLoader(playlist: Data(HLSPlaylist.media(index, url: streamURL).utf8))
                case .needsBytes(let needed):
                    guard needed <= indexByteLimit else { throw SegmentIndex.ParseError.noIndex }
                    wanted = min(indexByteLimit, max(needed, Int64(data.count) * 2))
                }
            }
        } catch {
            if !Task.isCancelled {
                log.error("no segment index (\(String(describing: error), privacy: .public)); using the chunked loader")
            }
            return nil
        }
    }

    /// A bounded range of the stream, plus the stream's total size from `Content-Range`.
    private static func fetch(_ url: URL, headers: [String: String], from start: Int64, through end: Int64, session: URLSession) async throws -> (Data, Int64?) {
        var request = URLRequest(url: url)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 206 else { throw URLError(.badServerResponse) }
        return (data, ByteRange.total(fromContentRange: http.value(forHTTPHeaderField: "Content-Range")))
    }

    // MARK: - AVAssetResourceLoaderDelegate

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard loadingRequest.request.url?.scheme == Self.scheme else { return false }
        if let info = loadingRequest.contentInformationRequest {
            info.contentType = UTType.m3uPlaylist.identifier
            info.contentLength = Int64(playlist.count)
            info.isByteRangeAccessSupported = true
        }
        if let dataRequest = loadingRequest.dataRequest {
            let start = Int(min(dataRequest.requestedOffset, Int64(playlist.count)))
            let end = dataRequest.requestsAllDataToEndOfResource ? playlist.count : min(playlist.count, start + dataRequest.requestedLength)
            dataRequest.respond(with: playlist.subdata(in: start..<end))
        }
        loadingRequest.finishLoading()
        return true
    }
}

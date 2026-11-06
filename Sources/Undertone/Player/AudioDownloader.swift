import Foundation
import UndertoneCore
import os

/// Downloads a track's whole stream into `AudioCache`, so the next play of it needs no network.
///
/// The player streams only what it is about to play and keeps none of it (HLS segments go straight from YouTube to
/// AVFoundation), so the file is fetched separately, one bounded range at a time like the loaders, and committed only
/// once every byte is on disk.
nonisolated enum AudioDownloader {
    /// Big enough to keep the request count low, still well under the ~10 MB YouTube serves unthrottled.
    static let chunkSize: Int64 = 4 << 20

    enum Failure: Error {
        case tooLarge(Int64)
        case unknownLength
        case shortRead(at: Int64)
    }

    private static let log = Logger(subsystem: "com.jverissimo.undertone", category: "audio-cache")

    /// Off the main actor: the writes and the final move are blocking file I/O.
    @concurrent
    static func download(_ track: Track, key: String, into cache: AudioCache) async throws {
        let part = try cache.preparePartFile(forKey: key)
        let session = RangeFetch.makeSession(timeout: 30)
        defer { session.invalidateAndCancel() }
        do {
            let handle = try FileHandle(forWritingTo: part)
            defer { try? handle.close() }
            var offset: Int64 = 0
            var total: Int64?
            repeat {
                try Task.checkCancellation()
                let end = min(offset + chunkSize, total ?? .max) - 1
                let (data, reported) = try await RangeFetch.fetch(track.streamURL, headers: track.httpHeaders, from: offset, through: end, session: session)
                if total == nil {
                    guard let reported else { throw Failure.unknownLength }
                    guard reported <= cache.maxFileSize else { throw Failure.tooLarge(reported) }
                    total = reported
                }
                guard !data.isEmpty else { throw Failure.shortRead(at: offset) }
                try handle.write(contentsOf: data)
                offset += Int64(data.count)
            } while offset < total!
            try handle.close()
            try Task.checkCancellation()
            try cache.commit(partFile: part, track: track, forKey: key)
            log.notice("cached \(key, privacy: .public) (\(offset) bytes)")
        } catch {
            try? FileManager.default.removeItem(at: part)
            throw error
        }
    }
}

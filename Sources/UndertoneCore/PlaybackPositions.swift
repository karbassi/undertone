import Foundation

public struct SavedPosition: Codable, Equatable, Sendable {
    public var seconds: Double
    public var duration: Double
    public var updatedAt: Date

    public init(seconds: Double, duration: Double, updatedAt: Date) {
        self.seconds = seconds
        self.duration = duration
        self.updatedAt = updatedAt
    }
}

/// Where each long track was left, so a mix picks up where it stopped. Keyed by `MediaLink.cacheKey`.
public struct PlaybackPositions: Equatable, Sendable {
    public static let limit = 200
    /// Only tracks at least this long are remembered: a mix or a podcast, not a song in a playlist.
    public static let minimumDuration: Double = 10 * 60
    /// This close to either end counts as not started / finished, and forgets the track.
    public static let edgeMargin: Double = 30

    public private(set) var entries: [String: SavedPosition]

    /// Keeps only the newest `limit` entries, so an oversized dictionary or saved payload starts within the cap
    /// that `record` then maintains.
    public init(entries: [String: SavedPosition] = [:]) {
        guard entries.count > Self.limit else {
            self.entries = entries
            return
        }
        let newest = entries.sorted { $0.value.updatedAt > $1.value.updatedAt }.prefix(Self.limit)
        self.entries = Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
    }

    public init(decoding data: Data) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.init(entries: (try? decoder.decode([String: SavedPosition].self, from: data)) ?? [:])
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(entries)
    }

    public subscript(key: String) -> SavedPosition? { entries[key] }

    /// Where to start `key`: a saved position beats the link's own `t=`, since copied links often carry one by accident.
    public func start(forKey key: String, linkStart: Double?) -> Double? {
        entries[key]?.seconds ?? linkStart
    }

    /// The saved position for a pasted or stored link, if any.
    public func position(for url: URL) -> SavedPosition? {
        LinkParser.parse(url.absoluteString).flatMap { entries[$0.cacheKey] }
    }

    /// Remembers `seconds` into a track of `duration`. Near the start or the end it forgets the track
    /// instead, so a finished mix starts over and one barely begun isn't worth resuming. A track now
    /// shorter than `minimumDuration` (a video trimmed since) is forgotten too.
    public mutating func record(_ seconds: Double, duration: Double?, forKey key: String, at date: Date = Date()) {
        guard let duration, seconds.isFinite else { return }
        guard duration >= Self.minimumDuration, seconds >= Self.edgeMargin, seconds <= duration - Self.edgeMargin else {
            entries[key] = nil
            return
        }
        entries[key] = SavedPosition(seconds: seconds, duration: duration, updatedAt: date)
        if entries.count > Self.limit, let oldest = entries.min(by: { $0.value.updatedAt < $1.value.updatedAt })?.key {
            entries[oldest] = nil
        }
    }

    public mutating func forget(_ key: String) {
        entries[key] = nil
    }
}

import Foundation

/// Whole audio files of tracks already played, kept on disk so a replay needs no network at all.
///
/// `StreamCache` only remembers stream URLs, which expire within hours; this keeps the bytes. Each entry is two files
/// in `directory`: the audio, and a JSON sidecar with the `Track` (so a replay skips yt-dlp even after its URL expired)
/// and the audio's size. The sidecar is written last and checked against the audio on every read, so a half-written
/// or half-purged entry is simply a miss. The directory itself is the index, since macOS may purge Caches at any time.
/// Least recently played entries are evicted once the total passes `capacity`.
public struct AudioCache: Sendable {
    /// Decimal, like Finder and ByteCountFormatter: Settings shows "2 GB", not "2.15 GB".
    public static let defaultCapacity: Int64 = 2_000_000_000

    public struct Entry: Codable, Equatable, Sendable {
        public let track: Track
        public let fileName: String
        public let byteCount: Int64
    }

    public struct Usage: Equatable, Sendable {
        public let key: String
        public let byteCount: Int64
        public let lastPlayed: Date
    }

    public let directory: URL
    public let capacity: Int64

    public init(directory: URL, capacity: Int64 = defaultCapacity) {
        self.directory = directory
        self.capacity = capacity
    }

    /// `~/Library/Caches/<bundle id>/Audio`.
    public static func standard(bundleIdentifier: String?) -> AudioCache {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return AudioCache(directory: caches.appending(path: bundleIdentifier ?? "com.jverissimo.undertone").appending(path: "Audio"))
    }

    /// Larger files are not worth caching: a quarter of the cap (500 MB of a 2 GB cap is about eight and a half hours of audio).
    public var maxFileSize: Int64 { capacity / 4 }

    // MARK: - Paths

    private static let sidecarExtension = "json"
    private static let partExtension = "part"
    private static let keyCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")

    /// A filesystem-safe name for `key` (a YouTube id is already one; a URL key gets percent-encoded).
    static func baseName(forKey key: String) -> String {
        key.addingPercentEncoding(withAllowedCharacters: keyCharacters) ?? String(key.hashValue)
    }

    private func sidecarURL(forKey key: String) -> URL {
        directory.appending(path: Self.baseName(forKey: key)).appendingPathExtension(Self.sidecarExtension)
    }

    /// Where a download in progress writes; `commit` moves it into place.
    public func partURL(forKey key: String) -> URL {
        directory.appending(path: Self.baseName(forKey: key)).appendingPathExtension(Self.partExtension)
    }

    // MARK: - Reading

    /// The cached track and its audio file, or nil unless both are present and the file is complete.
    public func entry(forKey key: String) -> (track: Track, file: URL)? {
        guard let entry = readEntry(at: sidecarURL(forKey: key)) else { return nil }
        let file = directory.appending(path: entry.fileName)
        guard Self.size(of: file) == entry.byteCount else { return nil }
        return (entry.track, file)
    }

    public func contains(_ key: String) -> Bool { entry(forKey: key) != nil }

    /// Marks `key` as just played, so eviction keeps it longest.
    public func touch(_ key: String, now: Date = Date()) {
        try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: sidecarURL(forKey: key).path)
    }

    /// Bytes on disk: every complete entry plus anything in progress or orphaned.
    public var totalSize: Int64 {
        files().reduce(0) { $0 + (Self.size(of: $1) ?? 0) }
    }

    /// Every complete entry, with its size and when it was last played.
    public func usage() -> [Usage] {
        files().filter { $0.pathExtension == Self.sidecarExtension }.compactMap { sidecar in
            guard let entry = readEntry(at: sidecar),
                  let size = Self.size(of: directory.appending(path: entry.fileName)), size == entry.byteCount else { return nil }
            let played = (try? sidecar.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return Usage(key: sidecar.deletingPathExtension().lastPathComponent.removingPercentEncoding ?? "", byteCount: size, lastPlayed: played)
        }
    }

    // MARK: - Writing

    /// Moves a finished download into the cache, then evicts down to `capacity` (never `key` itself).
    @discardableResult
    public func commit(partFile: URL, track: Track, forKey key: String, now: Date = Date()) throws -> URL {
        let fm = FileManager.default
        guard let byteCount = Self.size(of: partFile), byteCount > 0 else { throw CocoaError(.fileReadCorruptFile) }
        remove(forKey: key)
        let fileName = Self.baseName(forKey: key) + "." + (track.streamExtension ?? "m4a")
        let file = directory.appending(path: fileName)
        try fm.moveItem(at: partFile, to: file)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(Entry(track: track, fileName: fileName, byteCount: byteCount)).write(to: sidecarURL(forKey: key), options: .atomic)
        touch(key, now: now)
        evict(keeping: key)
        return file
    }

    /// Prepares the directory for a download: creates it and clears any earlier partial file for `key`.
    public func preparePartFile(forKey key: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let part = partURL(forKey: key)
        try? FileManager.default.removeItem(at: part)
        guard FileManager.default.createFile(atPath: part.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        return part
    }

    public func remove(forKey key: String) {
        let sidecar = sidecarURL(forKey: key)
        // The sidecar goes first: without it the audio is already a miss, whatever happens next.
        let fileName = readEntry(at: sidecar)?.fileName
        try? FileManager.default.removeItem(at: sidecar)
        if let fileName { try? FileManager.default.removeItem(at: directory.appending(path: fileName)) }
    }

    public func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Deletes least recently played entries until the cache fits `capacity`, never `keeping`.
    public func evict(keeping: String? = nil) {
        for key in Self.evictionPlan(usage(), capacity: capacity, keeping: keeping) {
            remove(forKey: key)
        }
    }

    /// Deletes leftovers no entry owns: partial downloads and audio whose sidecar is gone. Only safe with no download
    /// running (the app calls it at launch).
    public func sweep() {
        let owned = Set(files().filter { $0.pathExtension == Self.sidecarExtension }.compactMap { readEntry(at: $0)?.fileName })
        for file in files() where file.pathExtension != Self.sidecarExtension && !owned.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// The keys to delete, oldest play first, so the rest fit in `capacity`.
    public static func evictionPlan(_ usage: [Usage], capacity: Int64, keeping: String?) -> [String] {
        var total = usage.reduce(0) { $0 + $1.byteCount }
        var plan: [String] = []
        for item in usage.sorted(by: { $0.lastPlayed < $1.lastPlayed }) where total > capacity && item.key != keeping {
            plan.append(item.key)
            total -= item.byteCount
        }
        return plan
    }

    // MARK: - Helpers

    private func readEntry(at sidecar: URL) -> Entry? {
        guard let data = try? Data(contentsOf: sidecar) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Entry.self, from: data)
    }

    private func files() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []
    }

    private static func size(of url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }
}

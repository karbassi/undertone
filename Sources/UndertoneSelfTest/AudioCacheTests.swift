import Foundation
import Testing
@testable import UndertoneCore

@Suite struct AudioCacheTests {
    let now = Date(timeIntervalSince1970: 1_788_500_000)

    func makeCache(capacity: Int64 = 1_000) -> AudioCache {
        AudioCache(directory: FileManager.default.temporaryDirectory.appending(path: "undertone-audio-\(UUID().uuidString)"), capacity: capacity)
    }

    func track(_ id: String) -> Track {
        Track(id: id, title: "T \(id)", duration: 61, streamURL: URL(string: "https://example.com/\(id)")!,
              streamExtension: "m4a", expiresAt: now, extractor: "youtube")
    }

    /// Writes `size` bytes as a finished download and commits it.
    @discardableResult
    func add(_ key: String, size: Int, to cache: AudioCache, at date: Date) throws -> URL {
        let part = try cache.preparePartFile(forKey: key)
        try Data(repeating: 7, count: size).write(to: part)
        return try cache.commit(partFile: part, track: track(key), forKey: key, now: date)
    }

    @Test func commitThenHit() throws {
        let cache = makeCache()
        defer { cache.removeAll() }
        #expect(cache.entry(forKey: "abc") == nil)
        let file = try add("abc", size: 100, to: cache, at: now)
        let hit = try #require(cache.entry(forKey: "abc"))
        #expect(hit.file == file)
        #expect(hit.track == track("abc"))   // the sidecar keeps the whole Track, chapters and all
        #expect(file.pathExtension == "m4a")
        #expect(!FileManager.default.fileExists(atPath: cache.partURL(forKey: "abc").path))
        #expect(cache.usage().map(\.key) == ["abc"])
    }

    @Test func truncatedOrOrphanedFileIsAMiss() throws {
        let cache = makeCache()
        defer { cache.removeAll() }
        let file = try add("abc", size: 100, to: cache, at: now)
        // macOS purged part of the cache, or the file was cut short: never play a partial file.
        try Data(repeating: 7, count: 50).write(to: file)
        #expect(cache.entry(forKey: "abc") == nil)
        #expect(cache.usage().isEmpty)

        // An audio file without its sidecar and a leftover .part are swept; a complete entry is not.
        try add("keep", size: 10, to: cache, at: now)
        cache.remove(forKey: "abc")
        try Data(repeating: 1, count: 5).write(to: cache.directory.appending(path: "orphan.m4a"))
        _ = try cache.preparePartFile(forKey: "stale")
        cache.sweep()
        let names = try FileManager.default.contentsOfDirectory(atPath: cache.directory.path).sorted()
        #expect(names == ["keep.json", "keep.m4a"])
    }

    @Test func evictsLeastRecentlyPlayedButNeverTheKeptKey() throws {
        let cache = makeCache(capacity: 250)
        defer { cache.removeAll() }
        try add("a", size: 100, to: cache, at: now)
        try add("b", size: 100, to: cache, at: now.addingTimeInterval(10))
        cache.touch("a", now: now.addingTimeInterval(20))   // replayed: now b is the oldest
        try add("c", size: 100, to: cache, at: now.addingTimeInterval(30))
        #expect(cache.contains("a"))
        #expect(!cache.contains("b"))
        #expect(cache.contains("c"))
    }

    @Test func evictionPlan() {
        let usage = [
            AudioCache.Usage(key: "old", byteCount: 400, lastPlayed: now),
            AudioCache.Usage(key: "mid", byteCount: 400, lastPlayed: now.addingTimeInterval(1)),
            AudioCache.Usage(key: "new", byteCount: 400, lastPlayed: now.addingTimeInterval(2)),
        ]
        #expect(AudioCache.evictionPlan(usage, capacity: 1_200, keeping: nil).isEmpty)
        #expect(AudioCache.evictionPlan(usage, capacity: 800, keeping: nil) == ["old"])
        #expect(AudioCache.evictionPlan(usage, capacity: 500, keeping: nil) == ["old", "mid"])
        // The playing track is skipped even when it is the oldest.
        #expect(AudioCache.evictionPlan(usage, capacity: 800, keeping: "old") == ["mid"])
        #expect(AudioCache.evictionPlan(usage, capacity: 0, keeping: "new") == ["old", "mid"])
    }

    @Test func urlKeysAreFileSafeAndRoundTrip() throws {
        let cache = makeCache()
        defer { cache.removeAll() }
        let key = "https://soundcloud.com/a/b?x=1"
        let file = try add(key, size: 10, to: cache, at: now)
        #expect(!file.lastPathComponent.contains("/"))
        #expect(cache.entry(forKey: key) != nil)
        #expect(cache.usage().map(\.key) == [key])
    }

    @Test func removeAllEmptiesIt() throws {
        let cache = makeCache()
        try add("a", size: 10, to: cache, at: now)
        #expect(cache.totalSize > 0)
        cache.removeAll()
        #expect(cache.totalSize == 0)
        #expect(cache.entry(forKey: "a") == nil)
    }
}

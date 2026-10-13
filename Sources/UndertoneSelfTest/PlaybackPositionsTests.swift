import Foundation
import Testing
@testable import UndertoneCore

@Suite struct PlaybackPositionsTests {
    let mix = 7115.0

    @Test func remembersAndRoundTrips() throws {
        var store = PlaybackPositions()
        store.record(2843, duration: mix, forKey: "p8ug6mn93xk", at: Date(timeIntervalSince1970: 1))
        #expect(store["p8ug6mn93xk"]?.seconds == 2843)
        #expect(store["p8ug6mn93xk"]?.duration == mix)

        store.record(2900, duration: mix, forKey: "p8ug6mn93xk", at: Date(timeIntervalSince1970: 2))
        #expect(store["p8ug6mn93xk"]?.seconds == 2900)
        #expect(store.entries.count == 1)

        let decoded = PlaybackPositions(decoding: try store.encoded())
        #expect(decoded == store)
        #expect(PlaybackPositions(decoding: Data("garbage".utf8)).entries.isEmpty)
    }

    @Test func ignoresShortTracks() {
        var store = PlaybackPositions()
        store.record(120, duration: 213, forKey: "dQw4w9WgXcQ")
        store.record(120, duration: nil, forKey: "unknown")
        #expect(store.entries.isEmpty)
    }

    @Test func forgetsNearEitherEnd() {
        var store = PlaybackPositions()
        store.record(1000, duration: mix, forKey: "a")
        store.record(10, duration: mix, forKey: "a")
        #expect(store["a"] == nil)

        store.record(1000, duration: mix, forKey: "a")
        store.record(mix - 5, duration: mix, forKey: "a")
        #expect(store["a"] == nil)

        store.record(1000, duration: mix, forKey: "a")
        store.forget("a")
        #expect(store["a"] == nil)
    }

    @Test func savedPositionBeatsTheLinksTimestamp() {
        var store = PlaybackPositions()
        store.record(2843, duration: mix, forKey: "a")
        #expect(store.start(forKey: "a", linkStart: 5) == 2843)
        #expect(store.start(forKey: "b", linkStart: 5) == 5)
        #expect(store.start(forKey: "b", linkStart: nil) == nil)
    }

    @Test func dropsTheOldestPastTheLimit() {
        var store = PlaybackPositions()
        for i in 0...PlaybackPositions.limit {
            store.record(1000, duration: mix, forKey: "v\(i)", at: Date(timeIntervalSince1970: Double(i)))
        }
        #expect(store.entries.count == PlaybackPositions.limit)
        #expect(store["v0"] == nil)
        #expect(store["v\(PlaybackPositions.limit)"] != nil)
    }

    @Test func trimsAnOversizedStoreToTheNewest() throws {
        let limit = PlaybackPositions.limit
        var oversized: [String: SavedPosition] = [:]
        for i in 0..<(limit + 5) {
            oversized["v\(i)"] = SavedPosition(seconds: 1000, duration: mix, updatedAt: Date(timeIntervalSince1970: Double(i)))
        }

        let store = PlaybackPositions(entries: oversized)
        #expect(store.entries.count == limit)
        for i in 0..<5 { #expect(store["v\(i)"] == nil) }
        #expect(store["v\(limit + 4)"] != nil)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoded = PlaybackPositions(decoding: try encoder.encode(oversized))
        #expect(decoded.entries.count == limit)
        #expect(decoded["v0"] == nil)
    }
}

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

    @Test func dropsTheOldestPastTheLimit() {
        var store = PlaybackPositions()
        for i in 0...PlaybackPositions.limit {
            store.record(1000, duration: mix, forKey: "v\(i)", at: Date(timeIntervalSince1970: Double(i)))
        }
        #expect(store.entries.count == PlaybackPositions.limit)
        #expect(store["v0"] == nil)
        #expect(store["v\(PlaybackPositions.limit)"] != nil)
    }

    @Test func looksUpAnyFormOfTheLink() {
        var store = PlaybackPositions()
        store.record(1000, duration: mix, forKey: "p8ug6mn93xk")
        #expect(store.position(for: URL(string: "https://www.youtube.com/watch?v=p8ug6mn93xk&t=5s")!)?.seconds == 1000)
        #expect(store.position(for: URL(string: "https://www.youtube.com/watch?v=p8ug6mn93xk&amp;t=5s")!)?.seconds == 1000)
        #expect(store.position(for: URL(string: "https://youtu.be/p8ug6mn93xk")!)?.seconds == 1000)
        #expect(store.position(for: URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!) == nil)
    }
}

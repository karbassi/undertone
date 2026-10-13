import Foundation
import Testing
@testable import UndertoneCore

@Suite struct ChapterTests {
    func mix() throws -> Track {
        try Track.decode(fromYTDLPJSON: Data(Fixtures.mixJSON.utf8))
    }

    func track(chapterStarts starts: [Double]) -> Track {
        var track = Track(id: "x", title: "t", streamURL: URL(string: "https://example.com/a.m4a")!)
        track.chapters = starts.enumerated().map { Chapter(start: $1, title: "C\($0)") }
        return track
    }

    @Test func decodesChapters() throws {
        let chapters = try mix().chapters
        #expect(chapters.count == 4)
        #expect(chapters[0] == Chapter(start: 0, end: 254, title: "Tube & Berger, Milan Euringer - Lovebreak (Original Mix)"))
        #expect(chapters[1].start == 254)
        #expect(chapters[3].title == "Yves Murasca, Meines - Mazunte (Extended Mix)")
    }

    @Test func videoWithoutChaptersHasNone() throws {
        #expect(try Track.decode(fromYTDLPJSON: Data(Fixtures.videoJSON.utf8)).chapters.isEmpty)
        let nullChapters = #"{"id": "x", "url": "https://example.com/a.m4a", "chapters": null}"#
        #expect(try Track.decode(fromYTDLPJSON: Data(nullChapters.utf8)).chapters.isEmpty)
    }

    @Test func sortsChaptersAndFillsGaps() throws {
        let json = """
        {"id": "x", "url": "https://example.com/a.m4a", "chapters": [
          {"start_time": 120, "title": "Second"}, {"title": "No start"}, {"start_time": 0, "title": " "}, {"start_time": 300}
        ]}
        """
        let chapters = try Track.decode(fromYTDLPJSON: Data(json.utf8)).chapters
        #expect(chapters.map(\.start) == [0, 120, 300])
        #expect(chapters.map(\.title) == ["Chapter 1", "Second", "Chapter 3"])
    }

    @Test func streamsCachedBeforeChaptersStillDecode() {
        // A cache entry written by a build that had no `chapters` field.
        let old = """
        {"aqz-KE-bpKQ": {"track": {"id": "aqz-KE-bpKQ", "title": "Big Buck Bunny", "channel": "Blender", "duration": 635, "streamURL": "https://example.com/a.m4a", "httpHeaders": {"User-Agent": "ua"}, "expiresAt": "2026-09-05T12:00:00Z", "extractor": "youtube"}, "storedAt": "2026-09-05T06:00:00Z"}}
        """
        let cache = StreamCache(decoding: Data(old.utf8))
        #expect(cache.count == 1)
        let track = cache.entries["aqz-KE-bpKQ"]?.track
        #expect(track?.title == "Big Buck Bunny")
        #expect(track?.duration == 635)
        #expect(track?.chapters == [])
    }

    @Test func chaptersRoundTripThroughTheCache() throws {
        var cache = StreamCache()
        let now = Date(timeIntervalSince1970: 1_788_500_000)
        cache.store(try mix(), forKey: "p8ug6mn93xk", now: now)
        let decoded = StreamCache(decoding: try cache.encoded())
        #expect(decoded == cache)
        #expect(decoded.track(forKey: "p8ug6mn93xk", now: now)?.chapters.count == 4)
    }

    @Test func findsTheChapterAtATime() throws {
        let mix = try mix()
        #expect(mix.chapter(at: 0)?.start == 0)
        #expect(mix.chapter(at: 253)?.start == 0)
        #expect(mix.chapter(at: 254)?.start == 254)
        #expect(mix.chapter(at: 253.8)?.start == 254, "a boundary observer can fire a hair early")
        #expect(mix.chapter(at: 5000)?.start == 690, "the last chapter runs to the end")
        #expect(track(chapterStarts: []).chapter(at: 10) == nil)
        #expect(track(chapterStarts: [30, 90]).chapter(at: 10) == nil, "an intro before the first chapter")
    }

    @Test func nextChapterStart() throws {
        let mix = try mix()
        #expect(mix.nextChapterStart(after: 0) == 254)
        #expect(mix.nextChapterStart(after: 300) == 502)
        #expect(mix.nextChapterStart(after: 253.8) == 502)
        #expect(mix.nextChapterStart(after: 700) == nil)
        #expect(track(chapterStarts: []).nextChapterStart(after: 0) == nil)
        #expect(track(chapterStarts: [30, 90]).nextChapterStart(after: 10) == 30)
    }

    @Test func previousChapterStartRestartsAfterThreeSeconds() throws {
        let mix = try mix()
        #expect(mix.previousChapterStart(from: 260) == 254, "6 s in: restart this chapter")
        #expect(mix.previousChapterStart(from: 256) == 0, "2 s in: go to the one before")
        #expect(mix.previousChapterStart(from: 504) == 254)
        #expect(mix.previousChapterStart(from: 600) == 502)
        #expect(mix.previousChapterStart(from: 2) == 0)
        #expect(track(chapterStarts: []).previousChapterStart(from: 100) == nil)
        #expect(track(chapterStarts: [30, 90]).previousChapterStart(from: 10) == 0)
        #expect(track(chapterStarts: [30, 90]).previousChapterStart(from: 31) == 0)
    }
}

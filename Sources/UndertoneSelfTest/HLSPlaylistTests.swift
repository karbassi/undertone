import Foundation
import Testing
@testable import UndertoneCore

@Suite struct HLSPlaylistTests {
    let url = URL(string: "https://rr3---sn-h5qzen7s.googlevideo.com/videoplayback?expire=1788564066&itag=140&mime=audio%2Fmp4&sig=abc")!

    @Test func listsEachSegmentAsAByteRangeOfTheStream() {
        let index = SegmentIndex(initRange: 0..<723, timescale: 44100, segments: [
            .init(offset: 9311, size: 162_288, duration: 440_320 / 44100.0),
            .init(offset: 171_599, size: 161_441, duration: 10.5),
            .init(offset: 333_040, size: 80_000, duration: 4.25),
        ])
        let u = url.absoluteString
        #expect(HLSPlaylist.media(index, url: url) == """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-PLAYLIST-TYPE:VOD
        #EXT-X-TARGETDURATION:11
        #EXT-X-MAP:URI="\(u)",BYTERANGE="723@0"
        #EXTINF:9.984580,
        #EXT-X-BYTERANGE:162288@9311
        \(u)
        #EXTINF:10.500000,
        #EXT-X-BYTERANGE:161441@171599
        \(u)
        #EXTINF:4.250000,
        #EXT-X-BYTERANGE:80000@333040
        \(u)
        #EXT-X-ENDLIST

        """)
    }

    @Test func targetDurationRoundsTheLongestSegmentUp() {
        func target(_ durations: [Double]) -> String? {
            let index = SegmentIndex(initRange: 0..<100, timescale: 1000, segments: durations.enumerated().map {
                .init(offset: Int64(100 + $0.offset * 10), size: 10, duration: $0.element)
            })
            return HLSPlaylist.media(index, url: url).split(separator: "\n").first { $0.hasPrefix("#EXT-X-TARGETDURATION:") }.map(String.init)
        }
        #expect(target([9.98, 10.0]) == "#EXT-X-TARGETDURATION:10")
        #expect(target([9.98, 10.001]) == "#EXT-X-TARGETDURATION:11")
        #expect(target([0.5]) == "#EXT-X-TARGETDURATION:1")
    }
}

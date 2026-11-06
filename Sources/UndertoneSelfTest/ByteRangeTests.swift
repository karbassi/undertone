import Testing
@testable import UndertoneCore

@Suite struct ByteRangeTests {
    @Test func parsesContentRangeTotals() {
        #expect(ByteRange.total(fromContentRange: "bytes 0-1/115150454") == 115_150_454)
        #expect(ByteRange.total(fromContentRange: "bytes 0-1/*") == nil)
        #expect(ByteRange.total(fromContentRange: nil) == nil)
    }

    @Test func refusedStatusesMeanTheURLIsDead() {
        #expect(StreamRefused.isRefusal(403))
        #expect(StreamRefused.isRefusal(410))
        #expect(!StreamRefused.isRefusal(206))
        #expect(!StreamRefused.isRefusal(500))   // a server hiccup, not a dead URL
        #expect(StreamRefused(statusCode: 403).localizedDescription == "Stream returned HTTP 403")
    }
}

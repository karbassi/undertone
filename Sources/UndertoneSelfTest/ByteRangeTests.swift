import Testing
@testable import UndertoneCore

@Suite struct ByteRangeTests {
    @Test func parsesContentRangeTotals() {
        #expect(ByteRange.total(fromContentRange: "bytes 0-1/115150454") == 115_150_454)
        #expect(ByteRange.total(fromContentRange: "bytes 0-1/*") == nil)
        #expect(ByteRange.total(fromContentRange: nil) == nil)
    }
}

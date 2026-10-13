import Foundation
import Testing
@testable import UndertoneCore

/// Builds ISO-BMFF boxes byte by byte, laid out like YouTube's DASH audio.
enum MP4 {
    static func be(_ value: UInt64, _ width: Int) -> [UInt8] {
        (0..<width).reversed().map { UInt8(truncatingIfNeeded: value >> (8 * UInt64($0))) }
    }

    static func box(_ type: String, _ payload: [UInt8] = []) -> [UInt8] {
        be(UInt64(8 + payload.count), 4) + Array(type.utf8) + payload
    }

    /// A box with a 64-bit `largesize` header.
    static func largeBox(_ type: String, _ payload: [UInt8] = []) -> [UInt8] {
        be(1, 4) + Array(type.utf8) + be(UInt64(16 + payload.count), 8) + payload
    }

    static let ftyp = box("ftyp", Array("dash".utf8) + be(0, 4) + Array("iso6mp41".utf8))
    static let moov = box("moov", box("mvhd", [UInt8](repeating: 0, count: 100)))

    /// `references` are (referenced_size, subsegment_duration) pairs; `hierarchical` marks the first as pointing at a `sidx`.
    static func sidx(version: UInt8 = 0, timescale: UInt32 = 44100, firstOffset: UInt64 = 0,
                     references: [(UInt32, UInt32)], hierarchical: Bool = false) -> [UInt8] {
        var payload = [version, 0, 0, 0] + be(1, 4) + be(UInt64(timescale), 4)
        payload += version == 0 ? be(0, 4) + be(firstOffset, 4) : be(0, 8) + be(firstOffset, 8)
        payload += be(0, 2) + be(UInt64(references.count), 2)
        for (i, (size, ticks)) in references.enumerated() {
            let type: UInt64 = hierarchical && i == 0 ? 1 << 31 : 0
            payload += be(type | UInt64(size), 4) + be(UInt64(ticks), 4) + be(0x9000_0000, 4)
        }
        return box("sidx", payload)
    }
}

@Suite struct SegmentIndexTests {
    let references: [(UInt32, UInt32)] = [(161_490, 440_320), (161_441, 440_320), (80_000, 220_160)]

    func parse(_ bytes: [UInt8]) throws -> SegmentIndex.ParseResult {
        try SegmentIndex.parse(Data(bytes))
    }

    @Test func readsAVersion0Index() throws {
        let sidx = MP4.sidx(references: references)
        let file = MP4.ftyp + MP4.moov + sidx + MP4.box("moof") + MP4.box("mdat")
        guard case .index(let index) = try parse(file) else { Issue.record("expected an index"); return }

        let initEnd = Int64(MP4.ftyp.count + MP4.moov.count)
        let sidxEnd = initEnd + Int64(sidx.count)
        #expect(index.initRange == 0..<initEnd)
        #expect(index.timescale == 44100)
        let tenSeconds: Double = 440_320.0 / 44100.0   // 9.98 s, as YouTube cuts them
        let expected: [SegmentIndex.Segment] = [
            .init(offset: sidxEnd, size: 161_490, duration: tenSeconds),
            .init(offset: sidxEnd + 161_490, size: 161_441, duration: tenSeconds),
            .init(offset: sidxEnd + 322_931, size: 80_000, duration: tenSeconds / 2),
        ]
        #expect(index.segments == expected)
        #expect(index.segments.last?.end == sidxEnd + 402_931)
    }

    @Test func readsAVersion1IndexWithAFirstOffset() throws {
        let sidx = MP4.sidx(version: 1, timescale: 48000, firstOffset: 100, references: [(5000, 96000), (6000, 48000)])
        let file = MP4.ftyp + MP4.moov + sidx + MP4.box("free", [UInt8](repeating: 0, count: 92))
        guard case .index(let index) = try parse(file) else { Issue.record("expected an index"); return }

        let sidxEnd = Int64(MP4.ftyp.count + MP4.moov.count + sidx.count)
        #expect(index.timescale == 48000)
        let expected: [SegmentIndex.Segment] = [
            .init(offset: sidxEnd + 100, size: 5000, duration: 2),
            .init(offset: sidxEnd + 5100, size: 6000, duration: 1),
        ]
        #expect(index.segments == expected)
    }

    @Test func skipsOtherBoxesIncludingLargeSizedOnes() throws {
        let free = MP4.largeBox("free", [UInt8](repeating: 0, count: 20))
        let file = MP4.ftyp + MP4.moov + free + MP4.sidx(references: references)
        guard case .index(let index) = try parse(file) else { Issue.record("expected an index"); return }
        #expect(index.initRange == 0..<Int64(MP4.ftyp.count + MP4.moov.count))   // init ends at moov, not at sidx
        #expect(index.segments.first?.offset == Int64(file.count))
    }

    @Test func asksForMoreBytesWhenTheBoxesRunPastTheBuffer() throws {
        let sidx = MP4.sidx(references: references)
        let file = MP4.ftyp + MP4.moov + sidx
        let moovStart = MP4.ftyp.count
        let sidxStart = moovStart + MP4.moov.count

        #expect(try parse([]) == .needsBytes(8))
        #expect(try parse(Array(file.prefix(5))) == .needsBytes(8))
        // Only moov's header is needed to skip it; the next header sits right after it.
        #expect(try parse(Array(file.prefix(moovStart + 8))) == .needsBytes(Int64(sidxStart + 8)))
        // The sidx itself must be complete.
        #expect(try parse(Array(file.prefix(sidxStart + 8))) == .needsBytes(Int64(file.count)))
        #expect(try parse(Array(file.dropLast())) == .needsBytes(Int64(file.count)))

        let large = MP4.ftyp + MP4.largeBox("free") + MP4.moov
        #expect(try parse(Array(large.prefix(MP4.ftyp.count + 8))) == .needsBytes(Int64(MP4.ftyp.count + 16)))
    }

    @Test func growingTheBufferAsAskedEndsInTheIndex() throws {
        let file = MP4.ftyp + MP4.moov + MP4.largeBox("free", [1, 2, 3]) + MP4.sidx(version: 1, references: references) + MP4.box("moof")
        var length = 0
        var rounds = 0
        while case .needsBytes(let needed) = try parse(Array(file.prefix(length))) {
            #expect(Int(needed) > length)
            length = Int(needed)
            rounds += 1
        }
        guard case .index(let index) = try parse(Array(file.prefix(length))) else { Issue.record("expected an index"); return }
        #expect(index.segments.count == references.count)
        #expect(rounds == 6)   // four box headers, free's largesize, then the rest of sidx
    }

    @Test func rejectsFilesWithoutAUsableIndex() throws {
        // Media before any index: an ordinary fragmented or progressive MP4.
        #expect(throws: SegmentIndex.ParseError.noIndex) { try parse(MP4.ftyp + MP4.moov + MP4.box("moof") + MP4.sidx(references: references)) }
        #expect(throws: SegmentIndex.ParseError.noIndex) { try parse(MP4.ftyp + MP4.box("mdat") + MP4.moov) }
        // A box that runs to the end of the file.
        #expect(throws: SegmentIndex.ParseError.noIndex) { try parse(MP4.ftyp + MP4.be(0, 4) + Array("moov".utf8)) }
        // An index with no init section before it.
        #expect(throws: SegmentIndex.ParseError.unsupported) { try parse(MP4.ftyp + MP4.sidx(references: references) + MP4.moov) }
        // Unknown version, and a hierarchical index pointing at further sidx boxes.
        #expect(throws: SegmentIndex.ParseError.unsupported) { try parse(MP4.ftyp + MP4.moov + MP4.sidx(version: 2, references: references)) }
        #expect(throws: SegmentIndex.ParseError.unsupported) { try parse(MP4.ftyp + MP4.moov + MP4.sidx(references: references, hierarchical: true)) }
    }

    @Test func rejectsMalformedBoxes() throws {
        // A size smaller than the header itself.
        #expect(throws: SegmentIndex.ParseError.malformed) { try parse(MP4.ftyp + MP4.be(4, 4) + Array("free".utf8)) }
        // A largesize that does not fit in Int64.
        #expect(throws: SegmentIndex.ParseError.malformed) { try parse(MP4.be(1, 4) + Array("free".utf8) + MP4.be(UInt64.max, 8)) }
        // A box that ends at the largest representable offset.
        #expect(throws: SegmentIndex.ParseError.malformed) { try parse(MP4.be(1, 4) + Array("free".utf8) + MP4.be(UInt64(Int64.max), 8)) }
        // Segments that run past the largest representable offset.
        let sidxEnd = UInt64(MP4.ftyp.count + MP4.moov.count + MP4.sidx(version: 1, references: references).count)
        let far = MP4.sidx(version: 1, firstOffset: UInt64(Int64.max) - sidxEnd, references: references)
        #expect(throws: SegmentIndex.ParseError.malformed) { try parse(MP4.ftyp + MP4.moov + far) }
        // No timescale, no references, or more references than the box holds.
        #expect(throws: SegmentIndex.ParseError.malformed) { try parse(MP4.ftyp + MP4.moov + MP4.sidx(timescale: 0, references: references)) }
        #expect(throws: SegmentIndex.ParseError.malformed) { try parse(MP4.ftyp + MP4.moov + MP4.sidx(references: [])) }
        var short = MP4.sidx(references: references)
        short.replaceSubrange(30..<32, with: MP4.be(4, 2))   // reference_count 4, room for 3
        #expect(throws: SegmentIndex.ParseError.malformed) { try parse(MP4.ftyp + MP4.moov + short) }
    }
}

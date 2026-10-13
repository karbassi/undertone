import Foundation

/// The layout of a fragmented MP4 (YouTube's DASH audio: `ftyp`, `moov`, `sidx`, then `moof`/`mdat` pairs), read
/// from the file's leading bytes: the init section a decoder needs first, and the media segments `sidx` lists.
public struct SegmentIndex: Equatable, Sendable {
    public struct Segment: Equatable, Sendable {
        public var offset: Int64
        public var size: Int64
        /// Seconds.
        public var duration: Double

        public init(offset: Int64, size: Int64, duration: Double) {
            self.offset = offset
            self.size = size
            self.duration = duration
        }

        /// One past the segment's last byte.
        public var end: Int64 { offset + size }
    }

    /// Bytes 0 through the end of `moov`.
    public var initRange: Range<Int64>
    /// Ticks per second in `sidx`; the segment durations are already converted from it.
    public var timescale: UInt32
    public var segments: [Segment]

    public init(initRange: Range<Int64>, timescale: UInt32, segments: [Segment]) {
        self.initRange = initRange
        self.timescale = timescale
        self.segments = segments
    }

    public enum ParseResult: Equatable, Sendable {
        case index(SegmentIndex)
        /// The boxes run past the bytes given: parse again with at least this many leading bytes.
        case needsBytes(Int64)
    }

    public enum ParseError: Error, Equatable, Sendable {
        /// A box that cannot be right: smaller than its own header, a `sidx` shorter than its entries, or offsets
        /// past the largest `Int64`.
        case malformed
        /// Media (`moof`/`mdat`) or a box running to the end of the file came before any `sidx`.
        case noIndex
        /// A layout this parser does not handle: `sidx` before `moov`, an unknown `sidx` version, or a `sidx`
        /// that points at further `sidx` boxes.
        case unsupported
    }

    /// Walks the top-level boxes of `data`, the first bytes of the file, up to and including `sidx`.
    public static func parse(_ data: Data) throws -> ParseResult {
        let bytes = ByteReader(data)
        var offset: Int64 = 0
        var moovEnd: Int64?
        while true {
            guard offset <= Int64.max - 8 else { throw ParseError.malformed }
            guard bytes.count >= offset + 8 else { return .needsBytes(offset + 8) }
            var size = Int64(bytes.uint(at: offset, width: 4))
            let type = bytes.fourCC(at: offset + 4)
            var headerSize: Int64 = 8
            if size == 1 {
                guard bytes.count >= offset + 16 else { return .needsBytes(offset + 16) }
                guard let large = Int64(exactly: bytes.uint(at: offset + 8, width: 8)) else { throw ParseError.malformed }
                size = large
                headerSize = 16
            } else if size == 0 {
                throw ParseError.noIndex   // the box runs to the end of the file, so no `sidx` follows it
            }
            guard size >= headerSize, offset <= Int64.max - size else { throw ParseError.malformed }
            let end = offset + size
            switch type {
            case "moov":
                moovEnd = end
            case "sidx":
                guard let moovEnd else { throw ParseError.unsupported }
                guard bytes.count >= end else { return .needsBytes(end) }
                return .index(try parseSIDX(bytes, from: offset + headerSize, to: end, initEnd: moovEnd))
            case "moof", "mdat":
                throw ParseError.noIndex
            default:
                break
            }
            offset = end
        }
    }

    /// Reads the `sidx` payload in `start..<end`. Segment offsets count from the end of the box plus `first_offset`.
    private static func parseSIDX(_ bytes: ByteReader, from start: Int64, to end: Int64, initEnd: Int64) throws -> SegmentIndex {
        var p = start
        func require(_ length: Int64) throws {
            guard p + length <= end else { throw ParseError.malformed }
        }
        try require(12)   // version, flags, reference_ID, timescale
        let version = bytes.uint(at: p, width: 1)
        let timescale = UInt32(bytes.uint(at: p + 8, width: 4))
        p += 12
        let firstOffset: UInt64
        switch version {
        case 0:
            try require(8)
            firstOffset = bytes.uint(at: p + 4, width: 4)   // after earliest_presentation_time
            p += 8
        case 1:
            try require(16)
            firstOffset = bytes.uint(at: p + 8, width: 8)
            p += 16
        default:
            throw ParseError.unsupported
        }
        try require(4)
        let count = Int64(bytes.uint(at: p + 2, width: 2))   // after 2 reserved bytes
        p += 4
        guard timescale > 0, count > 0 else { throw ParseError.malformed }
        try require(count * 12)
        guard let first = Int64(exactly: firstOffset), end <= Int64.max - first else { throw ParseError.malformed }

        var offset = end + first
        var segments: [Segment] = []
        segments.reserveCapacity(Int(count))
        for _ in 0..<count {
            let reference = bytes.uint(at: p, width: 4)
            guard reference & 0x8000_0000 == 0 else { throw ParseError.unsupported }   // points at another `sidx`
            let size = Int64(reference & 0x7FFF_FFFF)
            guard offset <= Int64.max - size else { throw ParseError.malformed }
            let ticks = bytes.uint(at: p + 4, width: 4)
            segments.append(Segment(offset: offset, size: size, duration: Double(ticks) / Double(timescale)))
            offset += size
            p += 12   // the third word is SAP info, unused
        }
        return SegmentIndex(initRange: 0..<initEnd, timescale: timescale, segments: segments)
    }
}

/// Big-endian reads at absolute offsets. Callers check `count` before reading.
private struct ByteReader {
    let bytes: [UInt8]

    init(_ data: Data) {
        bytes = [UInt8](data)
    }

    var count: Int64 { Int64(bytes.count) }

    func uint(at offset: Int64, width: Int) -> UInt64 {
        var value: UInt64 = 0
        for i in 0..<width { value = value << 8 | UInt64(bytes[Int(offset) + i]) }
        return value
    }

    func fourCC(at offset: Int64) -> String {
        String(decoding: bytes[Int(offset)..<Int(offset) + 4], as: UTF8.self)
    }
}

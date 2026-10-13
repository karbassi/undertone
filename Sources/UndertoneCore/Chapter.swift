import Foundation

/// A titled part of a video, such as one track of a DJ mix (YouTube's chapters).
public struct Chapter: Equatable, Hashable, Sendable, Codable {
    /// Seconds from the start of the video.
    public var start: Double
    public var end: Double?
    public var title: String

    public init(start: Double, end: Double? = nil, title: String) {
        self.start = start
        self.end = end
        self.title = title
    }
}

extension Track {
    /// A chapter starting this close ahead counts as reached: a boundary observer can fire a hair early.
    public static let chapterTolerance: Double = 0.5

    /// The chapter playing at `seconds`; nil without chapters or before the first one starts.
    public func chapter(at seconds: Double) -> Chapter? {
        chapterIndex(at: seconds).map { chapters[$0] }
    }

    /// Where Next goes: the start of the chapter after the one playing at `seconds`.
    public func nextChapterStart(after seconds: Double) -> Double? {
        guard !chapters.isEmpty else { return nil }
        let next = chapterIndex(at: seconds).map { $0 + 1 } ?? 0
        return chapters.indices.contains(next) ? chapters[next].start : nil
    }

    /// Where Previous goes: the start of the current chapter once more than `restartAfter` seconds in, else the one
    /// before it (the very start from the first chapter). Nil without chapters.
    public func previousChapterStart(from seconds: Double, restartAfter: Double = 3) -> Double? {
        guard !chapters.isEmpty else { return nil }
        guard let index = chapterIndex(at: seconds) else { return 0 }
        if seconds - chapters[index].start > restartAfter { return chapters[index].start }
        return index > 0 ? chapters[index - 1].start : 0
    }

    func chapterIndex(at seconds: Double) -> Int? {
        chapters.lastIndex { $0.start <= seconds + Self.chapterTolerance }
    }
}

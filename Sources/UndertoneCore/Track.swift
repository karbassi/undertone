import Foundation

/// A resolved, playable stream plus the metadata the UI shows.
public struct Track: Equatable, Sendable, Identifiable, Codable {
    public var id: String
    public var title: String
    public var channel: String?
    /// Seconds, from yt-dlp metadata. Trust this over AVFoundation: YouTube's m4a headers report double the length.
    public var duration: Double?
    public var webpageURL: URL?
    public var thumbnailURL: URL?
    public var streamURL: URL
    public var streamExtension: String?
    public var audioCodec: String?
    public var httpHeaders: [String: String]
    /// From the `expire=` query parameter of the stream URL (YouTube URLs live ~6 h).
    public var expiresAt: Date?
    public var extractor: String?
    /// In start order; empty for most videos.
    public var chapters: [Chapter]

    public init(
        id: String, title: String, channel: String? = nil, duration: Double? = nil,
        webpageURL: URL? = nil, thumbnailURL: URL? = nil, streamURL: URL,
        streamExtension: String? = nil, audioCodec: String? = nil,
        httpHeaders: [String: String] = [:], expiresAt: Date? = nil, extractor: String? = nil,
        chapters: [Chapter] = []
    ) {
        self.id = id
        self.title = title
        self.channel = channel
        self.duration = duration
        self.webpageURL = webpageURL
        self.thumbnailURL = thumbnailURL
        self.streamURL = streamURL
        self.streamExtension = streamExtension
        self.audioCodec = audioCodec
        self.httpHeaders = httpHeaders
        self.expiresAt = expiresAt
        self.extractor = extractor
        self.chapters = chapters
    }

    // Written out so a stream cached before chapters were decoded (no `chapters` key) still loads.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        channel = try c.decodeIfPresent(String.self, forKey: .channel)
        duration = try c.decodeIfPresent(Double.self, forKey: .duration)
        webpageURL = try c.decodeIfPresent(URL.self, forKey: .webpageURL)
        thumbnailURL = try c.decodeIfPresent(URL.self, forKey: .thumbnailURL)
        streamURL = try c.decode(URL.self, forKey: .streamURL)
        streamExtension = try c.decodeIfPresent(String.self, forKey: .streamExtension)
        audioCodec = try c.decodeIfPresent(String.self, forKey: .audioCodec)
        httpHeaders = try c.decode([String: String].self, forKey: .httpHeaders)
        expiresAt = try c.decodeIfPresent(Date.self, forKey: .expiresAt)
        extractor = try c.decodeIfPresent(String.self, forKey: .extractor)
        chapters = try c.decodeIfPresent([Chapter].self, forKey: .chapters) ?? []
    }

    public var userAgent: String? { httpHeaders["User-Agent"] }

    public var isYouTube: Bool { extractor?.lowercased().hasPrefix("youtube") ?? false }

    /// Stable JPEG artwork for YouTube (webp maxres thumbnails are flaky); the site thumbnail otherwise.
    public var artworkURL: URL? {
        isYouTube ? URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg") : thumbnailURL
    }

    public func isExpired(at now: Date = Date(), margin: TimeInterval = 120) -> Bool {
        guard let expiresAt else { return false }
        return now.addingTimeInterval(margin) >= expiresAt
    }

    /// Decodes `yt-dlp -j` output for a single video.
    public static func decode(fromYTDLPJSON data: Data) throws -> Track {
        let info: YTDLPInfo
        do {
            info = try JSONDecoder().decode(YTDLPInfo.self, from: data)
        } catch {
            throw YTDLPFailure.invalidOutput
        }
        guard let urlString = info.url, let streamURL = URL(string: urlString) else {
            throw YTDLPFailure.invalidOutput
        }
        return Track(
            id: info.id,
            title: info.title ?? info.id,
            channel: info.channel ?? info.uploader,
            duration: info.duration,
            webpageURL: info.webpageURL.flatMap(URL.init(string:)),
            thumbnailURL: info.thumbnail.flatMap(URL.init(string:)),
            streamURL: streamURL,
            streamExtension: info.ext,
            audioCodec: info.acodec,
            httpHeaders: (info.httpHeaders ?? [:]).filter { $0.key == "User-Agent" },   // the only one used
            expiresAt: expiry(from: streamURL),
            extractor: info.extractor,
            chapters: chapters(from: info.chapters ?? [])
        )
    }

    /// yt-dlp's chapters in start order. One without a start is dropped; an untitled one gets its number.
    private static func chapters(from raw: [YTDLPChapter]) -> [Chapter] {
        let timed = raw.compactMap { c in c.startTime.map { (start: $0, end: c.endTime, title: c.title) } }
        return timed.sorted { $0.start < $1.start }.enumerated().map { i, c in
            let title = c.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return Chapter(start: c.start, end: c.end, title: title.isEmpty ? "Chapter \(i + 1)" : title)
        }
    }

    static func expiry(from url: URL) -> Date? {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let raw = items.first(where: { $0.name == "expire" })?.value,
              let seconds = TimeInterval(raw)
        else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}

private struct YTDLPInfo: Decodable {
    let id: String
    let title: String?
    let channel: String?
    let uploader: String?
    let duration: Double?
    let webpageURL: String?
    let thumbnail: String?
    let url: String?
    let ext: String?
    let acodec: String?
    let httpHeaders: [String: String]?
    let extractor: String?
    let chapters: [YTDLPChapter]?

    enum CodingKeys: String, CodingKey {
        case id, title, channel, uploader, duration, thumbnail, url, ext, acodec, extractor, chapters
        case webpageURL = "webpage_url"
        case httpHeaders = "http_headers"
    }
}

private struct YTDLPChapter: Decodable {
    let startTime: Double?
    let endTime: Double?
    let title: String?

    enum CodingKeys: String, CodingKey {
        case title
        case startTime = "start_time"
        case endTime = "end_time"
    }
}

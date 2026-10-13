import Foundation

/// HLS media playlists over a fragmented MP4, so AVPlayer streams it segment by segment.
public enum HLSPlaylist {
    /// A VOD playlist whose init section and segments are the byte ranges of `url` that `index` lists. AVPlayer
    /// fetches each segment as a bounded range only as playback nears it, and takes the duration from the list.
    public static func media(_ index: SegmentIndex, url: URL) -> String {
        let uri = url.absoluteString
        let longest = index.segments.map(\.duration).max() ?? 0
        var lines = [
            "#EXTM3U",
            "#EXT-X-VERSION:7",
            "#EXT-X-PLAYLIST-TYPE:VOD",
            "#EXT-X-TARGETDURATION:\(max(1, Int(longest.rounded(.up))))",
            "#EXT-X-MAP:URI=\"\(uri)\",BYTERANGE=\"\(index.initRange.count)@\(index.initRange.lowerBound)\"",
        ]
        lines.reserveCapacity(lines.count + 3 * index.segments.count + 1)
        for segment in index.segments {
            // Six decimals: rounding error summed over ~700 segments stays far below a sample's worth of drift.
            lines.append(String(format: "#EXTINF:%.6f,", segment.duration))
            lines.append("#EXT-X-BYTERANGE:\(segment.size)@\(segment.offset)")
            lines.append(uri)
        }
        lines.append("#EXT-X-ENDLIST")
        return lines.joined(separator: "\n") + "\n"
    }
}

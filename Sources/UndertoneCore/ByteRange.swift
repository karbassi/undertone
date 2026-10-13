import Foundation

public enum ByteRange {
    /// The resource's total size from a `Content-Range: bytes 0-1/115150454` header, or nil if absent or `*`.
    public static func total(fromContentRange header: String?) -> Int64? {
        guard let header, let slash = header.lastIndex(of: "/") else { return nil }
        return Int64(header[header.index(after: slash)...].trimmingCharacters(in: .whitespaces))
    }
}

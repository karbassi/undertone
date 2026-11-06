import Foundation

/// The stream URL itself was turned away (YouTube sometimes 403s a freshly signed URL), so retrying the same URL
/// cannot help: the link has to be resolved again for a new one.
public struct StreamRefused: Error, Equatable, Sendable, LocalizedError {
    public let statusCode: Int

    public init(statusCode: Int) { self.statusCode = statusCode }

    /// Statuses that mean "this URL is dead", as opposed to a hiccup worth retrying or a server quirk.
    public static func isRefusal(_ statusCode: Int) -> Bool {
        [401, 403, 404, 410].contains(statusCode)
    }

    public var errorDescription: String? { "Stream returned HTTP \(statusCode)" }
}

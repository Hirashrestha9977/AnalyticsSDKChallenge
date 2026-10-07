import Foundation

public struct AnalyticsConfiguration: Sendable {
    /// Events are held in memory and written to disk in batches of this size.
    /// Larger batches mean fewer disk writes; smaller batches mean less data at risk
    /// if the process is killed.
    public var flushBatchSize: Int

    /// Oldest sessions are deleted once this many are stored, so disk usage stays bounded.
    public var maxStoredSessions: Int

    /// Prints dropped events and persistence failures to the console.
    public var isDebugLoggingEnabled: Bool

    public init(
        flushBatchSize: Int = 20,
        maxStoredSessions: Int = 50,
        isDebugLoggingEnabled: Bool = false
    ) {
        self.flushBatchSize = max(1, flushBatchSize)
        self.maxStoredSessions = max(1, maxStoredSessions)
        self.isDebugLoggingEnabled = isDebugLoggingEnabled
    }
}

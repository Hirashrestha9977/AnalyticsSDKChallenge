import Foundation

/// A recording session: the window of time between `startSession()` and `endSession()`.
public struct Session: Codable, Equatable, Identifiable, Sendable {
    public enum Status: String, Codable, Sendable {
        /// Recording is in progress.
        case active
        /// Closed by a call to `endSession()`.
        case ended
        /// The app went away (crash, kill) before `endSession()` was called.
        case interrupted
    }

    public let id: UUID
    public let startedAt: Date
    /// For an interrupted session this is the time of its last recorded event.
    public var endedAt: Date?
    public var status: Status
    public let properties: [String: PropertyValue]
    public var eventCount: Int

    public var duration: TimeInterval? {
        endedAt.map { $0.timeIntervalSince(startedAt) }
    }

    public init(
        id: UUID,
        startedAt: Date,
        endedAt: Date? = nil,
        status: Status = .active,
        properties: [String: PropertyValue] = [:],
        eventCount: Int = 0
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.properties = properties
        self.eventCount = eventCount
    }
}

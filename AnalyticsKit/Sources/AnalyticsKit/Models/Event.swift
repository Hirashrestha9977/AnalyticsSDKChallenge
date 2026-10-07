import Foundation

/// Something that happened during a session.
public struct Event: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let name: String
    public let timestamp: Date
    public let properties: [String: PropertyValue]

    public init(
        id: UUID,
        sessionID: UUID,
        name: String,
        timestamp: Date,
        properties: [String: PropertyValue] = [:]
    ) {
        self.id = id
        self.sessionID = sessionID
        self.name = name
        self.timestamp = timestamp
        self.properties = properties
    }
}

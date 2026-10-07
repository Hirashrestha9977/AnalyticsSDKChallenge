import Foundation

/// Keeps everything in memory. Useful for unit tests and SwiftUI previews,
/// where touching the disk is unwanted.
public final class InMemorySessionStore: SessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var sessions: [UUID: Session] = [:]
    private var events: [UUID: [Event]] = [:]

    public init() {}

    public func saveSession(_ session: Session) throws {
        lock.lock(); defer { lock.unlock() }
        sessions[session.id] = session
    }

    public func appendEvents(_ events: [Event], to sessionID: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        self.events[sessionID, default: []].append(contentsOf: events)
    }

    public func loadSessions() throws -> [Session] {
        lock.lock(); defer { lock.unlock() }
        return Array(sessions.values)
    }

    public func loadEvents(for sessionID: UUID) throws -> [Event] {
        lock.lock(); defer { lock.unlock() }
        return events[sessionID] ?? []
    }

    public func deleteSession(_ sessionID: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        sessions[sessionID] = nil
        events[sessionID] = nil
    }
}

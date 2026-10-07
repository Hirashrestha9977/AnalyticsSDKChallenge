import Foundation

/// Where session data is persisted.
///
/// `Analytics` only talks to this protocol, so the storage engine can be swapped
/// (files, SQLite, Core Data, an in-memory fake for tests) without touching the SDK's logic.
///
/// `Analytics` calls a store from a single serial queue, so implementations do not
/// need their own locking unless they are also used elsewhere.
public protocol SessionStore: AnyObject {
    /// Inserts the session, or replaces the stored one with the same id.
    func saveSession(_ session: Session) throws

    /// Adds events to the end of a session's event log.
    func appendEvents(_ events: [Event], to sessionID: UUID) throws

    func loadSessions() throws -> [Session]

    /// Events in the order they were appended.
    func loadEvents(for sessionID: UUID) throws -> [Event]

    /// Removes the session and its events. Deleting an unknown id is not an error.
    func deleteSession(_ sessionID: UUID) throws
}

import Foundation

/// Persists sessions as files, two per session:
///
/// - `<id>.session.json`  the session's metadata, rewritten atomically when it changes
/// - `<id>.events.jsonl`  one JSON event per line, append-only
///
/// Appending a line costs the same whether the session holds ten events or a million,
/// which is why events are not kept inside the session's JSON document.
public final class FileSessionStore: SessionStore {
    private let directory: URL
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private static let sessionSuffix = ".session.json"
    private static let newline = Data([0x0A])

    /// `Application Support/AnalyticsKit/Sessions`
    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("AnalyticsKit/Sessions", isDirectory: true)
    }

    public init(directory: URL = FileSessionStore.defaultDirectory) {
        self.directory = directory
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
    }

    public func saveSession(_ session: Session) throws {
        try createDirectoryIfNeeded()
        try encoder.encode(session).write(to: sessionURL(session.id), options: .atomic)
    }

    public func appendEvents(_ events: [Event], to sessionID: UUID) throws {
        guard !events.isEmpty else { return }
        try createDirectoryIfNeeded()

        var lines = Data()
        for event in events {
            lines.append(try encoder.encode(event))
            lines.append(Self.newline)
        }

        let url = eventsURL(sessionID)
        guard fileManager.fileExists(atPath: url.path) else {
            try lines.write(to: url, options: .atomic)
            return
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: lines)
    }

    public func loadSessions() throws -> [Session] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        return try fileManager
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(Self.sessionSuffix) }
            // An unreadable file is skipped so one bad session cannot hide the rest.
            .compactMap { try? decoder.decode(Session.self, from: Data(contentsOf: $0)) }
    }

    public func loadEvents(for sessionID: UUID) throws -> [Event] {
        let url = eventsURL(sessionID)
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        return try Data(contentsOf: url)
            .split(separator: 0x0A)
            // A line cut short by a crash mid-write is skipped; the lines before it survive.
            .compactMap { try? decoder.decode(Event.self, from: $0) }
    }

    public func deleteSession(_ sessionID: UUID) throws {
        for url in [sessionURL(sessionID), eventsURL(sessionID)] where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func createDirectoryIfNeeded() throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func sessionURL(_ id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString + Self.sessionSuffix)
    }

    private func eventsURL(_ id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString + ".events.jsonl")
    }
}

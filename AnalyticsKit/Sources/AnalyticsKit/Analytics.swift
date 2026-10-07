import Foundation
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

/// Entry point of the SDK.
///
///     Analytics.shared.startSession()
///     Analytics.shared.track("button_tapped", properties: ["screen": "home"])
///     Analytics.shared.endSession()
///
/// Recording calls (`startSession`, `track`, `endSession`) can be made from any thread,
/// return immediately, and never throw: an analytics SDK must not be able to crash or
/// block the app that hosts it. Disk work happens on a background queue.
///
/// `shared` covers the common case. Create your own instance when you need a custom
/// configuration or store.
public final class Analytics: @unchecked Sendable {
    public static let shared = Analytics()

    private let configuration: AnalyticsConfiguration
    private let store: SessionStore
    private let now: () -> Date
    private let makeID: () -> UUID

    /// Guards `activeSession` and `buffer`.
    private let lock = NSLock()
    private var activeSession: Session?
    private var buffer: [Event] = []

    /// All store access goes through this serial queue. Work is enqueued while `lock`
    /// is held, so writes reach the store in the order the calls were made.
    private let ioQueue = DispatchQueue(label: "com.analyticskit.io", qos: .utility)
    private var lifecycleObservers: [NSObjectProtocol] = []

    public convenience init(
        configuration: AnalyticsConfiguration = AnalyticsConfiguration(),
        store: SessionStore = FileSessionStore()
    ) {
        self.init(configuration: configuration, store: store, now: Date.init, makeID: UUID.init)
    }

    /// Lets tests control time and identifiers.
    init(
        configuration: AnalyticsConfiguration,
        store: SessionStore,
        now: @escaping () -> Date,
        makeID: @escaping () -> UUID
    ) {
        self.configuration = configuration
        self.store = store
        self.now = now
        self.makeID = makeID
        recoverInterruptedSessions()
        observeAppLifecycle()
    }

    deinit {
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Recording

    /// The session currently being recorded, if any.
    public var currentSession: Session? {
        locked { activeSession }
    }

    /// Starts recording a session.
    ///
    /// If a session is already active it is returned unchanged, so calling this twice
    /// is harmless. Call `endSession()` first to start a fresh one.
    @discardableResult
    public func startSession(properties: [String: PropertyValue] = [:]) -> Session {
        locked {
            if let activeSession {
                log("startSession ignored: session \(activeSession.id) is already active")
                return activeSession
            }
            let session = Session(id: makeID(), startedAt: now(), properties: properties)
            activeSession = session
            enqueue { [store, limit = configuration.maxStoredSessions] in
                try store.saveSession(session)
                try Self.pruneOldSessions(in: store, keeping: session.id, limit: limit)
            }
            return session
        }
    }

    /// Records an event in the active session.
    ///
    /// The event is dropped if no session is active or `name` is blank.
    public func track(_ name: String, properties: [String: PropertyValue] = [:]) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            log("Event dropped: name is empty")
            return
        }
        locked {
            guard let session = activeSession else {
                log("Event '\(name)' dropped: no active session")
                return
            }
            buffer.append(
                Event(id: makeID(), sessionID: session.id, name: name, timestamp: now(), properties: properties)
            )
            activeSession?.eventCount += 1
            if buffer.count >= configuration.flushBatchSize {
                flushBuffer()
            }
        }
    }

    /// Ends the active session and persists everything recorded in it.
    /// Does nothing if no session is active.
    public func endSession() {
        locked {
            guard var session = activeSession else {
                log("endSession ignored: no active session")
                return
            }
            flushBuffer()
            session.endedAt = now()
            session.status = .ended
            activeSession = nil
            enqueue { [store] in try store.saveSession(session) }
        }
    }

    /// Writes buffered events to the store and returns once they are persisted.
    public func flush() async {
        locked { flushBuffer() }
        await waitForPendingWrites()
    }

    // MARK: - Reading

    /// All stored sessions, oldest first, including the active one.
    public func sessions() async throws -> [Session] {
        try await read { store in
            let stored = try store.loadSessions()
            // The stored copy of the active session lags behind (its event count is
            // only written when it ends), so the live one takes its place.
            let active = self.currentSession
            return stored
                .map { $0.id == active?.id ? active ?? $0 : $0 }
                .sorted { $0.startedAt < $1.startedAt }
        }
    }

    /// Events of a session in the order they were tracked, including ones not yet flushed.
    public func events(in sessionID: UUID) async throws -> [Event] {
        locked { flushBuffer() }
        return try await read { try $0.loadEvents(for: sessionID) }
    }

    // MARK: - Internals

    /// Returns once every write enqueued so far has reached the store.
    func waitForPendingWrites() async {
        await withCheckedContinuation { continuation in
            ioQueue.async { continuation.resume() }
        }
    }

    /// Must be called with `lock` held.
    private func flushBuffer() {
        guard !buffer.isEmpty, let sessionID = activeSession?.id else { return }
        let batch = buffer
        buffer.removeAll(keepingCapacity: true)
        enqueue { [store] in try store.appendEvents(batch, to: sessionID) }
    }

    private func enqueue(_ work: @escaping () throws -> Void) {
        ioQueue.async { [weak self] in
            do {
                try work()
            } catch {
                self?.log("Persistence failed: \(error)")
            }
        }
    }

    private func read<T>(_ work: @escaping (SessionStore) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            ioQueue.async { [store] in
                continuation.resume(with: Result { try work(store) })
            }
        }
    }

    /// A session still marked active when the SDK starts up belongs to a previous
    /// launch that never called `endSession()`. Close it so it is not left dangling.
    private func recoverInterruptedSessions() {
        enqueue { [store] in
            for var session in try store.loadSessions() where session.status == .active {
                let events = (try? store.loadEvents(for: session.id)) ?? []
                session.status = .interrupted
                session.endedAt = events.last?.timestamp ?? session.startedAt
                session.eventCount = events.count
                try store.saveSession(session)
            }
        }
    }

    private static func pruneOldSessions(in store: SessionStore, keeping currentID: UUID, limit: Int) throws {
        let sessions = try store.loadSessions()
        let excess = sessions.count - limit
        guard excess > 0 else { return }
        let oldest = sessions
            .filter { $0.id != currentID }
            .sorted { $0.startedAt < $1.startedAt }
            .prefix(excess)
        for session in oldest {
            try store.deleteSession(session.id)
        }
    }

    private func observeAppLifecycle() {
        #if canImport(UIKit) && !os(watchOS)
        // The app may be killed while suspended without further notice, so buffered
        // events are written out before it leaves the foreground.
        let names = [UIApplication.didEnterBackgroundNotification, UIApplication.willTerminateNotification]
        lifecycleObservers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                guard let self else { return }
                self.locked { self.flushBuffer() }
                self.ioQueue.sync {}
            }
        }
        #endif
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private func log(_ message: @autoclosure () -> String) {
        guard configuration.isDebugLoggingEnabled else { return }
        print("[AnalyticsKit] \(message())")
    }
}

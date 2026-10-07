import XCTest
@testable import AnalyticsKit

final class AnalyticsTests: XCTestCase {
    private var store: InMemorySessionStore!
    private var clock: TestClock!

    override func setUp() {
        super.setUp()
        store = InMemorySessionStore()
        clock = TestClock()
    }

    private func makeSUT(flushBatchSize: Int = 20, maxStoredSessions: Int = 50) -> Analytics {
        Analytics(
            configuration: AnalyticsConfiguration(
                flushBatchSize: flushBatchSize,
                maxStoredSessions: maxStoredSessions
            ),
            store: store,
            now: clock.now,
            makeID: UUID.init
        )
    }

    // MARK: - Starting

    func test_startSession_persistsAnActiveSession() async throws {
        let sut = makeSUT()

        let session = sut.startSession(properties: ["plan": "pro"])
        await sut.flush()

        XCTAssertEqual(sut.currentSession, session)
        XCTAssertEqual(session.status, .active)
        XCTAssertEqual(session.startedAt, clock.start)
        XCTAssertEqual(session.properties, ["plan": .string("pro")])
        XCTAssertEqual(try store.loadSessions(), [session])
    }

    func test_startSession_whileActive_returnsTheSameSession() async throws {
        let sut = makeSUT()

        let first = sut.startSession()
        let second = sut.startSession()
        await sut.flush()

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(try store.loadSessions().count, 1)
    }

    func test_startSession_afterEnding_createsANewSession() async throws {
        let sut = makeSUT()

        let first = sut.startSession()
        sut.endSession()
        let second = sut.startSession()
        await sut.flush()

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(try store.loadSessions().count, 2)
    }

    // MARK: - Tracking

    func test_track_persistsEventWithProperties() async throws {
        let sut = makeSUT()
        let session = sut.startSession()

        clock.advance(by: 5)
        sut.track("purchase", properties: ["item": "shoes", "price": 59.99, "quantity": 2, "gift": false])
        await sut.flush()

        let events = try store.loadEvents(for: session.id)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.name, "purchase")
        XCTAssertEqual(events.first?.sessionID, session.id)
        XCTAssertEqual(events.first?.timestamp, clock.start.addingTimeInterval(5))
        XCTAssertEqual(events.first?.properties, [
            "item": .string("shoes"),
            "price": .double(59.99),
            "quantity": .int(2),
            "gift": .bool(false)
        ])
    }

    func test_track_withoutActiveSession_dropsTheEvent() async throws {
        let sut = makeSUT()

        sut.track("orphan")
        let session = sut.startSession()
        await sut.flush()

        XCTAssertEqual(try store.loadEvents(for: session.id), [])
    }

    func test_track_withBlankName_dropsTheEvent() async throws {
        let sut = makeSUT()
        let session = sut.startSession()

        sut.track("   ")
        await sut.flush()

        XCTAssertEqual(try store.loadEvents(for: session.id), [])
        XCTAssertEqual(sut.currentSession?.eventCount, 0)
    }

    func test_track_keepsEventsInOrder() async throws {
        let sut = makeSUT(flushBatchSize: 3)
        let session = sut.startSession()

        (1...10).forEach { sut.track("event_\($0)") }
        await sut.flush()

        XCTAssertEqual(
            try store.loadEvents(for: session.id).map(\.name),
            (1...10).map { "event_\($0)" }
        )
    }

    func test_track_writesToStoreOnlyWhenBatchIsFull() async throws {
        let sut = makeSUT(flushBatchSize: 3)
        let session = sut.startSession()

        sut.track("one")
        sut.track("two")
        await sut.waitForPendingWrites()
        XCTAssertEqual(try store.loadEvents(for: session.id).count, 0)

        sut.track("three")
        await sut.waitForPendingWrites()
        XCTAssertEqual(try store.loadEvents(for: session.id).count, 3)
    }

    func test_track_fromManyThreads_losesNothing() async throws {
        let sut = makeSUT(flushBatchSize: 7)
        let session = sut.startSession()

        DispatchQueue.concurrentPerform(iterations: 1_000) { index in
            sut.track("event", properties: ["index": .int(index)])
        }
        await sut.flush()

        let events = try store.loadEvents(for: session.id)
        XCTAssertEqual(events.count, 1_000)
        XCTAssertEqual(Set(events.map(\.id)).count, 1_000)
        XCTAssertEqual(sut.currentSession?.eventCount, 1_000)
    }

    // MARK: - Ending

    func test_endSession_closesTheSessionAndFlushesEvents() async throws {
        let sut = makeSUT()
        let session = sut.startSession()
        sut.track("one")
        sut.track("two")

        clock.advance(by: 60)
        sut.endSession()
        await sut.waitForPendingWrites()

        let stored = try XCTUnwrap(store.loadSessions().first)
        XCTAssertNil(sut.currentSession)
        XCTAssertEqual(stored.status, .ended)
        XCTAssertEqual(stored.duration, 60)
        XCTAssertEqual(stored.eventCount, 2)
        XCTAssertEqual(try store.loadEvents(for: session.id).count, 2)
    }

    func test_endSession_withoutActiveSession_doesNothing() async throws {
        let sut = makeSUT()

        sut.endSession()
        await sut.flush()

        XCTAssertEqual(try store.loadSessions(), [])
    }

    // MARK: - Reading

    func test_sessions_reportsLiveEventCountForActiveSession() async throws {
        let sut = makeSUT()
        sut.startSession()
        sut.track("one")

        let sessions = try await sut.sessions()

        XCTAssertEqual(sessions.map(\.eventCount), [1])
    }

    func test_events_includesEventsNotYetFlushed() async throws {
        let sut = makeSUT(flushBatchSize: 100)
        let session = sut.startSession()
        sut.track("buffered")

        let events = try await sut.events(in: session.id)

        XCTAssertEqual(events.map(\.name), ["buffered"])
    }

    // MARK: - Housekeeping

    func test_init_marksSessionLeftActiveByPreviousLaunchAsInterrupted() async throws {
        let id = UUID()
        let lastEventTime = clock.start.addingTimeInterval(30)
        try store.saveSession(Session(id: id, startedAt: clock.start))
        try store.appendEvents([
            Event(id: UUID(), sessionID: id, name: "one", timestamp: clock.start),
            Event(id: UUID(), sessionID: id, name: "two", timestamp: lastEventTime)
        ], to: id)

        let sut = makeSUT()
        await sut.waitForPendingWrites()

        let recovered = try XCTUnwrap(store.loadSessions().first)
        XCTAssertEqual(recovered.status, .interrupted)
        XCTAssertEqual(recovered.endedAt, lastEventTime)
        XCTAssertEqual(recovered.eventCount, 2)
        XCTAssertNil(sut.currentSession)
    }

    func test_startSession_deletesOldestSessionsBeyondTheLimit() async throws {
        let sut = makeSUT(maxStoredSessions: 2)
        var started: [Session] = []

        for _ in 0..<4 {
            clock.advance(by: 10)
            let session = sut.startSession()
            sut.track("event")
            sut.endSession()
            started.append(session)
        }
        await sut.flush()

        XCTAssertEqual(Set(try store.loadSessions().map(\.id)), Set(started.suffix(2).map(\.id)))
        XCTAssertEqual(try store.loadEvents(for: started[0].id), [])
    }
}

/// A clock that only moves when the test tells it to.
final class TestClock: @unchecked Sendable {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    private let lock = NSLock()
    private var offset: TimeInterval = 0

    func now() -> Date {
        lock.lock(); defer { lock.unlock() }
        return start.addingTimeInterval(offset)
    }

    func advance(by seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        offset += seconds
    }
}

import XCTest
@testable import AnalyticsKit

final class FileSessionStoreTests: XCTestCase {
    private var directory: URL!
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnalyticsKitTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func makeEvent(_ name: String, in sessionID: UUID) -> Event {
        Event(id: UUID(), sessionID: sessionID, name: name, timestamp: date, properties: ["screen": "home", "count": 3])
    }

    func test_loading_fromEmptyStore_returnsNothing() throws {
        let sut = FileSessionStore(directory: directory)

        XCTAssertEqual(try sut.loadSessions(), [])
        XCTAssertEqual(try sut.loadEvents(for: UUID()), [])
    }

    func test_saveSession_roundTrips() throws {
        let session = Session(id: UUID(), startedAt: date, properties: ["plan": "pro"])

        try FileSessionStore(directory: directory).saveSession(session)

        XCTAssertEqual(try FileSessionStore(directory: directory).loadSessions(), [session])
    }

    func test_saveSession_replacesExistingSession() throws {
        let sut = FileSessionStore(directory: directory)
        var session = Session(id: UUID(), startedAt: date)
        try sut.saveSession(session)

        session.status = .ended
        session.endedAt = date.addingTimeInterval(10)
        try sut.saveSession(session)

        XCTAssertEqual(try sut.loadSessions(), [session])
    }

    func test_appendEvents_accumulatesAcrossCallsInOrder() throws {
        let sut = FileSessionStore(directory: directory)
        let id = UUID()
        let first = [makeEvent("one", in: id), makeEvent("two", in: id)]
        let second = [makeEvent("three", in: id)]

        try sut.appendEvents(first, to: id)
        try sut.appendEvents(second, to: id)

        XCTAssertEqual(try sut.loadEvents(for: id), first + second)
    }

    func test_appendEvents_keepsSessionsSeparate() throws {
        let sut = FileSessionStore(directory: directory)
        let (a, b) = (UUID(), UUID())

        try sut.appendEvents([makeEvent("a", in: a)], to: a)
        try sut.appendEvents([makeEvent("b", in: b)], to: b)

        XCTAssertEqual(try sut.loadEvents(for: a).map(\.name), ["a"])
        XCTAssertEqual(try sut.loadEvents(for: b).map(\.name), ["b"])
    }

    func test_loadEvents_skipsLineTruncatedByACrash() throws {
        let sut = FileSessionStore(directory: directory)
        let id = UUID()
        try sut.appendEvents([makeEvent("intact", in: id)], to: id)

        let url = directory.appendingPathComponent("\(id.uuidString).events.jsonl")
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(#"{"id":"half-writ"#.utf8))
        try handle.close()

        XCTAssertEqual(try sut.loadEvents(for: id).map(\.name), ["intact"])
    }

    func test_deleteSession_removesSessionAndItsEvents() throws {
        let sut = FileSessionStore(directory: directory)
        let session = Session(id: UUID(), startedAt: date)
        try sut.saveSession(session)
        try sut.appendEvents([makeEvent("one", in: session.id)], to: session.id)

        try sut.deleteSession(session.id)
        try sut.deleteSession(UUID())

        XCTAssertEqual(try sut.loadSessions(), [])
        XCTAssertEqual(try sut.loadEvents(for: session.id), [])
    }

    func test_dataRecordedByOneAnalyticsInstance_isReadableByTheNext() async throws {
        let firstLaunch = Analytics(store: FileSessionStore(directory: directory))
        let session = firstLaunch.startSession(properties: ["plan": "pro"])
        firstLaunch.track("screen_viewed", properties: ["screen": "home"])
        firstLaunch.track("button_tapped")
        firstLaunch.endSession()
        await firstLaunch.flush()

        let secondLaunch = Analytics(store: FileSessionStore(directory: directory))
        let sessions = try await secondLaunch.sessions()
        let events = try await secondLaunch.events(in: session.id)

        XCTAssertEqual(sessions.map(\.id), [session.id])
        XCTAssertEqual(sessions.first?.status, .ended)
        XCTAssertEqual(sessions.first?.eventCount, 2)
        XCTAssertEqual(events.map(\.name), ["screen_viewed", "button_tapped"])
        XCTAssertEqual(events.first?.properties, ["screen": .string("home")])
    }
}

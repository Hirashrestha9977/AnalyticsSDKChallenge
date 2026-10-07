# AnalyticsKit

A small analytics SDK for iOS, written in Swift, with a SwiftUI demo app.

```
AnalyticsSDKChallenge/
├── AnalyticsKit/      the SDK (Swift Package, iOS 15+, no dependencies)
│   ├── Sources/AnalyticsKit/
│   │   ├── Analytics.swift               public entry point
│   │   ├── AnalyticsConfiguration.swift
│   │   ├── Models/                       Session, Event, PropertyValue
│   │   └── Storage/                      SessionStore protocol + file and in-memory stores
│   └── Tests/AnalyticsKitTests/          27 unit tests
└── AnalyticsDemo/     SwiftUI app that uses the SDK (iOS 16+)
```

## Using the SDK

```swift
import AnalyticsKit

Analytics.shared.startSession(properties: ["plan": "pro"])

Analytics.shared.track("screen_viewed", properties: ["screen": "home"])
Analytics.shared.track("purchase_completed", properties: ["price": 59.99, "quantity": 1, "gift": false])

Analytics.shared.endSession()
```

Reading back what was stored:

```swift
let sessions = try await Analytics.shared.sessions()
let events = try await Analytics.shared.events(in: sessions[0].id)
```

Custom setup:

```swift
let analytics = Analytics(
    configuration: AnalyticsConfiguration(flushBatchSize: 50, maxStoredSessions: 100, isDebugLoggingEnabled: true),
    store: FileSessionStore(directory: myDirectory)
)
```

## Running it

- **Demo app:** open `AnalyticsDemo/AnalyticsDemo.xcodeproj` and run the `AnalyticsDemo` scheme on a simulator.
- **Tests:** `cd AnalyticsKit && swift test`, or open the package in Xcode and press ⌘U.

Built and tested with Xcode 15.2 (Swift 5.9).

## Design decisions

### Usability of the API

- **Three verbs for the three use cases:** `startSession`, `track`, `endSession`. `Analytics.shared` works with zero setup.
- **Recording calls never throw and never block.** An analytics SDK must not crash or slow the host app. Misuse is handled quietly and predictably, and reported through debug logging:

  | Call | Situation | Result |
  |---|---|---|
  | `startSession()` | a session is already active | returns the active session |
  | `track()` | no active session, or blank name | event dropped |
  | `endSession()` | no active session | nothing happens |

- **Typed properties.** `PropertyValue` is an enum (`string`, `int`, `double`, `bool`) rather than `Any`, so anything the caller can pass is guaranteed to be serialisable. Literal conformances keep call sites as short as an `Any` dictionary would be.
- **Reads are `async throws`.** Unlike recording, a caller who asks for data wants to know if it could not be loaded.

### Persistence

`FileSessionStore` writes two files per session:

- `<id>.session.json` holds the metadata and is rewritten atomically on start and end.
- `<id>.events.jsonl` holds one JSON event per line and is only ever appended to.

Events are kept out of the session document on purpose: appending a line costs the same for the millionth event as for the first, whereas re-encoding one growing JSON document gets slower with every event.

A session is saved the moment it starts, so it survives a crash. On the next launch any session still marked `active` is closed as `interrupted`, with its end time set to its last recorded event. A line cut off mid-write is skipped when reading; everything before it is kept.

### Scalability

- **Batched writes.** Events are buffered in memory and written `flushBatchSize` at a time (default 20), and also on `endSession()`, on `flush()`, and when the app goes to the background.
- **Off the caller's thread.** `track` takes a lock, appends to an array, and returns. Disk I/O runs on a serial utility queue.
- **Bounded disk use.** Only the newest `maxStoredSessions` are kept.
- **Thread safe.** State is guarded by a lock; writes are enqueued while the lock is held, so they reach the disk in call order. A test tracks 1,000 events from concurrent threads and checks none are lost.

### Testability

- `Analytics` depends on the `SessionStore` protocol, not on files. Tests use `InMemorySessionStore`.
- Time and ID generation are injected, so tests assert exact timestamps and durations without sleeping.
- `Analytics` is an ordinary class with a singleton for convenience, so each test gets a fresh instance.
- `FileSessionStore` takes its directory as a parameter and is tested against a temporary one.

## Trade-offs and what I would do next

- **Up to one batch of events can be lost in a hard crash**, because they are buffered in memory. Lowering `flushBatchSize` to 1 removes the window at the cost of a write per event. A timed flush would narrow it further.
- **No upload.** The brief asks for recording and persistence. A network uploader would read completed sessions from the store, send them in batches, and delete them on success; the store protocol already has what it needs for that.
- **Flat files, not a database.** Good for append-and-read-back. Querying across sessions would justify SQLite, which can be added as another `SessionStore` without changing `Analytics`.
- **Whole-number doubles** (`3.0`) are stored as JSON `3` and read back as `.int(3)`. Plain JSON was preferred over a tagged format because it is what a backend would expect.
- **Not included:** automatic session handling on app foreground/background, user identity, Objective-C bridging, file encryption.

import AnalyticsKit
import Foundation

/// Bridges the SDK to SwiftUI: forwards user actions to `Analytics` and
/// republishes what the SDK has stored so the views can show it.
@MainActor
final class DemoViewModel: ObservableObject {
    @Published private(set) var activeSession: Session?
    @Published private(set) var sessions: [Session] = []
    @Published var errorMessage: String?

    private let analytics: Analytics

    init(analytics: Analytics = .shared) {
        self.analytics = analytics
    }

    func startSession() {
        analytics.startSession(properties: ["source": "demo_app"])
        refresh()
    }

    func endSession() {
        analytics.endSession()
        refresh()
    }

    func track(_ name: String, properties: [String: PropertyValue] = [:]) {
        analytics.track(name, properties: properties)
        refresh()
    }

    func refresh() {
        Task {
            do {
                sessions = try await analytics.sessions().reversed()
                activeSession = analytics.currentSession
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func events(in session: Session) async -> [Event] {
        do {
            return try await analytics.events(in: session.id)
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    /// Turns text typed into the form into the closest matching property type.
    static func propertyValue(from text: String) -> PropertyValue {
        if let int = Int(text) { return .int(int) }
        if let double = Double(text) { return .double(double) }
        if let bool = Bool(text.lowercased()) { return .bool(bool) }
        return .string(text)
    }
}

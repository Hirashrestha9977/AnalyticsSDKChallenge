import AnalyticsKit
import SwiftUI

/// Shows what was persisted for one session by reading it back through the SDK.
struct SessionDetailView: View {
    let session: Session
    @ObservedObject var viewModel: DemoViewModel
    @State private var events: [Event] = []

    var body: some View {
        List {
            Section("Session") {
                LabeledContent("ID", value: session.id.uuidString.prefix(8) + "…")
                LabeledContent("Status", value: session.status.rawValue.capitalized)
                LabeledContent("Started", value: session.startedAt.formatted(date: .abbreviated, time: .standard))
                if let endedAt = session.endedAt {
                    LabeledContent("Ended", value: endedAt.formatted(date: .abbreviated, time: .standard))
                }
                PropertyList(properties: session.properties)
            }

            Section("Events (\(events.count))") {
                if events.isEmpty {
                    Text("No events").foregroundStyle(.secondary)
                }
                ForEach(events) { event in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(event.name).font(.headline)
                            Spacer()
                            Text(event.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        PropertyList(properties: event.properties)
                    }
                }
            }
        }
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            events = await viewModel.events(in: session)
        }
    }
}

private struct PropertyList: View {
    let properties: [String: PropertyValue]

    var body: some View {
        ForEach(properties.sorted { $0.key < $1.key }, id: \.key) { key, value in
            HStack {
                Text(key)
                Spacer()
                Text(value.description)
            }
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
        }
    }
}

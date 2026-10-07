import AnalyticsKit
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = DemoViewModel()
    @State private var eventName = ""
    @State private var propertyKey = ""
    @State private var propertyValue = ""

    private var isRecording: Bool { viewModel.activeSession != nil }

    var body: some View {
        NavigationStack {
            List {
                sessionSection
                quickEventsSection
                customEventSection
                storedSessionsSection
            }
            .navigationTitle("AnalyticsKit Demo")
            .onAppear { viewModel.refresh() }
            .alert("Something went wrong", isPresented: errorIsPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private var sessionSection: some View {
        Section("Session") {
            if let session = viewModel.activeSession {
                LabeledContent("Status") {
                    Label("Recording", systemImage: "record.circle.fill").foregroundStyle(.red)
                }
                LabeledContent("Started", value: session.startedAt.formatted(date: .omitted, time: .standard))
                LabeledContent("Events", value: "\(session.eventCount)")
                Button("End Session", role: .destructive) { viewModel.endSession() }
            } else {
                LabeledContent("Status", value: "Not recording")
                Button("Start Session") { viewModel.startSession() }
            }
        }
    }

    private var quickEventsSection: some View {
        Section {
            Button("Screen Viewed") {
                viewModel.track("screen_viewed", properties: ["screen": "home"])
            }
            Button("Button Tapped") {
                viewModel.track("button_tapped", properties: ["button": "buy_now", "position": 2])
            }
            Button("Purchase Completed") {
                viewModel.track(
                    "purchase_completed",
                    properties: ["item": "shoes", "price": 59.99, "quantity": 1, "gift": false]
                )
            }
        } header: {
            Text("Quick events")
        } footer: {
            if !isRecording {
                Text("Start a session to record events.")
            }
        }
        .disabled(!isRecording)
    }

    private var customEventSection: some View {
        Section("Custom event") {
            TextField("Event name", text: $eventName)
            TextField("Property key (optional)", text: $propertyKey)
            TextField("Property value", text: $propertyValue)
            Button("Track Event", action: trackCustomEvent)
                .disabled(eventName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .disabled(!isRecording)
    }

    private var storedSessionsSection: some View {
        Section("Stored sessions") {
            if viewModel.sessions.isEmpty {
                Text("Nothing recorded yet").foregroundStyle(.secondary)
            }
            ForEach(viewModel.sessions) { session in
                NavigationLink {
                    SessionDetailView(session: session, viewModel: viewModel)
                } label: {
                    SessionRow(session: session)
                }
            }
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }

    private func trackCustomEvent() {
        let key = propertyKey.trimmingCharacters(in: .whitespaces)
        let properties = key.isEmpty ? [:] : [key: DemoViewModel.propertyValue(from: propertyValue)]
        viewModel.track(eventName, properties: properties)
        eventName = ""
        propertyKey = ""
        propertyValue = ""
    }
}

private struct SessionRow: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.startedAt.formatted(date: .abbreviated, time: .standard))
                Spacer()
                Text(session.status.rawValue.capitalized)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(statusColor)
            }
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var summary: String {
        let events = "\(session.eventCount) event\(session.eventCount == 1 ? "" : "s")"
        guard let duration = session.duration else { return events }
        return "\(events) · \(Duration.seconds(duration).formatted(.units(allowed: [.minutes, .seconds])))"
    }

    private var statusColor: Color {
        switch session.status {
        case .active: return .red
        case .ended: return .green
        case .interrupted: return .orange
        }
    }
}

#Preview {
    ContentView()
}

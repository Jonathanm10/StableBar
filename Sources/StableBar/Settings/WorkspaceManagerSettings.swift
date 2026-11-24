import Observation
import SwiftUI

extension EnvironmentValues {
    /// The window managers a scene says are found, so a drawing doesn't depend on what the drawing Mac has installed.
    @Entry var workspaceManagersSample: Set<WorkspaceSource>?
}

/// Looks for the installed window managers, one lookup at a time. The lookup reads the file system, which can stall on
/// a disconnected network volume and keep its thread, so a caller that comes while one runs waits for its result.
@MainActor
final class WorkspaceManagerLookup {
    static let installed = WorkspaceManagerLookup {
        WorkspaceSource.installed(path: shellEnvironment.withLock { $0["PATH", default: ""] })
    }

    private let work: @Sendable () -> Set<WorkspaceSource>
    private var running: Task<Set<WorkspaceSource>, Never>?

    init(_ work: @escaping @Sendable () -> Set<WorkspaceSource>) {
        self.work = work
    }

    func run() async -> Set<WorkspaceSource> {
        if let running { return await running.value }
        let work = work
        let lookup = Task { (try? await BlockingWork.run(work)) ?? [] }
        running = lookup
        let found = await lookup.value
        if running == lookup { running = nil }
        return found
    }
}

/// Runs `WorkspaceManagerScan`'s scans, off the main actor.
@MainActor @Observable
final class WorkspaceManagerFinder {
    private(set) var scan = WorkspaceManagerScan()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let lookup: WorkspaceManagerLookup
    @ObservationIgnored private var observation: NotificationObservation?

    init(lookup: WorkspaceManagerLookup = .installed, notifications: NotificationCenter = .default) {
        self.lookup = lookup
        // Until the login shell's PATH arrives, a scan misses what Homebrew installed.
        observation = NotificationObservation(loginShellEnvironmentLoaded, in: notifications) { [weak self] in self?.send(.rescan) }
    }

    func send(_ event: WorkspaceManagerScan.Event) {
        for effect in scan.handle(event) {
            switch effect {
            case .scan: start()
            }
        }
    }

    private func start() {
        let lookup = lookup
        task = Task { [weak self] in
            let found = await lookup.run()
            guard !Task.isCancelled else { return }
            self?.task = nil
            self?.send(.finished(found))
        }
    }

    deinit { task?.cancel() }
}

/// Stops observing when released, so a main-actor owner needn't reach the observer from its deinit.
private final class NotificationObservation: @unchecked Sendable {
    private let center: NotificationCenter
    private let observer: any NSObjectProtocol

    init(_ name: Notification.Name, in center: NotificationCenter, perform: @escaping @MainActor @Sendable () -> Void) {
        self.center = center
        observer = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { perform() }
        }
    }

    deinit { center.removeObserver(observer) }
}

/// Settings' choice of workspace manager: the window managers found on this Mac, then macOS Spaces.
struct WorkspaceManagerSettings: View {
    let editor: ConfigurationEditor
    @State private var finder = WorkspaceManagerFinder()
    @Environment(\.workspaceManagersSample) private var sample

    private static let hint = (try? AttributedString(markdown: """
        Only window managers found on this Mac are listed. \
        [Supported managers](https://github.com/stablebox/StableBar/blob/main/docs/widgets.md#workspace-managers)
        """)) ?? AttributedString("Only window managers found on this Mac are listed.")

    var body: some View {
        let source = editor.store.configuration?.workspaceSource ?? .aerospace
        let sections = WorkspaceManagerOption.sections(found: finder.scan.found, configured: source)
        let selected = sections.joined().first { $0.source == source } ?? .spaces
        LabeledContent {
            HStack(spacing: 8) {
                SettingsMenu(title: "Workspace manager", selectedTitle: selected.title) {
                    Picker("Workspace manager", selection: Binding(get: { source }, set: {
                        if $0 != source { editor.change(ConfigurationEdit(action: .workspaceSource, name: $0.rawValue)) }
                    })) {
                        ForEach(sections.indices, id: \.self) { index in
                            if index > 0 { Divider() }
                            ForEach(sections[index]) { Text($0.title).tag($0.source) }
                        }
                    }
                    .pickerStyle(.inline)
                }
                Button("Rescan") { finder.send(.rescan) }
                    .disabled(finder.scan.isScanning)
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text("Workspace manager")
                Text(Self.hint).font(.caption).foregroundStyle(.secondary)
            }
        }
        .task { if let sample { finder.send(.finished(sample)) } else { finder.send(.rescan) } }
        if source != .spaces, let found = finder.scan.found, !found.contains(source) {
            Label("\(source.title) isn't installed, so workspace widgets can't show its workspaces. Install it, or choose macOS Spaces.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(SettingsPalette.warning)
                .groupRow()
        }
    }
}

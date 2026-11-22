import Observation
import SwiftUI

extension EnvironmentValues {
    /// The window managers a scene says are found, so a drawing doesn't depend on what the drawing Mac has installed.
    @Entry var workspaceManagersSample: Set<WorkspaceSource>?
}

/// Runs `WorkspaceManagerScan`'s scans. The lookup reads the file system, which can stall on a disconnected network
/// volume, so it never runs on the main actor.
@MainActor @Observable
final class WorkspaceManagerFinder {
    private(set) var scan = WorkspaceManagerScan()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let lookup: @Sendable () -> Set<WorkspaceSource>

    init(lookup: @escaping @Sendable () -> Set<WorkspaceSource> = {
        WorkspaceSource.installed(path: shellEnvironment.withLock { $0["PATH", default: ""] })
    }) {
        self.lookup = lookup
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
            let found = (try? await BlockingWork.run(lookup)) ?? []
            guard !Task.isCancelled else { return }
            self?.task = nil
            self?.send(.finished(found))
        }
    }

    deinit { task?.cancel() }
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
        let managers = WorkspaceManagerOption.managers(found: finder.scan.found, configured: source)
        let selected = (managers + [.spaces]).first { $0.source == source } ?? .spaces
        LabeledContent {
            HStack(spacing: 8) {
                SettingsMenu(title: "Workspace manager", selectedTitle: selected.title) {
                    Picker("Workspace manager", selection: Binding(get: { source }, set: {
                        if $0 != source { editor.change(ConfigurationEdit(action: .workspaceSource, name: $0.rawValue)) }
                    })) {
                        ForEach(managers) { Text($0.title).tag($0.source) }
                        Divider()
                        Text(WorkspaceManagerOption.spaces.title).tag(WorkspaceSource.spaces)
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

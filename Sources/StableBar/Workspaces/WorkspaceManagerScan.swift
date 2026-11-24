import Foundation

/// Which window managers Settings lists: whether a scan for their commands runs, and what the last one found.
struct WorkspaceManagerScan: StateMachine {
    enum Mode: Equatable {
        case notScanned
        /// A scan runs; the previous one's result stays listed meanwhile.
        case scanning(previous: Set<WorkspaceSource>?)
        /// A rescan came during the scan, which may have read the `PATH` before it changed, so another scan follows.
        case scanningThenAgain(previous: Set<WorkspaceSource>?)
        case found(Set<WorkspaceSource>)
    }

    enum Event: Equatable {
        case rescan
        /// A scan found these, or a scene says they're found without scanning.
        case finished(Set<WorkspaceSource>)
    }

    enum Effect: Equatable {
        /// Looks for each window manager's command.
        case scan
    }

    private(set) var mode = Mode.notScanned

    var found: Set<WorkspaceSource>? {
        switch mode {
        case .notScanned: nil
        case let .scanning(previous), let .scanningThenAgain(previous): previous
        case let .found(found): found
        }
    }

    var isScanning: Bool {
        switch mode {
        case .scanning, .scanningThenAgain: true
        case .notScanned, .found: false
        }
    }

    mutating func handle(_ event: Event) -> [Effect] {
        switch (event, mode) {
        case let (.rescan, .scanning(previous)):
            mode = .scanningThenAgain(previous: previous)
            return []
        case (.rescan, .scanningThenAgain):
            return []
        case (.rescan, _):
            mode = .scanning(previous: found)
            return [.scan]
        case let (.finished(found), .scanningThenAgain):
            mode = .scanning(previous: found)
            return [.scan]
        case let (.finished(found), _):
            mode = .found(found)
            return []
        }
    }
}

/// An item of Settings' workspace manager menu.
struct WorkspaceManagerOption: Equatable, Identifiable, Sendable {
    let source: WorkspaceSource
    /// A scan looked for its command and didn't find it.
    let isMissing: Bool

    var id: WorkspaceSource { source }

    var title: String {
        if isMissing { "\(source.title) (not found)" } else if source == .spaces { "macOS Spaces" } else { source.title }
    }

    static let spaces = WorkspaceManagerOption(source: .spaces, isMissing: false)

    /// The window managers listed above macOS Spaces: those `found`, and the `configured` one even when it isn't, so the
    /// menu always shows what the bar uses. Before the first scan, `found` is nil and nothing is marked missing.
    static func managers(found: Set<WorkspaceSource>?, configured: WorkspaceSource) -> [WorkspaceManagerOption] {
        WorkspaceSource.windowManagers.compactMap { source in
            let isFound = found?.contains(source) ?? false
            guard isFound || source == configured else { return nil }
            return WorkspaceManagerOption(source: source, isMissing: found != nil && !isFound)
        }
    }

    /// The menu's sections, separated by dividers: the window managers, when there's one, then macOS Spaces.
    static func sections(found: Set<WorkspaceSource>?, configured: WorkspaceSource) -> [[WorkspaceManagerOption]] {
        [managers(found: found, configured: configured), [spaces]].filter { !$0.isEmpty }
    }
}

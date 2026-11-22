import Foundation

let kiwideskBundleID = "com.kiwicanopy.kiwidesk"

// KiwiDesk writes its numbers as JSON doubles, so ids decode as Double and convert.

private struct KiwiDeskState: Decodable {
    let activeSpace: String?
    let spaces: [Space]
    let windows: [Window]

    struct Space: Decodable {
        let id: String
        /// The Space's windows on the Desktops screens show, in its layout's order.
        let windows: [Double]
    }

    struct Window: Decodable {
        let id: Double
        let app: String
        let bundleId: String?
        let title: String
        let pocket: String?
    }
}

private struct KiwiDeskListedWindow: Decodable {
    let id: Double
    let display: Double?
    let shown: Bool
    let focused: Bool
}

/// Runs `get_state` and `list_windows` together: only the second says which screen a window is on.
func readKiwiDeskWorkspaces(_ executable: String, screenIDs: [UInt32], timeout: Double = 10) async throws -> [Workspace] {
    async let state = runCommand(executable, arguments: ["get_state"], timeout: timeout)
    async let windows = runCommand(executable, arguments: ["list_windows"], timeout: timeout)
    return try await kiwideskSnapshot(state: state, windows: windows, screenIDs: screenIDs)
}

/// KiwiDesk's Spaces in its own order, each with the windows of the Desktop on screen. `get_state` names no screen
/// per Space, so a Space goes on its windows' screen; one without windows there goes on the active Space's screen,
/// else the main one.
func kiwideskSnapshot(state: Data, windows: Data, screenIDs: [UInt32]) throws -> [Workspace] {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let state = try decoder.decode(KiwiDeskState.self, from: state)
    let listed = try decoder.decode([KiwiDeskListedWindow].self, from: windows)
    let known = Dictionary(state.windows.map { (Int($0.id), $0) }, uniquingKeysWith: { first, _ in first })
    let placed = Dictionary(listed.map { (Int($0.id), $0) }, uniquingKeysWith: { first, _ in first })

    func screen(of space: KiwiDeskState.Space) -> Int? {
        let windows = space.windows.compactMap { placed[Int($0)] }
        return (windows.filter(\.shown) + windows.filter { !$0.shown }).lazy
            .compactMap { $0.display.flatMap { UInt32(exactly: $0) }.flatMap { screenIDs.firstIndex(of: $0) } }
            .first.map { $0 + 1 }
    }

    let activeScreen = state.spaces.first { $0.id == state.activeSpace }.flatMap(screen) ?? 1
    return state.spaces.map { space in
        var apps: [WorkspaceApp] = []
        var seen = Set<String>()
        let windows = space.windows.compactMap { id -> WorkspaceWindow? in
            guard let window = known[Int(id)], window.pocket != "pocketed" else { return nil }
            let app = WorkspaceApp(workspace: space.id, name: window.app, bundleID: window.bundleId ?? window.app)
            if seen.insert(app.bundleID).inserted { apps.append(app) }
            return WorkspaceWindow(id: Int(id), title: window.title, app: app, isFocused: placed[Int(id)]?.focused == true)
        }
        let isActive = space.id == state.activeSpace
        return Workspace(name: space.id, isFocused: isActive,
                         isVisible: isActive || space.windows.contains { placed[Int($0)]?.shown == true },
                         monitor: screen(of: space) ?? activeScreen,
                         apps: apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
                         windows: windows)
    }
}

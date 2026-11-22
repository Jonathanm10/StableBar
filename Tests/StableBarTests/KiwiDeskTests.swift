import Foundation
@testable import StableBar
import Testing

/// `get_state` and `list_windows` answers in the shape KiwiDesk prints, trimmed to the fields StableBar reads.
@Suite struct KiwiDeskTests {
    private let state = Data(#"""
    {"active_space":"2","desktop":1,"exec_running":0,"monitor_count":1,
     "spaces":[
      {"id":"1","mode":"bsp","windows":[11,12],"focused":12,"away_windows":[]},
      {"id":"2","mode":"bsp","windows":[21,22,23],"focused":21,"away_windows":[29]},
      {"id":"mail","mode":"monocle","windows":[],"focused":null,"away_windows":[]}
     ],
     "windows":[
      {"id":11,"app":"Safari","bundle_id":"com.apple.Safari","title":"Docs","floating":false,"pocket":null},
      {"id":12,"app":"Ghostty","bundle_id":"com.mitchellh.ghostty","title":"zsh","floating":false,"pocket":null},
      {"id":21,"app":"Notes","bundle_id":"com.apple.Notes","title":"List","floating":false,"pocket":null},
      {"id":22,"app":"Safari","bundle_id":"com.apple.Safari","title":"News","floating":true,"pocket":null},
      {"id":23,"app":"Music","bundle_id":"com.apple.Music","title":"Music","floating":true,"pocket":"pocketed"}
     ],
     "away_windows":[{"id":29,"app":"Mail","bundle_id":"com.apple.mail","space_id":"2","up":false,"desktop":2}]}
    """#.utf8)

    private let listed = Data(#"""
    [{"id":11,"app":"Safari","title":"Docs","pid":1,"space_id":"1","display":1,"shown":false,"focused":false},
     {"id":12,"app":"Ghostty","title":"zsh","pid":2,"space_id":"1","display":1,"shown":false,"focused":false},
     {"id":21,"app":"Notes","title":"List","pid":3,"space_id":"2","display":1,"shown":true,"focused":true},
     {"id":22,"app":"Safari","title":"News","pid":1,"space_id":"2","display":1,"shown":true,"focused":false},
     {"id":23,"app":"Music","title":"Music","pid":4,"space_id":"2","display":1,"shown":false,"focused":false}]
    """#.utf8)

    /// Two screens: 90 is the main one, 80 the second.
    private func twoScreens(active: String, spaces: String, windows: String, listed: String) throws -> [Workspace] {
        try kiwideskSnapshot(state: Data(#"{"active_space":"\#(active)","spaces":[\#(spaces)],"windows":[\#(windows)]}"#.utf8),
                             windows: Data("[\(listed)]".utf8), screenIDs: [90, 80])
    }

    private func window(_ id: Int, app: String = "Safari") -> String {
        #"{"id":\#(id),"app":"\#(app)","bundle_id":"com.example.\#(app)","title":"","floating":false,"pocket":null}"#
    }

    private func listing(_ id: Int, space: String, display: Int, shown: Bool) -> String {
        #"{"id":\#(id),"space_id":"\#(space)","display":\#(display),"shown":\#(shown),"focused":false}"#
    }

    @Test func aSingleScreenListsSpacesInKiwiDesksOrder() throws {
        let snapshot = try kiwideskSnapshot(state: state, windows: listed, screenIDs: [1])
        #expect(snapshot.map(\.name) == ["1", "2", "mail"])
        #expect(snapshot.map(\.isFocused) == [false, true, false])
        #expect(snapshot.map(\.isVisible) == [false, true, false])
        #expect(snapshot.map(\.monitor) == [1, 1, 1])
        #expect(snapshot[0].windows.map(\.id) == [11, 12])
        #expect(snapshot[0].apps.map(\.name) == ["Ghostty", "Safari"])
        #expect(snapshot[1].windows.map(\.isFocused) == [true, false])
        #expect(snapshot[1].apps.map(\.bundleID) == ["com.apple.Notes", "com.apple.Safari"])
    }

    @Test func windowsInThePocketOrOnHiddenDesktopsDontShow() throws {
        let snapshot = try kiwideskSnapshot(state: state, windows: listed, screenIDs: [1])
        #expect(snapshot[1].windows.map(\.id) == [21, 22])
        #expect(!snapshot[1].apps.contains { $0.name == "Music" || $0.name == "Mail" })
    }

    @Test func aWindowWithoutABundleIDUsesItsAppName() throws {
        let snapshot = try twoScreens(active: "1", spaces: #"{"id":"1","windows":[11]}"#,
                                      windows: #"{"id":11,"app":"sbcl","bundle_id":null,"title":"REPL","floating":false,"pocket":null}"#,
                                      listed: listing(11, space: "1", display: 90, shown: true))
        #expect(snapshot[0].windows.first?.app == WorkspaceApp(workspace: "1", name: "sbcl", bundleID: "sbcl"))
    }

    @Test func spacesGoOnTheScreenTheirWindowsAreOn() throws {
        let snapshot = try twoScreens(
            active: "2",
            spaces: #"{"id":"1","windows":[11]},{"id":"2","windows":[21]},{"id":"3","windows":[31]}"#,
            windows: [window(11), window(21), window(31)].joined(separator: ","),
            listed: [listing(11, space: "1", display: 80, shown: true), listing(21, space: "2", display: 90, shown: true),
                     listing(31, space: "3", display: 80, shown: false)].joined(separator: ","))
        #expect(snapshot.map(\.monitor) == [2, 1, 2])
        #expect(snapshot.map(\.isVisible) == [true, true, false])
        #expect(snapshot.map(\.isFocused) == [false, true, false])
    }

    @Test func anEmptyActiveSpaceGoesOnTheMainScreen() throws {
        let snapshot = try twoScreens(active: "2", spaces: #"{"id":"1","windows":[11]},{"id":"2","windows":[]}"#,
                                      windows: window(11), listed: listing(11, space: "1", display: 80, shown: true))
        #expect(snapshot.map(\.monitor) == [2, 1])
        #expect(snapshot[1].isFocused && snapshot[1].isVisible)
    }

    @Test func anEmptySpaceGoesOnTheActiveSpacesScreen() throws {
        let snapshot = try twoScreens(active: "1", spaces: #"{"id":"1","windows":[11]},{"id":"2","windows":[]}"#,
                                      windows: window(11), listed: listing(11, space: "1", display: 80, shown: true))
        #expect(snapshot.map(\.monitor) == [2, 2])
        #expect(!snapshot[1].isVisible)
    }

    @Test func idsWrittenAsDecimalsStillMatch() throws {
        let snapshot = try kiwideskSnapshot(
            state: Data(#"{"active_space":"1","spaces":[{"id":"1","windows":[11.0]}],"windows":[{"id":11.0,"app":"Safari","bundle_id":null,"title":"","floating":false,"pocket":null}]}"#.utf8),
            windows: Data(#"[{"id":11.0,"space_id":"1","display":80.0,"shown":true,"focused":true}]"#.utf8), screenIDs: [90, 80])
        #expect(snapshot[0].windows.map(\.id) == [11])
        #expect(snapshot[0].monitor == 2)
    }
}

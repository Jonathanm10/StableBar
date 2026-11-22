import Foundation
@testable import StableBar
import Testing

@Suite struct WorkspaceManagerScanTests {
    private func option(_ source: WorkspaceSource, missing: Bool = false) -> WorkspaceManagerOption {
        WorkspaceManagerOption(source: source, isMissing: missing)
    }

    @Test func rescanStartsAScan() {
        var scan = WorkspaceManagerScan()
        #expect(scan.handle(.rescan) == [.scan])
        #expect(scan.isScanning)
        #expect(scan.found == nil)
    }

    @Test func rescanWhileScanningIsIgnored() {
        var scan = WorkspaceManagerScan()
        _ = scan.handle(.rescan)
        #expect(scan.handle(.rescan) == [])
        #expect(scan.isScanning)
    }

    @Test func finishedKeepsWhatWasFound() {
        var scan = WorkspaceManagerScan()
        _ = scan.handle(.rescan)
        #expect(scan.handle(.finished([.yabai])) == [])
        #expect(scan.found == [.yabai])
        #expect(!scan.isScanning)
    }

    @Test func rescanKeepsThePreviousResultWhileScanning() {
        var scan = WorkspaceManagerScan()
        _ = scan.handle(.rescan)
        _ = scan.handle(.finished([.yabai]))
        #expect(scan.handle(.rescan) == [.scan])
        #expect(scan.found == [.yabai])
        #expect(scan.isScanning)
    }

    @Test func aSampleFinishesWithoutScanning() {
        var scan = WorkspaceManagerScan()
        #expect(scan.handle(.finished([.aerospace])) == [])
        #expect(scan.found == [.aerospace])
        #expect(!scan.isScanning)
    }

    @Test func listsFoundManagersInOrder() {
        #expect(WorkspaceManagerOption.managers(found: [.rift, .aerospace], configured: .aerospace)
            == [option(.aerospace), option(.rift)])
    }

    @Test func addsTheConfiguredManagerWhenNotFound() {
        let managers = WorkspaceManagerOption.managers(found: [.aerospace], configured: .yabai)
        #expect(managers == [option(.aerospace), option(.yabai, missing: true)])
        #expect(managers.last?.title == "yabai (not found)")
    }

    @Test func unnamedSourceShowsAeroSpaceMissing() {
        let managers = WorkspaceManagerOption.managers(found: [], configured: .aerospace)
        #expect(managers == [option(.aerospace, missing: true)])
        #expect(managers.first?.title == "AeroSpace (not found)")
    }

    @Test func spacesIsNeverAmongTheManagers() {
        #expect(WorkspaceManagerOption.managers(found: [], configured: .spaces) == [])
        #expect(WorkspaceManagerOption.spaces.title == "macOS Spaces")
    }

    @Test func beforeTheFirstScanListsOnlyTheConfiguredManager() {
        #expect(WorkspaceManagerOption.managers(found: nil, configured: .omniwm) == [option(.omniwm)])
    }

    @Test func installedFindsCommandsOnPath() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(FileManager.default.createFile(atPath: folder.appending(path: "yabai").path, contents: Data(),
                                               attributes: [.posixPermissions: 0o755]))
        let installed = WorkspaceSource.installed(path: folder.path)
        #expect(installed.contains(.yabai))
        #expect(installed.isDisjoint(with: [.aerospace, .rift, .spaces]))
    }
}

import AppKit
import Testing
@testable import StableBar

private let command = URL(filePath: "/usr/local/bin/stablebar")
private let cache = URL(filePath: "/Users/me/Library/Caches/org.stablebar.app", directoryHint: .isDirectory)
private let app = URL(filePath: "/Applications/StableBar.app", directoryHint: .isDirectory)
private let mac = UninstallSnapshot(menuBarHides: true, turnedOnMenuBarAutoHide: true, opensAtLogin: true, commands: [command],
                                    files: [cache], app: app)

private func confirmed(_ snapshot: UninstallSnapshot = mac) -> UninstallFlow {
    var flow = UninstallFlow()
    _ = flow.handle(.open(snapshot))
    _ = flow.handle(.confirm(UninstallOptions(snapshot)))
    return flow
}

@Test func uninstallFlowShowsTheMacReadWhenItOpens() {
    var flow = UninstallFlow()
    #expect(!flow.isPresented)
    #expect(flow.handle(.open(mac)) == [])
    #expect(flow.phase == .confirming)
    #expect(flow.snapshot == mac)
    #expect(flow.isPresented)
}

@Test func uninstallFlowCancelsOnlyBeforeItStarts() {
    var flow = UninstallFlow()
    _ = flow.handle(.open(mac))
    _ = flow.handle(.cancel)
    #expect(flow.phase == .closed)
    #expect(!flow.isPresented)

    flow = confirmed()
    _ = flow.handle(.cancel)
    #expect(flow.phase == .running([]))
}

@Test func uninstallFlowRunsTheStepsBeforeQuittingWithTheChosenOptions() {
    var flow = UninstallFlow()
    _ = flow.handle(.open(mac))
    var options = UninstallOptions(mac)
    options.showsMenuBar = false
    #expect(flow.handle(.confirm(options)) == [.run([.loginItem, .command(command)])])
    #expect(flow.phase == .running([]))
    #expect(flow.handle(.open(UninstallSnapshot())) == [])
    #expect(flow.snapshot == mac)
}

@Test func uninstallFlowQuitsOnceEveryStepIsDoneAndTheRestWaitsForIt() {
    var flow = confirmed()
    let outcomes = [UninstallOutcome(step: .showMenuBar, error: nil), UninstallOutcome(step: .loginItem, error: nil)]
    #expect(flow.handle(.ranSteps(outcomes)) == [.startFinish])
    #expect(flow.handle(.startedFinish(failure: nil)) == [.quit])
    #expect(flow.phase == .quitting)
    #expect(!flow.isPresented)
}

@Test func uninstallFlowWaitsForYouToQuitWhenHomebrewInstalledStableBar() {
    var snapshot = mac
    snapshot.homebrew = true
    var flow = confirmed(snapshot)
    _ = flow.handle(.ranSteps([UninstallOutcome(step: .loginItem, error: nil)]))
    #expect(flow.handle(.startedFinish(failure: nil)) == [])
    #expect(flow.phase == .finished([UninstallOutcome(step: .loginItem, error: nil)], finishing: true))
    #expect(flow.isPresented)
    #expect(flow.handle(.quit) == [.quit])
    #expect(flow.phase == .quitting)
}

@Test func uninstallFlowListsAFailedStepAndStillFinishesAfterQuitting() {
    var flow = confirmed()
    let outcomes = [UninstallOutcome(step: .command(command), error: "Cancelled.")]
    #expect(flow.handle(.ranSteps(outcomes)) == [.startFinish])
    #expect(flow.handle(.startedFinish(failure: nil)) == [])
    #expect(flow.phase == .finished(outcomes, finishing: true))
}

@Test func uninstallFlowLeavesEverythingElseWhenAnotherStableBarKeepsRunning() {
    var flow = confirmed(UninstallSnapshot(running: 1))
    let outcomes = [UninstallOutcome(step: .quit(1), error: "StableBar is still running.")]
    #expect(flow.handle(.ranSteps(outcomes)) == [])
    #expect(flow.phase == .finished(outcomes, finishing: false))
}

@Test func uninstallFlowListsTheStepsAfterQuittingWhenTheyCanNotStart() {
    var flow = confirmed()
    _ = flow.handle(.ranSteps([]))
    #expect(flow.handle(.startedFinish(failure: "No such file.")) == [])
    let error = "StableBar couldn’t start this step: No such file."
    #expect(flow.phase == .finished([UninstallOutcome(step: .permissions, error: error), UninstallOutcome(step: .files([cache]), error: error),
                                     UninstallOutcome(step: .app(app), error: error)], finishing: false))
}

@Test func uninstallFlowQuitsOnlyFromItsResult() {
    var flow = UninstallFlow()
    #expect(flow.handle(.quit) == [])
    _ = flow.handle(.open(mac))
    #expect(flow.handle(.quit) == [])
    flow = confirmed()
    #expect(flow.handle(.quit) == [])
    #expect(flow.phase == .running([]))
}

@MainActor
@Test func uninstallEndsTheSheetThatWouldKeepStableBarFromQuitting() {
    _ = NSApplication.shared
    let window = NSWindow(contentRect: CGRect(x: -9000, y: -6000, width: 400, height: 300), styleMask: [.titled], backing: .buffered,
                          defer: false)
    let sheet = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
    for window in [window, sheet] { window.isReleasedWhenClosed = false }
    defer { window.orderOut(nil) }
    window.orderFrontRegardless()
    window.beginSheet(sheet)
    #expect(window.attachedSheet === sheet)
    UninstallController.endSheets(of: [window])
    #expect(window.attachedSheet == nil)
    #expect(!sheet.isVisible)
}

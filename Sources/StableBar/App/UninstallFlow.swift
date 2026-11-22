import Foundation

/// Settings › General › Uninstall, from the confirmation to quitting. The steps that would take away the app, its
/// permissions and preferences wait for `--finish-uninstall`, which starts before StableBar quits, so a step that fails
/// first leaves StableBar whole and the sheet lists what's left until you quit it.
struct UninstallFlow: StateMachine, Equatable {
    enum Phase: Equatable {
        case closed
        case confirming
        /// The steps before quitting run, then `--finish-uninstall` starts; holds the outcomes so far.
        case running([UninstallOutcome])
        /// A step failed, or Homebrew installed StableBar, so the sheet lists what's left and quitting finishes.
        /// `finishing` when `--finish-uninstall` waits for StableBar to quit.
        case finished([UninstallOutcome], finishing: Bool)
        case quitting
    }

    enum Event: Equatable {
        /// The sheet opens on what Uninstall read from this Mac just then.
        case open(UninstallSnapshot)
        case cancel
        case confirm(UninstallOptions)
        case ranSteps([UninstallOutcome])
        /// `failure` says why `--finish-uninstall` couldn't start, or is nil when it started.
        case startedFinish(failure: String?)
        case quit
    }

    /// `run` and `startFinish` are the last effect `handle` returns: their answer is the next event.
    enum Effect: Equatable {
        /// Stops what could write back the caches and preferences the steps remove, then runs the steps.
        case run([UninstallStep])
        case startFinish
        case quit
    }

    private(set) var phase = Phase.closed
    private(set) var snapshot = UninstallSnapshot()

    /// A sheet in a given phase, for scenes.
    init(snapshot: UninstallSnapshot = UninstallSnapshot(), phase: Phase = .closed) {
        self.snapshot = snapshot
        self.phase = phase
    }

    var isPresented: Bool {
        switch phase {
        case .closed, .quitting: false
        case .confirming, .running, .finished: true
        }
    }

    mutating func handle(_ event: Event) -> [Effect] {
        switch (event, phase) {
        case let (.open(snapshot), .closed):
            self.snapshot = snapshot
            phase = .confirming
            return []
        case (.cancel, .confirming):
            phase = .closed
            return []
        case let (.confirm(options), .confirming):
            phase = .running([])
            return [.run(snapshot.stepsBeforeQuit(options))]
        case let (.ranSteps(outcomes), .running):
            guard Uninstall.finishesAfterQuit(outcomes) else {
                phase = .finished(outcomes, finishing: false)
                return []
            }
            phase = .running(outcomes)
            return [.startFinish]
        case let (.startedFinish(failure), .running(outcomes)):
            let notStarted = failure.map { failure in
                snapshot.stepsAfterQuit.map { UninstallOutcome(step: $0, error: "StableBar couldn’t start this step: \(failure)") }
            } ?? []
            let outcomes = outcomes + notStarted
            guard outcomes.allSatisfy({ $0.error == nil }) && !snapshot.homebrew else {
                phase = .finished(outcomes, finishing: failure == nil)
                return []
            }
            phase = .quitting
            return [.quit]
        case (.quit, .finished):
            phase = .quitting
            return [.quit]
        default:
            return []
        }
    }
}

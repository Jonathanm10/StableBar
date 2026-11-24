import SwiftUI

/// Setup keeps fades with Reduce Motion, but changes geometry immediately. Views resolve this from their live
/// accessibility environment, rather than keeping the setting from when setup opened.
struct SetupMotion {
    enum StepEffect { case fade, rise }

    let reduceMotion: Bool

    var stepEffect: StepEffect { reduceMotion ? .fade : .rise }
    /// The bar gliding between its places on the stage, and to the top edge.
    var stageAnimation: Animation { reduceMotion ? .easeInOut(duration: 0.35) : .spring(duration: 0.85, bounce: 0) }

    func revealAnimation(delay: Double) -> Animation {
        // A departing step keeps its layout space until its fade ends.
        // Let that settle before fading in the new step.
        reduceMotion ? .easeOut(duration: 0.2).delay(0.2) : .smooth(duration: 0.5).delay(0.22 + delay)
    }

    var removalAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .easeIn(duration: 0.2)
    }

    /// Steps fade and drift; they never blur, which would redraw the whole screen every frame.
    func stepTransition(delay: Double) -> AnyTransition {
        let insertion: AnyTransition
        let removal: AnyTransition
        switch stepEffect {
        case .fade:
            insertion = .opacity
            removal = .opacity
        case .rise:
            insertion = .opacity.combined(with: .offset(y: 14))
            removal = .opacity.combined(with: .offset(y: -8))
        }
        return .asymmetric(insertion: insertion.animation(revealAnimation(delay: delay)),
                           removal: removal.animation(removalAnimation))
    }

    func movement(_ animation: Animation) -> Animation? {
        reduceMotion ? nil : animation
    }
}

/// Where the intro is `time` seconds after it starts, with or without Reduce Motion.
struct SetupIntro {
    let reduceMotion: Bool
    let time: Double

    var length: Double { reduceMotion ? 1.5 : 3.6 }
    /// The wallpaper's opacity, and its scale as it settles.
    var wallpaper: Double { fade(0, reduceMotion ? 0.5 : 0.8) }
    var zoom: Double { reduceMotion ? 1 : 1 + 0.1 * (1 - Self.settle.value(at: progress(time, 0, 1.9))) }
    /// How far the wallpaper has dimmed and softened.
    var softness: Double { reduceMotion ? progress(time, 0.5, 0.6) : UnitCurve.easeInOut.value(at: progress(time, 0.7, 1.0)) }
    var name: Double { fade(reduceMotion ? 0.6 : 1.0, reduceMotion ? 0.75 : 1.1) }
    var nameRise: Double { reduceMotion ? 0 : 26 * (1 - sprung(Self.rising, from: 1.0)) }
    /// How out of focus the name still is, and how far its letters still stand apart.
    var nameBlur: Double { reduceMotion ? 0 : 18 * (1 - name) }
    var nameSpread: Double { reduceMotion ? 0 : 16 * (1 - name) }
    /// Where the light crosses the name, from 0 to 1; it stays off with Reduce Motion.
    var sweep: Double { reduceMotion ? 0 : UnitCurve.easeInOut.value(at: progress(time, 1.55, 1.0)) }
    /// How wide the glowing line has grown, and how bright it is.
    var line: Double { reduceMotion ? 0 : Self.settle.value(at: progress(time, 1.75, 0.6)) }
    var glow: Double { reduceMotion ? 0 : progress(time, 1.75, 0.15) * (1 - progress(time, 2.6, 0.6)) }
    /// The bar's height as it opens from the line, as a fraction of its own, and its opacity.
    var open: Double { reduceMotion ? 1 : time < 2.15 ? 0.04 : 0.04 + 0.96 * sprung(Self.opening, from: 2.15) }
    var bar: Double { reduceMotion ? progress(time, 0.8, 0.5) : progress(time, 2.1, 0.12) }
    /// How far across the bar the light has passed, showing its widgets behind it.
    var widgets: Double { reduceMotion ? 1 : UnitCurve.easeInOut.value(at: progress(time, 2.35, 0.9)) }
    /// The tagline, then Get Started.
    var invitation: Double { fade(reduceMotion ? 1.0 : 2.75, reduceMotion ? 0.4 : 0.7) }
    var action: Double { reduceMotion ? invitation : fade(2.95, 0.65) }
    var actionRise: Double { reduceMotion ? 0 : 16 * (1 - sprung(Self.rising, from: 2.95)) }

    /// Fast out, long settle.
    private static let settle = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.16, y: 1), endControlPoint: UnitPoint(x: 0.3, y: 1))
    private static let opening = Spring(duration: 0.6, bounce: 0.22)
    private static let rising = Spring(duration: 0.8, bounce: 0.18)

    private func fade(_ start: Double, _ duration: Double) -> Double {
        reduceMotion ? progress(time, start, duration) : Self.settle.value(at: progress(time, start, duration))
    }

    /// Where `spring` is from 0 to 1 once it starts at `start`, at rest from the intro's end.
    private func sprung(_ spring: Spring, from start: Double) -> Double {
        time >= length ? 1 : spring.value(target: 1.0, time: max(time - start, 0))
    }
}

/// The bar building itself again on Make it yours' stage, `time` seconds after Get Started.
struct SetupDemoTimeline {
    let time: Double

    static let length = 14.2
    /// When two widgets swap places, and when the right ones group.
    static let swap = 4.95
    static let group = 5.67
    /// When the pointer clicks the clock, the CPU and the battery, and when their popup closes.
    static let clicks = [7.02, 8.42, 9.81]
    static let closing = 10.8
    /// When the bar starts to morph into each theme it tries on, and back into the person's own bar, each held a moment.
    static let looks = [11.0, 12.1]
    static let own = 13.2
    /// Cubic ease-in-out, and a long ease-out that lands softly.
    static let easeInOut = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.65, y: 0), endControlPoint: UnitPoint(x: 0.35, y: 1))
    static let easeOut = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.22, y: 1), endControlPoint: UnitPoint(x: 0.36, y: 1))

    /// The opacity of the bar's own widgets as they clear, before the last light shows them again.
    var ownShown: Double { time < 0.3 ? 1 - Self.easeOut.value(at: progress(time, 0, 0.25)) : 1 }
    var ownWipe: Double { time < 0.3 ? 1 : wipe(Self.own) }
    /// How wide the line under the bar has grown, and how bright it is.
    var line: Double { Self.easeOut.value(at: progress(time, 13.75, 0.45)) }
    var glow: Double { progress(time, 13.75, 0.1) * (1 - progress(time, 13.9, 0.3)) }

    /// How far the morph, and the light across the bar with it, that starts at `start` has come.
    func wipe(_ start: Double) -> Double {
        Self.easeInOut.value(at: progress(time, start, 0.75))
    }
}

/// How far `time` is through the span that begins at `start` and lasts `duration`, from 0 to 1.
func progress(_ time: Double, _ start: Double, _ duration: Double) -> Double {
    min(max((time - start) / duration, 0), 1)
}

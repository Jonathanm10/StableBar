import AppKit
import SwiftUI

/// The light or dark look macOS gives each display's menu bar, which follows that display's wallpaper, read from the
/// window of StableBar's status item: macOS moves it to the display whose menu bar is active and gives it that menu
/// bar's appearance. A display keeps the look it last had; one not seen yet has none.
@MainActor @Observable
final class MenuBarAppearance: NSObject {
    static let shared = MenuBarAppearance()
    /// By `BarDisplay.id`.
    private(set) var schemes: [Int: ColorScheme] = [:]
    @ObservationIgnored private weak var window: NSWindow?
    @ObservationIgnored private var observation: NSKeyValueObservation?

    func watch(_ window: NSWindow) {
        self.window = window
        observation = window.observe(\.effectiveAppearance, options: .initial) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.windowChanged() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(windowChanged), name: NSWindow.didChangeScreenNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification,
                                               object: nil)
    }

    /// `BarDisplay.id` follows the screens' order, so once screens change, a remembered look could belong to another one.
    @objc private func screensChanged() {
        schemes = [:]
        windowChanged()
    }

    func record(_ appearance: NSAppearance, on displayID: Int) {
        schemes[displayID] = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }

    /// The appearance can change a moment before the window moves to its new display, so both are read on the next turn.
    @objc private func windowChanged() {
        DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.readWindow() } }
    }

    private func readWindow() {
        guard let window, let screen = window.screen else { return }
        record(window.effectiveAppearance, on: BarDisplay(screen: screen).id)
    }
}

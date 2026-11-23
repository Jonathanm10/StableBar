import AppKit
import SwiftUI

/// What previews of the bar show behind it: the Mac's wallpaper when StableBar can read it without a privacy prompt,
/// otherwise StableBar's own. Offscreen, it shows the scene's wallpaper or StableBar's own,
/// never the Mac's wallpaper.
struct SampleWallpaper: View {
    @Environment(\.offscreenSnapshot) private var offscreen
    @Environment(\.sceneWallpaper) private var sceneWallpaper
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        Group {
            if let image = offscreen ? sceneWallpaper ?? OffscreenSnapshot.wallpaper : DesktopWallpaper.shared.image {
                Color.clear.overlay(alignment: .top) { Image(nsImage: image).resizable().scaledToFill() }.clipped()
            } else {
                Color(white: dark ? 0.16 : 0.9)
            }
        }
        // Clipping the scaled image only limits its drawing, not its hit area.
        .allowsHitTesting(false)
    }
}

/// StableBar's own wallpaper, where it can't read the Mac's and in offscreen drawings: Walton Lighthouse by Paulius
/// Dragunas on Unsplash, blurred.
let bundledWallpaperURL = Bundle.main.url(forResource: "SetupWallpaper", withExtension: "jpg")

/// The main screen's wallpaper, or StableBar's own, read once, off the main thread, at a size that many previews draw
/// quickly.
@MainActor @Observable private final class DesktopWallpaper {
    static let shared = DesktopWallpaper()
    private(set) var image: NSImage?

    private init() {
        let url = NSScreen.screens.first.flatMap(NSWorkspace.shared.readableDesktopImageURL(for:))
        Task {
            image = await Self.thumbnail(url)
            if image == nil { image = await Self.thumbnail(bundledWallpaperURL) }
        }
    }

    private static func thumbnail(_ url: URL?) async -> NSImage? {
        guard let url else { return nil }
        let thumbnail = await Task.detached(priority: .utility) { () -> CGImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            return CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                   kCGImageSourceCreateThumbnailWithTransform: true,
                                                                   kCGImageSourceThumbnailMaxPixelSize: 1200] as CFDictionary)
        }.value
        return thumbnail.map { NSImage(cgImage: $0, size: .zero) }
    }
}

extension NSWorkspace {
    /// `screen`'s wallpaper, when StableBar can read it without a privacy prompt.
    func readableDesktopImageURL(for screen: NSScreen) -> URL? {
        desktopImageURL(for: screen).flatMap { wallpaperReadsWithoutPrompt($0, home: FileManager.default.homeDirectoryForCurrentUser) ? $0 : nil }
    }
}

/// Whether macOS lets StableBar read the picture at `url` without asking: Apple's wallpapers in /System or /Library, or
/// one in ~/Pictures outside a Photos library. Desktop, Documents, Downloads, iCloud Drive, other apps' data and other
/// volumes can show a privacy prompt. /System/Volumes/Data holds the home folder too.
func wallpaperReadsWithoutPrompt(_ url: URL, home: URL) -> Bool {
    let path = url.resolvingSymlinksInPath().standardizedFileURL.path
    // A Pictures folder that links elsewhere, such as to Desktop, leads where macOS can ask.
    let pictures = home.resolvingSymlinksInPath().appending(path: "Pictures").standardizedFileURL.path + "/"
    guard (path.hasPrefix("/System/") && !path.hasPrefix("/System/Volumes/Data/")) || path.hasPrefix("/Library/") || path.hasPrefix(pictures)
    else { return false }
    return !path.split(separator: "/").contains { $0.hasSuffix(".photoslibrary") }
}

extension EnvironmentValues {
    /// The wallpaper a scene gives the previews of the bar it draws.
    @Entry var sceneWallpaper: NSImage?
}

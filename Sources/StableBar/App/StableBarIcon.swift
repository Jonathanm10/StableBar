import AppKit

/// StableBar's own icon, for every view that draws it.
@MainActor
enum StableBarIcon {
    /// The bundle's `AppIcon.icns`, or the icon macOS looks up when StableBar runs without a bundle. macOS's lookup can
    /// pick other artwork in two copies of the same app, which changes the screens CI draws from each.
    static let image: NSImage = artwork(in: .main) ?? NSApplication.shared.applicationIconImage

    /// The file's 512-pixel bitmap, the smallest at least that large, as 256 points. It's taken from the file rather
    /// than through AppKit, whose choice of size depends on the screen and the macOS version.
    static func artwork(in bundle: Bundle) -> NSImage? {
        guard let url = bundle.url(forResource: "AppIcon", withExtension: "icns"), let image = NSImage(contentsOf: url) else { return nil }
        let bitmaps = image.representations.compactMap { $0 as? NSBitmapImageRep }
        let bitmap = bitmaps.filter { $0.pixelsWide >= 512 }.min { $0.pixelsWide < $1.pixelsWide }
            ?? bitmaps.max { $0.pixelsWide < $1.pixelsWide }
        return bitmap?.cgImage.map { NSImage(cgImage: $0, size: NSSize(width: 256, height: 256)) }
    }
}

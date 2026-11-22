import AppKit

/// StableBar's own icon, for every view that draws it.
@MainActor
enum StableBarIcon {
    /// The bundle's `AppIcon.icns`, or the icon macOS looks up when StableBar runs without a bundle. macOS's lookup can
    /// pick other artwork in two copies of the same app, which changes the screens CI draws from each.
    static let image: NSImage = artwork(in: .main) ?? NSApplication.shared.applicationIconImage

    /// The file's 512-pixel bitmap, the smallest at least that large, as a 256-point image's only representation.
    /// AppKit's own choice of size, and an image made from a `CGImage`, follow the screen and the macOS version.
    static func artwork(in bundle: Bundle) -> NSImage? {
        guard let url = bundle.url(forResource: "AppIcon", withExtension: "icns"), let file = NSImage(contentsOf: url) else { return nil }
        let bitmaps = file.representations.compactMap { $0 as? NSBitmapImageRep }
        guard let bitmap = bitmaps.filter({ $0.pixelsWide >= 512 }).min(by: { $0.pixelsWide < $1.pixelsWide })
            ?? bitmaps.max(by: { $0.pixelsWide < $1.pixelsWide }) else { return nil }
        bitmap.size = NSSize(width: 256, height: 256)
        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        return image
    }
}

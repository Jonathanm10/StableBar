import AppKit

/// StableBar's own icon, for every view that draws it.
@MainActor
enum StableBarIcon {
    /// The bundle's `AppIcon.icns`, or the icon macOS looks up when StableBar runs without a bundle. macOS's lookup can
    /// pick other artwork in two copies of the same app, which changes the screens CI draws from each.
    static let image: NSImage = artwork(in: .main) ?? NSApplication.shared.applicationIconImage

    /// The icon's 256-point artwork at 2x. One fixed bitmap, so AppKit can't choose another of the file's sizes by the
    /// screen or when a view scales it.
    static func artwork(in bundle: Bundle) -> NSImage? {
        guard let url = bundle.url(forResource: "AppIcon", withExtension: "icns"), let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 256, height: 256)
        var rect = NSRect(origin: .zero, size: image.size)
        let scale = NSAffineTransform()
        scale.scale(by: 2)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: [.ctm: scale]).map { NSImage(cgImage: $0, size: rect.size) }
    }
}

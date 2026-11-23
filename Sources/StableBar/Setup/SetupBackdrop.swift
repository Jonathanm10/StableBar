import AppKit
import CoreImage

/// Setup's full-screen backdrop: the Mac's wallpaper or a scene's, or StableBar's own where it has neither, at the
/// screen's size, and a blurred copy the tour crossfades to. Both are made once, off the main thread: Core Animation
/// draws a live blur of a layer this large from a small copy of it, in coarse blocks of flat color.
@MainActor @Observable final class SetupBackdrop {
    struct Images: Sendable {
        let sharp: CGImage
        let soft: CGImage
        /// Whether they show StableBar's own wallpaper.
        let bundled: Bool
    }

    enum Wallpaper: Sendable {
        case file(URL)
        case image(CGImage)
    }

    private(set) var images: Images?

    /// Makes the images for a screen `pixels` large, with StableBar's own wallpaper when `wallpaper` is nil or can't be
    /// read, and a flat color in dark or light where the app's resources aren't bundled.
    func load(_ wallpaper: Wallpaper?, pixels: CGSize, dark: Bool) async {
        let images = await Task.detached(priority: .userInitiated) {
            let given = wallpaper.flatMap { Self.filling(pixels, with: $0) }
            let ours = given == nil ? bundledWallpaperURL.flatMap { Self.filling(pixels, with: .file($0)) } : nil
            let sharp = given ?? ours ?? Self.flat(dark: dark)
            return Images(sharp: sharp, soft: Self.blurred(sharp) ?? sharp, bundled: ours != nil)
        }.value
        // A load for the Mac's earlier appearance, cancelled by a newer one, leaves the newer one's images.
        guard !Task.isCancelled else { return }
        self.images = images
    }

    /// The middle of `wallpaper`, cut to the screen's shape and read no larger than it fills the screen, as macOS's Fill
    /// Screen shows it.
    nonisolated private static func filling(_ pixels: CGSize, with wallpaper: Wallpaper) -> CGImage? {
        let image: CGImage
        switch wallpaper {
        case .image(let scene):
            image = scene
        case .file(let url):
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Double, let height = properties[kCGImagePropertyPixelHeight] as? Double,
                  let read = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: (max(width, height) * min(1, max(pixels.width / width, pixels.height / height))).rounded(.up)
                  ] as CFDictionary)
            else { return nil }
            image = read
        }
        let size = CGSize(width: image.width, height: image.height)
        let fill = max(pixels.width / size.width, pixels.height / size.height)
        let cut = CGSize(width: pixels.width / fill, height: pixels.height / fill)
        return image.cropping(to: CGRect(x: ((size.width - cut.width) / 2).rounded(), y: ((size.height - cut.height) / 2).rounded(),
                                         width: cut.width.rounded(), height: cut.height.rounded()))
    }

    /// A flat gray where the app's resources aren't bundled, as in tests.
    nonisolated private static func flat(dark: Bool) -> CGImage {
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                                bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        context.setFillColor(gray: dark ? 0.16 : 0.9, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        return context.makeImage()!
    }

    /// Blurred and a little richer at an eighth of the size, which the tour scales back up: a blur this wide hides the
    /// difference.
    nonisolated private static func blurred(_ image: CGImage) -> CGImage? {
        let small = CIImage(cgImage: image).transformed(by: CGAffineTransform(scaleX: 0.125, y: 0.125))
        let blurred = small.clampedToExtent().applyingGaussianBlur(sigma: 12)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.2])
            .cropped(to: small.extent)
        return CIContext().createCGImage(blurred, from: small.extent, format: .RGBAh, colorSpace: CGColorSpace(name: CGColorSpace.displayP3))
    }
}

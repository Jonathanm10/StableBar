import AppKit
import Foundation
import Testing
@testable import StableBar

private let bundledIcon = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().appending(path: "Resources/AppIcon.icns")

/// An app named `name` in `directory`, with StableBar's icon when `icon` is true, like the bundles CI draws screens from.
private func app(_ name: String, in directory: URL, icon: Bool = true) throws -> Bundle {
    let app = directory.appending(path: name)
    let resources = app.appending(path: "Contents/Resources")
    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
    try PropertyListSerialization.data(fromPropertyList: ["CFBundlePackageType": "APPL", "CFBundleIconFile": "AppIcon"],
                                       format: .xml, options: 0)
        .write(to: app.appending(path: "Contents/Info.plist"))
    if icon { try FileManager.default.copyItem(at: bundledIcon, to: resources.appending(path: "AppIcon.icns")) }
    return try #require(Bundle(url: app))
}

/// One fixed size of the artwork, whatever the screen, so AppKit can't pick another when a view scales it, and two
/// copies of the app draw the same pixels.
@Test @MainActor func stableBarIconDrawsOneSizeOfItsArtwork() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let base = try #require(StableBarIcon.artwork(in: try app("base.app", in: directory)))
    let head = try #require(StableBarIcon.artwork(in: try app("head.app", in: directory)))
    #expect(base.size == NSSize(width: 256, height: 256))
    #expect(base.representations.map(\.pixelsWide) == [512])
    #expect(base.tiffRepresentation == head.tiffRepresentation)
}

@Test @MainActor func anAppWithoutTheIconHasNoArtwork() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    #expect(StableBarIcon.artwork(in: try app("Plain.app", in: directory, icon: false)) == nil)
}

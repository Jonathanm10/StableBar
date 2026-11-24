import Foundation

/// A theme's own look over Built-in, with no user configuration or running bar state.
struct ThemePreview: Sendable {
    let light: Configuration
    let dark: Configuration
    /// The theme's tokens in each appearance, which widgets drawn in its look can name.
    private let lightTokens: [String: ConfigurationValue]
    private let darkTokens: [String: ConfigurationValue]

    init(choice: ThemeChoice, themesDirectory: URL?) throws {
        var loader = ConfigurationLoader()
        var layer = ConfigurationLayer(values: ["widgets": .array([])], origins: [:])
        if let themesDirectory {
            let directory = themesDirectory.appending(path: "built-in")
            let manifest = try WidgetPackageStore(directory: themesDirectory).manifest(at: directory)
            try layer.merge(loader.readPackage(at: directory, manifest: manifest, settings: [:]))
        }
        if !choice.isBuiltIn || themesDirectory == nil {
            try layer.merge(loader.readPackage(at: choice.directory, manifest: choice.manifest, settings: [:]))
        }
        func drawn(_ appearance: String) throws -> (Configuration, [String: ConfigurationValue]) {
            let context = ConfigurationContext(appearance: appearance, theme: choice.manifest.id)
            let document = try loader.finish(layer, context: context)
            return (try ConfigurationValue.object(document).decoded(Configuration.self),
                    try document["tokens"]?.decoded([String: ConfigurationValue].self) ?? [:])
        }
        (light, lightTokens) = try drawn("light")
        (dark, darkTokens) = try drawn("dark")
    }

    func configuration(for appearance: BarAppearance) -> Configuration {
        appearance == .dark ? dark : light
    }

    func tokens(for appearance: BarAppearance) -> [String: ConfigurationValue] {
        appearance == .dark ? darkTokens : lightTokens
    }
}

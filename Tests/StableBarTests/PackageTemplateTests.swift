import Foundation
import Testing
@testable import StableBar

@Test func packagesThatShareATemplateNameKeepTheirOwnTemplates() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = WidgetPackageStore(directory: directory.appending(path: "packages"))
    for (id, text) in [("player", "Player"), ("other", "Other")] {
        let source = directory.appending(path: "sources/\(id)")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data(#"{"id":"\#(id)","name":"\#(id)","version":"1","kind":"widgets","entry":"config.json"}"#.utf8)
            .write(to: source.appending(path: "package.json"))
        try Data(#"""
        {"templates":{"Player":{"type":"text","position":"right","text":"x","tooltip":"\#(text)","style":{"paddingHorizontal":4}},
                      "Chained":{"template":"Player"}},
         "widgets":[{"id":"\#(id)","template":"Chained"}]}
        """#.utf8).write(to: source.appending(path: "config.json"))
        _ = try store.install(source)
    }
    let root = directory.appending(path: "config.json")
    var loader = ConfigurationLoader()
    let configuration = try loader.load(root, data: Data(#"""
    {"packages":[{"id":"player","version":"1"},{"id":"other","version":"1"}],
     "templates":{"Player":{"style":{"fontSize":15}},"Chained":{"template":"Player"}},
     "widgets":[{"id":"mine","template":"Player","text":"Mine","tooltip":"Mine","position":"left"},
                {"id":"chained","template":"Chained"}]}
    """#.utf8))
    func widget(_ id: String) throws -> WidgetConfiguration {
        try #require(configuration.widgets.first { $0.id == id })
    }
    #expect(try widget("player").tooltip == "Player")
    #expect(try widget("other").tooltip == "Other")
    #expect(try widget("player").style.fontSize == 15)
    #expect(try widget("player").style.paddingHorizontal == 4)
    #expect(try widget("mine").style.fontSize == 15)
    // Your own widgets still get every package's template of a name, the later package winning.
    #expect(try widget("chained").tooltip == "Other")
    #expect(loader.origins["widgets.player.tooltip"]?.file.hasSuffix("packages/player/1/config.json") == true)
    #expect(loader.origins["widgets.player.style.fontSize"]?.file == root.path)
}

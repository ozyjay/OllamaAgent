import Foundation

enum Fixtures {
    static func data(_ name: String) -> Data {
        let bundle = Bundle(for: BundleToken.self)
        let url = bundle.url(forResource: name, withExtension: "json")!
        return try! Data(contentsOf: url)
    }
}

private final class BundleToken {}

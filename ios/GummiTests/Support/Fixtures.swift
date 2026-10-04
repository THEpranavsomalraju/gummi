import Foundation
@testable import Gummi

nonisolated private final class FixtureBundleToken {}

nonisolated enum Fixtures {
    static let bundle = Bundle(for: FixtureBundleToken.self)

    static func data(_ name: String, ext: String = "json") throws -> Data {
        guard let url = bundle.url(forResource: name, withExtension: ext) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "\(name).\(ext)"])
        }
        return try Data(contentsOf: url)
    }

    static func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try JSONCoding.decoder().decode(type, from: data(name))
    }
}

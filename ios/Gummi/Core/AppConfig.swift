import Foundation

/// Backend settings injected at build time from Config/Gummi.xcconfig and Secrets.xcconfig.local.
nonisolated struct AppConfig: Sendable {
    let apiBaseURL: URL
    let tokenURL: URL
    let clientID: String
    let clientSecret: String
    let userID: String

    enum LoadError: Error, CustomStringConvertible {
        case missing([String])

        var description: String {
            switch self {
            case .missing(let keys): "Not configured: \(keys.joined(separator: ", ")). Fill in Config/Secrets.xcconfig.local."
            }
        }
    }

    static func load(from bundle: Bundle = .main) throws -> AppConfig {
        func value(_ key: String) -> String {
            (bundle.object(forInfoDictionaryKey: key) as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        let keys = ["GummiAPIBaseURL", "GummiTokenURL", "GummiClientID", "GummiClientSecret", "GummiUserID"]
        let values = Dictionary(uniqueKeysWithValues: keys.map { ($0, value($0)) })
        var missing = keys.filter { values[$0]!.isEmpty }
        let apiBaseURL = URL(string: values["GummiAPIBaseURL"]!)
        let tokenURL = URL(string: values["GummiTokenURL"]!)
        if apiBaseURL == nil, !missing.contains("GummiAPIBaseURL") { missing.append("GummiAPIBaseURL") }
        if tokenURL == nil, !missing.contains("GummiTokenURL") { missing.append("GummiTokenURL") }
        guard missing.isEmpty, let apiBaseURL, let tokenURL else { throw LoadError.missing(missing) }
        return AppConfig(
            apiBaseURL: apiBaseURL,
            tokenURL: tokenURL,
            clientID: values["GummiClientID"]!,
            clientSecret: values["GummiClientSecret"]!,
            userID: values["GummiUserID"]!
        )
    }
}

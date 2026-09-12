import Foundation

public struct Identifier: Hashable, Sendable, Codable {
    public var raw: String
    public var normalized: String
    public var quoted: Bool
    public var schema: String?

    public init(raw: String, normalized: String? = nil, quoted: Bool = false, schema: String? = nil) {
        self.raw = raw
        self.normalized = normalized ?? Identifier.defaultNormalize(raw, quoted: quoted)
        self.quoted = quoted
        self.schema = schema
    }

    public static func defaultNormalize(_ raw: String, quoted: Bool) -> String {
        quoted ? raw : raw.lowercased()
    }

    public var qualified: String {
        if let schema { return "\(schema).\(raw)" }
        return raw
    }
}

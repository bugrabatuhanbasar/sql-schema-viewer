import Foundation

public indirect enum DataType: Hashable, Sendable, Codable {
    case named(String, params: [String])
    case array(DataType, dimensions: Int)
    case userDefined(Identifier)
    case unknown(String)

    public var displayName: String {
        switch self {
        case .named(let name, let params):
            return params.isEmpty ? name : "\(name)(\(params.joined(separator: ",")))"
        case .array(let inner, let dims):
            return inner.displayName + String(repeating: "[]", count: dims)
        case .userDefined(let ident):
            return ident.qualified
        case .unknown(let raw):
            return raw
        }
    }

    public var isTextLike: Bool {
        guard case .named(let n, _) = self else { return false }
        let lower = n.lowercased()
        return ["text", "varchar", "char", "citext", "nvarchar", "nchar", "clob"].contains(where: { lower.contains($0) })
    }

    public var isIntegerLike: Bool {
        guard case .named(let n, _) = self else { return false }
        let lower = n.lowercased()
        return ["int", "smallint", "bigint", "tinyint", "mediumint", "integer", "serial", "bigserial", "smallserial"].contains(where: { lower.contains($0) })
    }

    /// Best-effort compatibility used by the "foreign-key columns with
    /// incompatible types" quality check. Conservative: returns true when
    /// unsure.
    public func isCompatible(with other: DataType) -> Bool {
        switch (self, other) {
        case (.unknown, _), (_, .unknown):
            return true
        case (.named(let a, _), .named(let b, _)):
            let la = a.lowercased(), lb = b.lowercased()
            if la == lb { return true }
            if isIntegerLike && other.isIntegerLike { return true }
            if isTextLike && other.isTextLike { return true }
            return false
        default:
            return self == other
        }
    }
}

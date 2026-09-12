import Foundation

public enum Dialect: String, Sendable, CaseIterable, Codable {
    case postgres
    case mysql
    case mariadb
    case sqlite
    case oracle
    case dbml
    case unknown

    public var displayName: String {
        switch self {
        case .postgres: return "PostgreSQL"
        case .mysql: return "MySQL"
        case .mariadb: return "MariaDB"
        case .sqlite: return "SQLite"
        case .oracle: return "Oracle"
        case .dbml: return "DBML"
        case .unknown: return "Unknown"
        }
    }
}

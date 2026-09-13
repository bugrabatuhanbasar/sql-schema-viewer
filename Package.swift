// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacSQLSchemaViewer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "SchemaKit", targets: ["SchemaKit"]),
        .library(name: "AppUI", targets: ["AppUI"]),
        .executable(name: "schema-viewer", targets: ["SchemaViewerCLI"]),
    ],
    dependencies: [
        // No third-party runtime dependencies in M1.
        // swift-argument-parser will be added when the CLI is fleshed out (M11).
    ],
    targets: [
        // MARK: Foundations
        .target(name: "SchemaModel"),
        .target(name: "SQLLexer", dependencies: ["SchemaModel"]),
        .target(name: "ParserCore", dependencies: ["SchemaModel", "SQLLexer"]),

        // MARK: Per-dialect parsers (stubs until their milestones)
        .target(name: "PostgresParser", dependencies: ["SchemaModel", "SQLLexer", "ParserCore"]),
        .target(name: "MySQLParser", dependencies: ["SchemaModel", "SQLLexer", "ParserCore"]),
        .target(name: "SQLiteParser", dependencies: ["SchemaModel", "SQLLexer", "ParserCore"]),
        .target(name: "OracleParser", dependencies: ["SchemaModel", "SQLLexer", "ParserCore"]),
        .target(name: "DBMLParser", dependencies: ["SchemaModel", "ParserCore"]),

        // MARK: Analysis
        .target(name: "DialectDetector", dependencies: ["SchemaModel"]),
        .target(name: "DependencyAnalyzer", dependencies: ["SchemaModel", "SQLLexer"]),
        .target(name: "QualityChecks", dependencies: ["SchemaModel"]),

        // MARK: Rendering
        .target(name: "LayoutEngine", dependencies: ["SchemaModel"]),
        .target(name: "DiagramRenderer", dependencies: ["SchemaModel", "LayoutEngine"]),
        .target(name: "MermaidExporter", dependencies: ["SchemaModel"]),

        // MARK: Facade + UI + CLI
        .target(
            name: "SchemaKit",
            dependencies: [
                "SchemaModel",
                "ParserCore",
                "PostgresParser",
                "MySQLParser",
                "SQLiteParser",
                "OracleParser",
                "DBMLParser",
                "DialectDetector",
                "DependencyAnalyzer",
                "QualityChecks",
                "LayoutEngine",
                "DiagramRenderer",
                "MermaidExporter",
            ]
        ),
        .target(name: "AppUI", dependencies: ["SchemaKit"]),
        .executableTarget(name: "SchemaViewerCLI", dependencies: ["SchemaKit"]),

        // MARK: Tests
        .testTarget(name: "SchemaModelTests", dependencies: ["SchemaModel"]),
        .testTarget(name: "SQLLexerTests", dependencies: ["SQLLexer", "SchemaModel"]),
        .testTarget(name: "ParserCoreTests", dependencies: ["ParserCore", "SchemaModel", "SQLLexer"]),
        .testTarget(name: "PostgresParserTests", dependencies: ["PostgresParser", "SchemaModel"]),
        .testTarget(name: "MySQLParserTests", dependencies: ["MySQLParser", "SchemaModel"]),
        .testTarget(name: "SQLiteParserTests", dependencies: ["SQLiteParser", "SchemaModel"]),
        .testTarget(name: "OracleParserTests", dependencies: ["OracleParser", "SchemaModel"]),
        .testTarget(name: "DBMLParserTests", dependencies: ["DBMLParser", "SchemaModel"]),
        .testTarget(name: "DependencyAnalyzerTests", dependencies: ["DependencyAnalyzer", "SchemaModel"]),
        .testTarget(name: "DialectDetectorTests", dependencies: ["DialectDetector", "SchemaModel"]),
        .testTarget(name: "LayoutEngineTests", dependencies: ["LayoutEngine", "SchemaModel"]),
        .testTarget(name: "NetworkGuardTests", dependencies: ["SchemaKit"]),
    ]
)

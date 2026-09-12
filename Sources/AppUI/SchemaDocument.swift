import Foundation
import SchemaKit

#if canImport(SwiftUI)
import SwiftUI
import UniformTypeIdentifiers

public enum SchemaFileType {
    public static let sql = UTType(filenameExtension: "sql") ?? .plainText
    public static let ddl = UTType(filenameExtension: "ddl") ?? .plainText
    public static let dbml = UTType(filenameExtension: "dbml") ?? .plainText

    public static var readableTypes: [UTType] {
        [sql, ddl, dbml, .plainText]
    }
}

/// Document backing the schema viewer. Reads a source file, runs analysis
/// on demand, and exposes the resulting `Schema` to the UI. Documents are
/// read-only from the app's perspective — we never write back to the user's
/// source file.
public final class SchemaDocument: ReferenceFileDocument {
    public typealias Snapshot = String

    public static var readableContentTypes: [UTType] { SchemaFileType.readableTypes }
    public static var writableContentTypes: [UTType] { [] }

    @Published public var sourceText: String
    @Published public var fileURL: URL?
    @Published public var dialectOverride: Dialect?
    @Published public private(set) var schema: Schema = Schema()
    @Published public private(set) var diagnostics: [Diagnostic] = []

    public init() {
        self.sourceText = ""
        self.fileURL = nil
    }

    public required init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        self.sourceText = String(decoding: data, as: UTF8.self)
        self.fileURL = nil
        analyze()
    }

    public func snapshot(contentType: UTType) throws -> String { sourceText }

    public func fileWrapper(snapshot: String, configuration: WriteConfiguration) throws -> FileWrapper {
        // App is read-only; writable content types is empty so this never
        // fires, but conforming to the protocol requires an implementation.
        FileWrapper(regularFileWithContents: Data(snapshot.utf8))
    }

    public func analyze() {
        let result = SchemaKit.analyze(
            contents: sourceText,
            file: fileURL,
            dialectOverride: dialectOverride
        )
        self.schema = result.value
        self.diagnostics = result.value.diagnostics
    }
}
#endif

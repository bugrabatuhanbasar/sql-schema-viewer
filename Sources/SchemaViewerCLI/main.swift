import Foundation
import SchemaKit

// Minimal M1 CLI. Full subcommands (inspect / check / render / export) with
// swift-argument-parser arrive in M11.

let args = CommandLine.arguments
if args.count < 2 || args.contains("--help") || args.contains("-h") {
    let usage = """
    schema-viewer (M1 preview)

    Usage:
      schema-viewer inspect <path>   Print an analysis summary for a SQL/DBML file.
      schema-viewer version          Print version.

    Full CLI arrives in milestone M11.
    """
    print(usage)
    exit(args.count < 2 ? 64 : 0)
}

switch args[1] {
case "version":
    print("schema-viewer 0.1.0-m1")
case "inspect":
    guard args.count >= 3 else {
        FileHandle.standardError.write(Data("error: inspect requires a file path\n".utf8))
        exit(64)
    }
    let url = URL(fileURLWithPath: args[2])
    do {
        let result = try SchemaKit.analyzeFile(at: url)
        print(result.value.summarySentence)
        let errors = result.diagnostics.filter { $0.severity == .error }.count
        exit(errors == 0 ? 0 : 1)
    } catch {
        FileHandle.standardError.write(Data("error: \(error)\n".utf8))
        exit(74)
    }
default:
    FileHandle.standardError.write(Data("error: unknown subcommand '\(args[1])'\n".utf8))
    exit(64)
}

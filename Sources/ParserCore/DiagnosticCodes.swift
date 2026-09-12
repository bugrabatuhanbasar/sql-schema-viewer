import Foundation

/// Stable diagnostic codes. The prefix encodes the severity by convention
/// (`E` error, `W` warning, `I` info), but severity is authoritative in the
/// `Diagnostic` value itself.
public enum DiagnosticCode {
    public static let unterminatedStatement = "E0001"
    public static let unexpectedToken       = "E0002"
    public static let unsupportedFeature    = "I0001"
    public static let skippedStatement      = "I0002"
    public static let partialParse          = "W0001"
    public static let missingPrimaryKey     = "W0010"
    public static let incompatibleFKTypes   = "W0011"
    public static let unindexedFKColumn     = "W0012"
    public static let suspectedFK           = "W0013"
    public static let duplicateName         = "W0014"
    public static let orphanTable           = "W0015"
    public static let danglingReference     = "W0016"
    public static let circularDependency    = "W0017"
    public static let dbmlLossyExport       = "I0100"
}

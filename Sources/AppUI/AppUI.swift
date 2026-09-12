import Foundation
import SchemaKit

#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import AppKit

/// M1 placeholder view. The full three-pane document window (list, diagram,
/// details + diagnostics) is built in M2.
public struct SchemaViewerRootView: SwiftUI.View {
    public init() {}
    public var body: some SwiftUI.View {
        VStack(spacing: 12) {
            Text("Mac SQL Schema Viewer")
                .font(.title2).bold()
            Text("Milestone M1 shell. Drop a .sql, .ddl, or .dbml file into a document window (M2).")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
        }
        .frame(minWidth: 480, minHeight: 320)
    }
}
#endif

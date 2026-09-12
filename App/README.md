# Xcode App Setup

The core library, parser engine, and CLI live in the SPM package at the repo
root. The macOS document-based app is a thin Xcode wrapper that consumes
that package.

## One-time project creation

1. Open Xcode → **File → New → Project…**
2. Choose **macOS → App**. Click Next.
3. Fill in:
   - **Product Name:** `Mac SQL Schema Viewer`
   - **Team:** your signing team
   - **Organization Identifier:** `org.macsqlschemaviewer`
     (final bundle id: `org.macsqlschemaviewer.MacSQLSchemaViewer`)
   - **Interface:** SwiftUI
   - **Language:** Swift
   - **Storage:** None
   - Uncheck Testing / Core Data / CloudKit — this app has none of that.
4. Save the project into `App/` in this repo (uncheck "Create Git repository";
   the repo already exists at the top level).
5. **Signing & Capabilities**
   - Turn on **App Sandbox**
   - Under App Sandbox → File Access, set **User Selected File** to
     **Read/Write**
   - Do **not** enable Outgoing / Incoming Network Connections. Do not add
     any other capability.
   - Replace the generated `.entitlements` with
     `App/Source/MacSQLSchemaViewer.entitlements` (or match its contents).
6. **Deployment target:** macOS 13.0
7. **Frameworks & Libraries → Add Package Dependency → Add Local…** and pick
   the repo root (the folder containing `Package.swift`). Add the `AppUI`
   product to the app target.
8. Replace the auto-generated `@main` app file with the contents of
   `App/Source/MacSQLSchemaViewerApp.swift`.
9. Replace the auto-generated `Info.plist` with `App/Source/Info.plist` (or
   copy over the `CFBundleDocumentTypes` and `UTExportedTypeDeclarations`
   entries and the display name / bundle id).
10. Build and run. `File → Open…` a `.sql` / `.ddl` / `.dbml` file.

The reason the `.xcodeproj` is not checked in yet: Xcode 26 rewrites the
pbxproj file aggressively on first save, and a hand-maintained project file
would drift on every commit. Once one contributor has run the steps above,
they can commit the resulting `MacSQLSchemaViewer.xcodeproj` and future
contributors just open it.

## What the app links

- SPM product `AppUI` (which re-exports `SchemaKit`)
- Nothing else. No third-party runtime dependencies.

## Verifying "no network" after build

From the built `.app`:

```
codesign -d --entitlements - MacSQLSchemaViewer.app | grep -Ei 'network|internet'
```

Should print nothing. Also:

```
nm MacSQLSchemaViewer.app/Contents/MacOS/MacSQLSchemaViewer | grep -E 'URLSession|nw_connection|SCNetworkReachability'
```

Should print nothing from first-party code.

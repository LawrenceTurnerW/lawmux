import CmuxSettings
import Foundation

/// lawmux: `app.defaultWorkspacePath` (Settings → App → Default Workspace Path)
/// also decides where a new workspace starts when it does not inherit a
/// directory. Upstream reads that setting only to seed the Open Folder panel.
///
/// Resolution reuses upstream's `OpenFolderPanelStartDirectory`, so the same
/// rules apply: a leading `~` is expanded, and the value is used only when it
/// names an existing folder. Otherwise this returns nil and the caller falls
/// back to upstream behaviour (Ghostty's `working-directory`, else home).
enum LawmuxDefaultWorkspacePath {
    static func resolvedDirectory(defaults: UserDefaults = .standard) -> String? {
        let configured = AppCatalogSection().defaultWorkspacePath.value(in: defaults)
        guard !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return OpenFolderPanelStartDirectory()
            .resolve(configuredPath: configured, workspaceDirectory: nil)?
            .path
    }
}

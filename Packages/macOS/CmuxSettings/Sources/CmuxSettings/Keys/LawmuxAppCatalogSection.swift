import Foundation

/// lawmux: settings that exist only in the fork.
///
/// They extend upstream's `AppCatalogSection` as computed keys, so no upstream
/// file changes and `SettingCatalogSection.all` (which reflects stored
/// properties) keeps listing only upstream keys. These keys therefore stay out
/// of the generated cmux.json schema and `cmux config`; they live in
/// UserDefaults and are edited on the Settings → lawmux page.
extension AppCatalogSection {
    /// Shell command typed into a plain new terminal workspace (Cmd+N, the
    /// plus button, File → New Workspace) once its shell is ready, followed by
    /// Return. Empty, the default, types nothing.
    public var lawmuxNewWorkspaceCommand: DefaultsKey<String> {
        DefaultsKey<String>(
            id: "lawmux.newWorkspaceCommand",
            defaultValue: "",
            userDefaultsKey: "lawmux.newWorkspaceCommand"
        )
    }
}

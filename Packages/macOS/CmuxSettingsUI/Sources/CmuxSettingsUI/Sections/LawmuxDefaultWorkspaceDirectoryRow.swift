import AppKit
import CmuxSettings
import SwiftUI

/// lawmux: the `app.defaultWorkspacePath` row on the lawmux settings page.
///
/// Upstream has no UI for this key (it is set through cmux.json only) and
/// uses it just to seed the Open Folder panel. In lawmux the same key also
/// decides where a new workspace starts, so it gets a row with a text field
/// and a folder picker.
///
/// The strings are lawmux-only and intentionally absent from the shared
/// string catalog; `LawmuxText` shows Japanese in a Japanese app and
/// English everywhere else.
struct LawmuxDefaultWorkspaceDirectoryRow: View {
    let model: DefaultsValueModel<String>

    var body: some View {
        SettingsCardRow(
            configurationReview: .json("app.defaultWorkspacePath"),
            LawmuxText.string("Default Workspace Directory", ja: "デフォルトのワークスペースディレクトリ"),
            subtitle: LawmuxText.string(
                "New workspaces start here; the Open Folder dialog starts here too. Leave empty to use Ghostty's working-directory, or your home folder.",
                ja: "新規ワークスペースはここから始まります。「フォルダを開く」ダイアログの初期フォルダにもなります。空のままなら Ghostty の working-directory、それもなければホームフォルダを使います。"
            )
        ) {
            HStack(spacing: 6) {
                TextField(
                    LawmuxText.string("e.g. ~/Work", ja: "例: ~/Work"),
                    text: Binding(get: { model.current }, set: { model.set($0) })
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .accessibilityIdentifier("LawmuxDefaultWorkspaceDirectoryField")

                Button(LawmuxText.string("Choose…", ja: "選択…")) {
                    chooseDirectory()
                }
                .controlSize(.small)
                .accessibilityIdentifier("LawmuxDefaultWorkspaceDirectoryChooseButton")
            }
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = LawmuxText.string("Use", ja: "使用")
        if let current = OpenFolderPanelStartDirectory()
            .resolve(configuredPath: model.current, workspaceDirectory: nil) {
            panel.directoryURL = current
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Store the home-relative form so cmux.json stays portable between Macs.
        model.set((url.path as NSString).abbreviatingWithTildeInPath)
    }
}

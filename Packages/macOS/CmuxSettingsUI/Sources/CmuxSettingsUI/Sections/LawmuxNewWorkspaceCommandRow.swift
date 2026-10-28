import CmuxSettings
import SwiftUI

/// lawmux: the `lawmux.newWorkspaceCommand` row on the lawmux settings page.
///
/// The command is typed into every plain new terminal workspace (Cmd+N, the
/// plus button, File → New Workspace) once its shell is ready, followed by
/// Return. It is a per-Mac choice (one Mac runs `claude`, another `codex`),
/// so the default is empty and the value lives in UserDefaults only.
struct LawmuxNewWorkspaceCommandRow: View {
    let model: DefaultsValueModel<String>

    var body: some View {
        SettingsCardRow(
            configurationReview: .settingsOnly,
            searchAnchorID: "lawmux.newWorkspaceCommand",
            LawmuxText.string("New Workspace Command", ja: "新規ワークスペースで実行するコマンド"),
            subtitle: LawmuxText.string(
                "Typed into a new terminal workspace (Cmd+N, the plus button, File → New Workspace) and run once its shell is ready. Leave empty to start with a plain shell. Workspaces made by the CLI, layouts, or session restore are not affected.",
                ja: "新規ターミナルワークスペース（⌘N、＋ボタン、ファイル → 新規ワークスペース）のシェルが準備できたら打ち込んで実行します。空のままなら素のシェルで始まります。CLI、レイアウト、セッション復元で作られたワークスペースには影響しません。"
            )
        ) {
            TextField(
                LawmuxText.string("e.g. claude", ja: "例: claude"),
                text: Binding(get: { model.current }, set: { model.set($0) })
            )
            .textFieldStyle(.roundedBorder)
            .frame(width: 200)
            .accessibilityIdentifier("LawmuxNewWorkspaceCommandField")
        }
    }
}

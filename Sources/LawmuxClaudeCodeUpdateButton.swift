import CmuxSettingsUI
import SwiftUI

/// lawmux: the sidebar footer button for `LawmuxClaudeCodeUpdater`.
///
/// Hidden while Claude Code is current (or not a Homebrew install). It then
/// walks through: update available (click to upgrade) → upgrading (spinner)
/// → restart lawmux (enabled once no Claude session is mid-turn) → failed
/// (click to check again). Sits next to the Help button where upstream puts
/// the sign-in and Cloud buttons, which lawmux hides.
struct LawmuxClaudeCodeUpdateButton: View {
    @ObservedObject private var updater = LawmuxClaudeCodeUpdater.shared
    @Environment(\.cmuxAccentColor) private var accent
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.sidebarReadabilityBackdrop) private var readabilityBackdrop

    var body: some View {
        Group {
            switch updater.phase {
            case .hidden:
                EmptyView()
            case .available(let installed, let latest):
                button(
                    systemName: "arrow.down.circle",
                    tint: accent.color,
                    help: LawmuxText.string(
                        "Claude Code \(latest) is available (installed \(installed)). Click to run brew upgrade; running sessions keep working.",
                        ja: "Claude Code \(latest) があります（インストール済み: \(installed)）。クリックで brew upgrade を実行します。動作中のセッションはそのまま動きます。"
                    ),
                    identifier: "LawmuxClaudeCodeUpdateAvailable"
                ) { updater.upgrade() }
            case .upgrading(let latest):
                ProgressView()
                    .controlSize(.small)
                    .frame(
                        width: SidebarFooterButtonMetrics.buttonSize,
                        height: SidebarFooterButtonMetrics.buttonSize
                    )
                    .safeHelp(LawmuxText.string(
                        "Upgrading Claude Code to \(latest)…",
                        ja: "Claude Code を \(latest) に更新中…"
                    ))
                    .accessibilityIdentifier("LawmuxClaudeCodeUpgrading")
            case .upgraded(let latest):
                let busy = updater.busyClaudeCount
                button(
                    systemName: busy > 0 ? "clock.arrow.circlepath" : "arrow.clockwise.circle",
                    tint: busy > 0 ? secondary : accent.color,
                    help: busy > 0
                        ? LawmuxText.string(
                            "Claude Code \(latest) is installed. Restart lawmux once the \(busy) running Claude session(s) finish; the restart ends every process in every workspace and restores shells and Claude sessions.",
                            ja: "Claude Code \(latest) を入れました。処理中の Claude セッション（\(busy) 件）が終わったら lawmux を再起動できます。再起動は全ワークスペースのプロセスを終了し、シェルと Claude セッションだけ復元します。"
                        )
                        : LawmuxText.string(
                            "Claude Code \(latest) is installed and no Claude session is busy. Click to restart lawmux; shells and Claude sessions are restored, other processes are not.",
                            ja: "Claude Code \(latest) を入れました。処理中の Claude セッションはありません。クリックで lawmux を再起動します。シェルと Claude セッションは復元されますが、他のプロセスは戻りません。"
                        ),
                    identifier: busy > 0 ? "LawmuxClaudeCodeRestartWaiting" : "LawmuxClaudeCodeRestartReady",
                    isEnabled: busy == 0
                ) { updater.restart() }
            case .failed(let message):
                button(
                    systemName: "exclamationmark.triangle",
                    tint: secondary,
                    help: LawmuxText.string(
                        "Claude Code update failed: \(message). Click to check again. Log: \(LawmuxClaudeCodeUpdater.upgradeLogURL.path)",
                        ja: "Claude Code の更新に失敗しました: \(message)。クリックで再確認します。ログ: \(LawmuxClaudeCodeUpdater.upgradeLogURL.path)"
                    ),
                    identifier: "LawmuxClaudeCodeUpdateFailed"
                ) { updater.retry() }
            }
        }
    }

    private var secondary: Color {
        SidebarAppearanceColorResolver().readableSecondary(for: colorScheme, over: readabilityBackdrop)
    }

    private func button(
        systemName: String,
        tint: Color,
        help: String,
        identifier: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            CmuxSystemSymbolImage(
                systemName: systemName,
                pointSize: SidebarFooterButtonMetrics.helpIconSize,
                weight: SidebarFooterCircularIconStyle.standard.weight,
                tint: tint
            )
            .frame(
                width: SidebarFooterButtonMetrics.buttonSize,
                height: SidebarFooterButtonMetrics.buttonSize
            )
        }
        .buttonStyle(SidebarFooterIconButtonStyle())
        .disabled(!isEnabled)
        .frame(
            width: SidebarFooterButtonMetrics.buttonSize,
            height: SidebarFooterButtonMetrics.buttonSize
        )
        .safeHelp(help)
        .hintableAccessibilityLabel(help)
        .accessibilityIdentifier(identifier)
    }
}

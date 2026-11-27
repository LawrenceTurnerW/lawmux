import CmuxSettingsUI
import SwiftUI

/// lawmux: the sidebar footer button for `LawmuxScrcpyLauncher`. Hidden on a
/// Mac without scrcpy. Click starts scrcpy (USB device, no audio, stays
/// awake); while it runs the icon takes the accent color and a click
/// terminates it. Sits next to the Claude Code update button.
struct LawmuxScrcpyButton: View {
    @ObservedObject private var launcher = LawmuxScrcpyLauncher.shared
    @Environment(\.cmuxAccentColor) private var accent
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.sidebarReadabilityBackdrop) private var readabilityBackdrop

    var body: some View {
        if launcher.isAvailable {
            let running = launcher.isRunning
            let help = running
                ? LawmuxText.string(
                    "scrcpy is mirroring the USB Android device. Click to quit it.",
                    ja: "scrcpy で USB 接続の Android 端末を表示中。クリックで終了します。"
                )
                : LawmuxText.string(
                    "Mirror the USB Android device with scrcpy (stays awake, no audio, window title \"lawmux\").",
                    ja: "scrcpy で USB 接続の Android 端末の画面を表示します（スリープ抑止、音声なし、ウィンドウ名 \"lawmux\"）。"
                )
            Button {
                launcher.toggle()
            } label: {
                CmuxSystemSymbolImage(
                    systemName: "smartphone",
                    pointSize: SidebarFooterButtonMetrics.helpIconSize,
                    weight: SidebarFooterCircularIconStyle.standard.weight,
                    tint: running ? accent.color : secondary
                )
                .frame(
                    width: SidebarFooterButtonMetrics.buttonSize,
                    height: SidebarFooterButtonMetrics.buttonSize
                )
            }
            .buttonStyle(SidebarFooterIconButtonStyle())
            .frame(
                width: SidebarFooterButtonMetrics.buttonSize,
                height: SidebarFooterButtonMetrics.buttonSize
            )
            .safeHelp(help)
            .hintableAccessibilityLabel(help)
            .accessibilityIdentifier(running ? "LawmuxScrcpyRunning" : "LawmuxScrcpyLaunch")
        }
    }

    private var secondary: Color {
        SidebarAppearanceColorResolver().readableSecondary(for: colorScheme, over: readabilityBackdrop)
    }
}

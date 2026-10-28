import CmuxSettings
import CmuxWorkspaces
import Foundation

/// lawmux: types the configured `lawmux.newWorkspaceCommand` into a plain new
/// terminal workspace once its shell is ready, then presses Return.
///
/// Delivery reuses the welcome banner's typed path (`sendTextWhenReady`), so
/// it waits for the Ghostty surface the same way. Only the ordinary New
/// Workspace controls (Cmd+N, the plus button, File → New Workspace) reach
/// this; CLI `workspace create`, layout commands, custom `ui.newWorkspace`
/// actions, browser workspaces and session restore keep upstream behaviour.
@MainActor
enum LawmuxNewWorkspaceCommand {
    /// The configured command, or nil when the setting is empty.
    static func configuredCommand(defaults: UserDefaults = .standard) -> String? {
        let value = AppCatalogSection().lawmuxNewWorkspaceCommand.value(in: defaults)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// What gets typed. The leading space keeps the command out of shell
    /// history where `HIST_IGNORE_SPACE` applies, like the welcome banner.
    static func typedText(for command: String) -> String {
        " " + command + "\n"
    }

    /// Wraps a workspace-creation handler so a plain terminal workspace also
    /// gets the configured command typed. Returns `handler` unchanged when the
    /// workspace is not a terminal or no command is configured.
    static func wrappingCreatedHandler(
        _ handler: ((Workspace) -> Void)?,
        initialSurface: NewWorkspaceInitialSurface,
        defaults: UserDefaults = .standard,
        send: @escaping (String, Workspace) -> Void
    ) -> ((Workspace) -> Void)? {
        guard initialSurface == .terminal,
              let command = configuredCommand(defaults: defaults) else {
            return handler
        }
        let text = typedText(for: command)
        return { workspace in
            handler?(workspace)
            send(text, workspace)
        }
    }
}

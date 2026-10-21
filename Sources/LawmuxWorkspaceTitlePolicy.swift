import Foundation

/// lawmux: automatic workspace titles follow the git worktree.
///
/// Title precedence in lawmux is: a title the user typed, then a title the
/// agent auto-naming produced, then the name of the git worktree the focused
/// terminal's directory is in, then upstream's terminal (process) title. The
/// first two are upstream's `customTitle` and already win; this file supplies
/// the third tier and `Workspace` falls back to the fourth when it is nil.
///
/// The worktree root is found by walking up from the directory until an entry
/// named `.git` exists (a directory for a main checkout, a file for a linked
/// worktree), so a worktree is titled by its own folder, not the main repo.
/// Only a few stat calls; no process is spawned.
enum LawmuxWorkspaceTitlePolicy {
    static func automaticTitle(forDirectory directory: String?, fileManager: FileManager = .default) -> String? {
        guard let root = gitWorktreeRoot(containing: directory, fileManager: fileManager) else { return nil }
        let name = root.lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }

    static func gitWorktreeRoot(containing directory: String?, fileManager: FileManager = .default) -> URL? {
        guard let directory = directory?.trimmingCharacters(in: .whitespacesAndNewlines),
              directory.hasPrefix("/") else { return nil }
        var url = URL(fileURLWithPath: directory, isDirectory: true).standardizedFileURL
        // Bounded walk: a pathological path cannot loop, and `/` has no `.git`.
        for _ in 0..<64 {
            if fileManager.fileExists(atPath: url.appendingPathComponent(".git").path) {
                return url
            }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { return nil }
            url = parent
        }
        return nil
    }
}

extension Workspace {
    /// lawmux: re-derives the automatic title after the focused terminal's
    /// directory changed. Does nothing while a custom title (user or agent)
    /// is set, or for remote-provenance workspaces whose paths are not local.
    func lawmuxRefreshAutomaticTitleForDirectoryChange() {
        guard customTitle == nil, !usesRemoteDirectoryProvenance else { return }
        let next = LawmuxWorkspaceTitlePolicy.automaticTitle(forDirectory: currentDirectory)
            ?? processTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !next.isEmpty else { return }
        applyAutomaticTitle(next)
    }

    /// lawmux: the title to show for a terminal (process) title report.
    func lawmuxAutomaticTitle(forProcessTitle processTitle: String) -> String {
        guard !usesRemoteDirectoryProvenance else { return processTitle }
        return LawmuxWorkspaceTitlePolicy.automaticTitle(forDirectory: currentDirectory) ?? processTitle
    }
}

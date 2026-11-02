import AppKit
import Combine
import CmuxSidebar
import Foundation
import os

/// lawmux: keeps the Homebrew cask `claude-code@latest` current from the
/// sidebar footer, replacing the "Update available! Run: brew upgrade
/// claude-code@latest" banner that Claude Code prints at launch.
///
/// The flow has two halves. The upgrade itself is safe at any time: a running
/// Claude keeps the binary it started with, and only the next launch picks up
/// the new one, so `brew upgrade` runs as soon as the button is clicked. The
/// restart that moves the already running sessions to the new version is a
/// separate click, enabled only while no Claude session is mid-turn, because
/// relaunching lawmux ends every process in every workspace; session restore
/// brings back the shells and resumes Claude, nothing else.
///
/// The latest version comes from the formulae.brew.sh JSON API rather than
/// `brew outdated`, which only knows what the last `brew update` fetched. The
/// installed version is read from the Caskroom; without a Caskroom entry
/// (Claude Code installed some other way) the button never appears.
///
/// Logged under subsystem `com.lawrenceturnerw.lawmux`, category
/// `claude-update`; the upgrade's own output goes to
/// `~/.local/state/lawmux/claude-code-upgrade.log`.
@MainActor
final class LawmuxClaudeCodeUpdater: ObservableObject {
    static let shared = LawmuxClaudeCodeUpdater()

    enum Phase: Equatable {
        /// Nothing to show: up to date, not a Homebrew install, or not checked yet.
        case hidden
        case available(installed: String, latest: String)
        case upgrading(latest: String)
        /// The cask is upgraded; running sessions still use the old binary.
        case upgraded(latest: String)
        case failed(message: String)
    }

    @Published private(set) var phase: Phase = .hidden
    /// Claude sessions that are mid-turn (running or driving subagents).
    @Published private(set) var busyClaudeCount = 0

    static let caskToken = "claude-code@latest"
    static let apiURL = URL(string: "https://formulae.brew.sh/api/cask/claude-code@latest.json")!
    static let checkInterval: TimeInterval = 6 * 60 * 60
    static let activationCheckInterval: TimeInterval = 60 * 60

    private let logger = Logger(subsystem: "com.lawrenceturnerw.lawmux", category: "claude-update")
    private var started = false
    private var lastCheck: Date?
    private var periodicCheck: Task<Void, Never>?
    private var busyPoll: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?

    // MARK: - Lifecycle

    /// Starts the periodic check. Safe to call from every footer instance.
    func start() {
        guard !started else { return }
        started = true
        periodicCheck = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: .seconds(Self.checkInterval))
            }
        }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let lastCheck, Date().timeIntervalSince(lastCheck) < Self.activationCheckInterval { return }
                await self.check()
            }
        }
    }

    // MARK: - Checking

    func check() async {
        if case .upgrading = phase { return }
        if case .upgraded = phase { return }
        lastCheck = Date()
        guard let installed = Self.installedVersion() else {
            logger.info("no Caskroom entry for \(Self.caskToken, privacy: .public); update button stays hidden")
            phase = .hidden
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: Self.apiURL)
            guard let latest = Self.latestVersion(fromAPIResponse: data) else {
                logger.error("could not read the cask version from the API response")
                return
            }
            if Self.isVersion(latest, newerThan: installed) {
                logger.info("Claude Code \(latest, privacy: .public) available (installed \(installed, privacy: .public))")
                phase = .available(installed: installed, latest: latest)
            } else {
                phase = .hidden
            }
        } catch {
            logger.error("version check failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Upgrading

    func upgrade() {
        guard case .available(_, let latest) = phase else { return }
        guard let brew = Self.brewExecutable() else {
            phase = .failed(message: "brew not found")
            return
        }
        phase = .upgrading(latest: latest)
        logger.info("running brew upgrade --cask \(Self.caskToken, privacy: .public)")
        let logURL = Self.upgradeLogURL
        Task.detached(priority: .userInitiated) {
            let result = Self.runBrewUpgrade(brew: brew, logURL: logURL)
            await MainActor.run {
                Self.shared.finishUpgrade(result: result, expected: latest)
            }
        }
    }

    private func finishUpgrade(result: Result<Void, UpgradeError>, expected latest: String) {
        switch result {
        case .success:
            let installed = Self.installedVersion()
            if installed == latest {
                logger.info("Claude Code \(latest, privacy: .public) installed; restart pending")
                phase = .upgraded(latest: latest)
                startBusyPolling()
            } else {
                logger.error("brew finished but the Caskroom has \(installed ?? "nothing", privacy: .public), not \(latest, privacy: .public)")
                phase = .failed(message: "Installed \(installed ?? "?") instead of \(latest)")
            }
        case .failure(let error):
            logger.error("brew upgrade failed: \(error.message, privacy: .public)")
            phase = .failed(message: error.message)
        }
    }

    /// After a failure, a click goes back to checking.
    func retry() {
        phase = .hidden
        Task { await check() }
    }

    struct UpgradeError: Error {
        let message: String
    }

    nonisolated private static func runBrewUpgrade(brew: URL, logURL: URL) -> Result<Void, UpgradeError> {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        fileManager.createFile(atPath: logURL.path, contents: nil)
        guard let log = try? FileHandle(forWritingTo: logURL) else {
            return .failure(UpgradeError(message: "cannot open \(logURL.path)"))
        }
        defer { try? log.close() }

        let process = Process()
        process.executableURL = brew
        process.arguments = ["upgrade", "--cask", caskToken]
        var environment = ProcessInfo.processInfo.environment
        let brewBin = brew.deletingLastPathComponent().path
        environment["PATH"] = "\(brewBin):/usr/bin:/bin:/usr/sbin:/sbin"
        environment["HOMEBREW_NO_ENV_HINTS"] = "1"
        environment["HOMEBREW_NO_INSTALL_CLEANUP"] = "1"
        environment["HOMEBREW_COLOR"] = "0"
        environment["NONINTERACTIVE"] = "1"
        process.environment = environment
        process.standardOutput = log
        process.standardError = log
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return .failure(UpgradeError(message: error.localizedDescription))
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let tail = (try? String(contentsOf: logURL, encoding: .utf8))?
                .split(separator: "\n").suffix(3).joined(separator: " ") ?? ""
            return .failure(UpgradeError(message: "brew exited \(process.terminationStatus): \(tail)"))
        }
        return .success(())
    }

    // MARK: - Busy sessions and restart

    private func startBusyPolling() {
        busyPoll?.cancel()
        refreshBusyClaudeCount()
        busyPoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                self?.refreshBusyClaudeCount()
            }
        }
    }

    func refreshBusyClaudeCount() {
        busyClaudeCount = Self.busyClaudeWorkspaces().count
    }

    /// Workspaces whose Claude Code pill reports a turn in progress.
    static func busyClaudeWorkspaces() -> [Workspace] {
        guard let appDelegate = AppDelegate.shared else { return [] }
        var seen = Set<ObjectIdentifier>()
        var busy: [Workspace] = []
        for context in appDelegate.mainWindowContexts.values {
            for workspace in context.tabManager.tabs where seen.insert(ObjectIdentifier(workspace)).inserted {
                if isBusy(workspace.statusEntries[LawmuxMascotStatusView.claudeStatusKey]) {
                    busy.append(workspace)
                }
            }
        }
        return busy
    }

    static func isBusy(_ entry: SidebarStatusEntry?) -> Bool {
        switch entry?.workState {
        case .running, .subagents: return true
        case .waiting, nil: return false
        }
    }

    /// Quits lawmux and relaunches it once the process has exited. Session
    /// restore then brings the workspaces back and resumes their Claude
    /// sessions on the upgraded binary.
    func restart() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        for _ in $(seq 1 600); do kill -0 \(pid) 2>/dev/null || break; sleep 0.3; done
        kill -0 \(pid) 2>/dev/null && exit 1
        sleep 1
        open -b '\(bundleID)'
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        process.arguments = ["/bin/sh", "-c", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            logger.error("could not start the relaunch helper: \(error.localizedDescription, privacy: .public)")
            phase = .failed(message: "relaunch helper: \(error.localizedDescription)")
            return
        }
        logger.info("relaunch helper started (pid \(process.processIdentifier)); quitting")
        NSApp.terminate(nil)
    }

    // MARK: - Homebrew lookups

    static var upgradeLogURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".local/state/lawmux/claude-code-upgrade.log", directoryHint: .notDirectory)
    }

    static let brewPrefixes = ["/opt/homebrew", "/usr/local"]

    static func brewExecutable() -> URL? {
        for prefix in brewPrefixes {
            let url = URL(fileURLWithPath: "\(prefix)/bin/brew")
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }

    /// The version `bin/claude` resolves to inside the Caskroom, e.g.
    /// `/opt/homebrew/Caskroom/claude-code@latest/2.1.312/claude` → `2.1.312`.
    /// Falls back to the highest Caskroom version directory when the link is
    /// missing.
    static func installedVersion(fileManager: FileManager = .default) -> String? {
        for prefix in brewPrefixes {
            let caskroom = "\(prefix)/Caskroom/\(caskToken)"
            guard fileManager.fileExists(atPath: caskroom) else { continue }
            let link = "\(prefix)/bin/claude"
            if let target = try? fileManager.destinationOfSymbolicLink(atPath: link),
               let version = version(fromCaskroomPath: target, caskroom: caskroom) {
                return version
            }
            let versions = ((try? fileManager.contentsOfDirectory(atPath: caskroom)) ?? [])
                .filter { !$0.hasPrefix(".") }
            return versions.max { isVersion($1, newerThan: $0) }
        }
        return nil
    }

    static func version(fromCaskroomPath target: String, caskroom: String) -> String? {
        let caskroomComponents = URL(fileURLWithPath: caskroom).pathComponents
        let targetComponents = URL(fileURLWithPath: target).pathComponents
        guard targetComponents.count > caskroomComponents.count,
              Array(targetComponents.prefix(caskroomComponents.count)) == caskroomComponents else {
            return nil
        }
        return targetComponents[caskroomComponents.count]
    }

    static func latestVersion(fromAPIResponse data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["version"] as? String, !version.isEmpty else {
            return nil
        }
        return version
    }

    /// Dotted numeric comparison; a non-numeric component compares as text.
    static func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let l = lhs.split(separator: ".").map(String.init)
        let r = rhs.split(separator: ".").map(String.init)
        for index in 0..<max(l.count, r.count) {
            let a = index < l.count ? l[index] : "0"
            let b = index < r.count ? r[index] : "0"
            if let ai = Int(a), let bi = Int(b) {
                if ai != bi { return ai > bi }
            } else if a != b {
                return a > b
            }
        }
        return false
    }
}

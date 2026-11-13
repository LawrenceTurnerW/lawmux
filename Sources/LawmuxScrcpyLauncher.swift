import AppKit
import CmuxSettingsUI
import Combine
import Foundation
import os

/// lawmux: launches scrcpy (Android screen mirroring) from the sidebar footer.
///
/// The button exists only on a Mac where scrcpy is installed (Homebrew
/// prefixes are checked), so no setting is needed: a Mac without Android
/// work never shows it. scrcpy runs as a child process with its own window;
/// no terminal is involved. The fixed arguments mirror the USB device, keep
/// it awake and skip audio:
///
///     scrcpy -d --window-title=lawmux --stay-awake --no-audio
///
/// Clicking while scrcpy runs terminates it. When scrcpy exits on its own
/// within a few seconds (no device, several devices without `-s`, adb not
/// running), the tail of its stderr goes to a lawmux notification; the full
/// output is in `~/.local/state/lawmux/scrcpy.log`.
///
/// Logged under subsystem `com.lawrenceturnerw.lawmux`, category `scrcpy`.
@MainActor
final class LawmuxScrcpyLauncher: ObservableObject {
    static let shared = LawmuxScrcpyLauncher()

    static let arguments = ["-d", "--window-title=lawmux", "--stay-awake", "--no-audio"]
    static let searchPaths = ["/opt/homebrew/bin/scrcpy", "/usr/local/bin/scrcpy"]
    /// An exit this soon after launch is reported as a failure to start.
    static let earlyExitWindow: TimeInterval = 8

    @Published private(set) var executable: URL?
    @Published private(set) var isRunning = false

    private let logger = Logger(subsystem: "com.lawrenceturnerw.lawmux", category: "scrcpy")
    private var process: Process?
    private var launchedAt: Date?
    private var activationObserver: NSObjectProtocol?

    private init() {
        refreshAvailability()
        // A `brew install scrcpy` while lawmux runs shows up on the next activation.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshAvailability() }
        }
    }

    var isAvailable: Bool { executable != nil }

    func refreshAvailability() {
        let found = Self.searchPaths
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
        if found != executable {
            executable = found
        }
    }

    static var logURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".local/state/lawmux/scrcpy.log", directoryHint: .notDirectory)
    }

    func toggle() {
        if isRunning { stop() } else { launch() }
    }

    func launch() {
        guard !isRunning, let executable else { return }
        let logURL = Self.logURL
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        fileManager.createFile(atPath: logURL.path, contents: nil)
        guard let log = try? FileHandle(forWritingTo: logURL) else {
            report(failure: "cannot open \(logURL.path)")
            return
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = Self.arguments
        var environment = ProcessInfo.processInfo.environment
        let binDir = executable.deletingLastPathComponent().path
        environment["PATH"] = "\(binDir):/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment
        process.standardOutput = log
        process.standardError = log
        process.standardInput = FileHandle.nullDevice
        process.terminationHandler = { [weak self] finished in
            try? log.close()
            Task { @MainActor [weak self] in
                self?.handleExit(of: finished)
            }
        }
        do {
            try process.run()
        } catch {
            try? log.close()
            report(failure: error.localizedDescription)
            return
        }
        self.process = process
        launchedAt = Date()
        isRunning = true
        logger.info("scrcpy started (pid \(process.processIdentifier))")
    }

    func stop() {
        guard let process, process.isRunning else { return }
        logger.info("terminating scrcpy (pid \(process.processIdentifier))")
        process.terminate()
    }

    private func handleExit(of finished: Process) {
        guard finished === process else { return }
        let status = finished.terminationStatus
        let wasKilled = finished.terminationReason == .uncaughtSignal
        let ranFor = launchedAt.map { Date().timeIntervalSince($0) } ?? 0
        process = nil
        launchedAt = nil
        isRunning = false
        logger.info("scrcpy exited (status \(status), after \(Int(ranFor))s)")
        // A clean exit or a termination we asked for needs no notice.
        if status == 0 || wasKilled { return }
        if ranFor < Self.earlyExitWindow {
            let tail = Self.stderrTail(logURL: Self.logURL)
            report(failure: tail.isEmpty ? "scrcpy exited with status \(status)" : tail)
        }
    }

    /// The last meaningful lines of scrcpy's output, which carry its error.
    static func stderrTail(logURL: URL, lines: Int = 3) -> String {
        guard let text = try? String(contentsOf: logURL, encoding: .utf8) else { return "" }
        return text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("ERROR") || $0.hasPrefix("WARN") || $0.hasPrefix("adb:") }
            .suffix(lines)
            .joined(separator: "\n")
    }

    private func report(failure message: String) {
        logger.error("scrcpy failed: \(message, privacy: .public)")
        let title = LawmuxText.string("scrcpy did not start", ja: "scrcpy を起動できませんでした")
        let body = message + "\n" + LawmuxText.string(
            "Log: \(Self.logURL.path)",
            ja: "ログ: \(Self.logURL.path)"
        )
        if let tabId = AppDelegate.shared?.activeTabManagerForCommands(preferredWindow: nil)?.selectedTabId {
            TerminalNotificationStore.shared.addNotification(
                tabId: tabId,
                surfaceId: nil,
                title: title,
                subtitle: "",
                body: body,
                cooldownKey: "lawmux.scrcpy.failed",
                cooldownInterval: 5
            )
        } else {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = body
            alert.runModal()
        }
    }
}

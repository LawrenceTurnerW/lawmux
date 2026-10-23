import AppKit
import CmuxSidebar

// lawmux: a mascot before the workspace title that mirrors the Claude Code
// status pill (`claude_code`). The pill itself is unchanged.
//
// Images live outside the repository, in ~/.config/lawmux/icons:
//
//   claude-running.gif      animated while Claude Code is working (a model turn,
//                           a tool call or subagents). Required; without it the
//                           view stays hidden and the row looks like upstream.
//   claude-idle.png         while Claude Code waits for the next prompt. Falls
//                           back to the running image, frozen and dimmed.
//   claude-needs-input.png  while Claude Code waits for a permission or an
//                           answer. Falls back to the running image, frozen.
//
// Any image format NSImage reads works for each file; an animated GIF only
// animates in the running state.
@MainActor
final class LawmuxMascotStatusView: NSImageView {
    enum State: Equatable {
        case running
        case idle
        case needsInput
    }

    static let claudeStatusKey = "claude_code"

    /// The mascot state for a row's status entries, or nil when Claude Code
    /// has no pill there (not launched, or exited).
    static func state(for entries: [SidebarStatusEntry]) -> State? {
        guard let entry = entries.first(where: { $0.key == claudeStatusKey }) else { return nil }
        switch entry.workState {
        case .running, .subagents:
            return .running
        case .waiting:
            return .idle
        case nil:
            // The hook sets `bell.fill` for "Needs input" and `pause.circle.fill`
            // for "Idle"; both carry no work state.
            return entry.icon == "bell.fill" ? .needsInput : .idle
        }
    }

    static let iconsDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".config/lawmux/icons", directoryHint: .isDirectory)

    private struct LoadedImage {
        let image: NSImage
        let isAnimated: Bool
        let modified: Date?
    }

    /// Keyed by file name; an edited file reloads through its modification date.
    private static var cache: [String: LoadedImage] = [:]

    private static func load(_ fileName: String) -> LoadedImage? {
        let url = iconsDirectory.appending(path: fileName, directoryHint: .notDirectory)
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        if let cached = cache[fileName], cached.modified == modified {
            return cached
        }
        guard modified != nil, let image = NSImage(contentsOf: url) else {
            cache[fileName] = nil
            return nil
        }
        image.isTemplate = false
        let frameCount = (image.representations.first as? NSBitmapImageRep)?
            .value(forProperty: .frameCount) as? Int ?? 1
        let loaded = LoadedImage(image: image, isAnimated: frameCount > 1, modified: modified)
        cache[fileName] = loaded
        return loaded
    }

    private(set) var state: State?
    private var animatesForState = false

    /// Rows off screen or in an inactive window stop the GIF, like the
    /// compact glyph's pulse.
    var isPresentationActive = true {
        didSet { if oldValue != isPresentationActive { updateAnimation() } }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageScaling = .scaleProportionallyUpOrDown
        isHidden = true
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shows the mascot for the row's entries; returns whether it is visible.
    @discardableResult
    func configure(entries: [SidebarStatusEntry]) -> Bool {
        guard let newState = Self.state(for: entries),
              let running = Self.load("claude-running.gif") else {
            state = nil
            animatesForState = false
            updateAnimation()
            image = nil
            isHidden = true
            return false
        }
        let stateFileName: String? = switch newState {
        case .running: nil
        case .idle: "claude-idle.png"
        case .needsInput: "claude-needs-input.png"
        }
        let stateImage = stateFileName.flatMap(Self.load)
        let loaded = stateImage ?? running
        if image !== loaded.image {
            image = loaded.image
        }
        // Only a fallback to the running image is dimmed; a dedicated idle
        // image is drawn as supplied.
        alphaValue = (newState == .idle && stateImage == nil) ? 0.55 : 1
        state = newState
        animatesForState = newState == .running && loaded.isAnimated
        updateAnimation()
        isHidden = false
        return true
    }

    private func updateAnimation() {
        let shouldAnimate = animatesForState && isPresentationActive
        if animates != shouldAnimate {
            animates = shouldAnimate
        }
    }
}

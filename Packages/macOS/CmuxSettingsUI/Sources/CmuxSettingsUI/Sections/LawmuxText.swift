import Foundation

/// lawmux: English/Japanese text for lawmux-only UI.
///
/// lawmux keeps its strings out of the shared string catalog (every key there
/// must carry all nine locales, and the catalog is the file most likely to
/// conflict with upstream). The fork's UI is wanted in Japanese and English
/// only, so this picks Japanese when the app runs in Japanese (upstream's
/// language setting applies an `AppleLanguages` override, which
/// `Bundle.main.preferredLocalizations` reflects after a relaunch) and
/// English everywhere else.
enum LawmuxText {
    static func string(_ english: String, ja japanese: String) -> String {
        isJapanese ? japanese : english
    }

    static var isJapanese: Bool {
        let preferred = Bundle.main.preferredLocalizations.first
            ?? Locale.preferredLanguages.first
            ?? "en"
        return preferred.hasPrefix("ja")
    }
}

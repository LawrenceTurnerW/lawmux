import CmuxSettings
import SwiftUI

/// lawmux: the fork's own Settings page, first in the General group.
///
/// Settings that lawmux adds or re-purposes live here instead of being
/// mixed into upstream's sections, so upstream page edits merge cleanly and
/// lawmux-specific rows are easy to find. Strings are lawmux-only and stay
/// out of the shared string catalog; see `LawmuxText` (Japanese or English).
public struct LawmuxSection: View {
    private let catalog: SettingCatalog
    @State private var defaultWorkspacePath: DefaultsValueModel<String>

    public init(defaultsStore: UserDefaultsSettingsStore, catalog: SettingCatalog) {
        self.catalog = catalog
        _defaultWorkspacePath = State(initialValue: DefaultsValueModel(store: defaultsStore, key: catalog.app.defaultWorkspacePath))
    }

    public var body: some View {
        Group {
            SettingsSectionHeader("lawmux", section: .lawmux)
                .accessibilityIdentifier("SettingsLawmuxSection")
            SettingsCard {
                LawmuxDefaultWorkspaceDirectoryRow(model: defaultWorkspacePath)
            }
        }
        .task {
            startSettingsObservation([defaultWorkspacePath])
        }
    }
}

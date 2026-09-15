import Foundation

enum SnapShortcutMigration {
    static let completedKey = "bs_snapShortcutMigrated"
    static let snapKey = "bs_hotkey_26"

    /// This fork used ID 6 for Snap before upstream introduced recording at ID 6.
    /// Upstream 0.5 migrations identify recording preferences and must be preserved.
    /// Older upstream-only profiles without either marker cannot be distinguished
    /// from this fork's customized Snap binding. This migration targets this fork;
    /// it retains the original bytes for recovery rather than guessing from the keys.
    static func migrate(defaults: UserDefaults) {
        guard !defaults.bool(forKey: completedKey) else { return }
        defer { defaults.set(true, forKey: completedKey) }
        guard !defaults.bool(forKey: "bs_captureShortcuts050Restored"),
              !defaults.bool(forKey: "bs_captureShortcuts050Migrated"),
              let legacy = defaults.data(forKey: "bs_hotkey_6") else { return }
        defaults.set(legacy, forKey: "bs_legacySnapHotkey_6")
        if defaults.data(forKey: snapKey) == nil {
            defaults.set(legacy, forKey: snapKey)
        }
        defaults.removeObject(forKey: "bs_hotkey_6")
    }
}

import XCTest

final class SnapShortcutMigrationTests: XCTestCase {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "BetterShotSnapMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    func testMovesCustomizedAndDisabledBindingsWithoutChangingBytes() {
        for enabled in [true, false] {
            withDefaults { defaults in
                let data = Data("{\"keyCode\":42,\"modifiers\":768,\"enabled\":\(enabled)}".utf8)
                defaults.set(data, forKey: "bs_hotkey_6")
                SnapShortcutMigration.migrate(defaults: defaults)
                XCTAssertEqual(defaults.data(forKey: "bs_hotkey_26"), data)
                XCTAssertEqual(defaults.data(forKey: "bs_legacySnapHotkey_6"), data)
                XCTAssertNil(defaults.object(forKey: "bs_hotkey_6"))
            }
        }
    }

    func testPreservesUpstreamRecordingPreferences() {
        for marker in ["bs_captureShortcuts050Restored", "bs_captureShortcuts050Migrated"] {
            withDefaults { defaults in
                let data = Data("recording binding".utf8)
                defaults.set(data, forKey: "bs_hotkey_6")
                defaults.set(true, forKey: marker)
                SnapShortcutMigration.migrate(defaults: defaults)
                XCTAssertEqual(defaults.data(forKey: "bs_hotkey_6"), data)
                XCTAssertNil(defaults.object(forKey: "bs_hotkey_26"))
            }
        }
    }

    func testNewProfileDoesNotCreateBindings() {
        withDefaults { defaults in
            SnapShortcutMigration.migrate(defaults: defaults)
            XCTAssertNil(defaults.object(forKey: "bs_hotkey_6"))
            XCTAssertNil(defaults.object(forKey: "bs_hotkey_26"))
            XCTAssertTrue(defaults.bool(forKey: SnapShortcutMigration.completedKey))
        }
    }

    func testNeverOverwritesNewSnapBindingOrLaterRecordingBinding() {
        withDefaults { defaults in
            let old = Data("old snap".utf8), new = Data("new snap".utf8), recording = Data("recording".utf8)
            defaults.set(old, forKey: "bs_hotkey_6")
            defaults.set(new, forKey: "bs_hotkey_26")
            SnapShortcutMigration.migrate(defaults: defaults)
            XCTAssertEqual(defaults.data(forKey: "bs_hotkey_26"), new)
            defaults.set(recording, forKey: "bs_hotkey_6")
            SnapShortcutMigration.migrate(defaults: defaults)
            XCTAssertEqual(defaults.data(forKey: "bs_hotkey_6"), recording)
            XCTAssertEqual(defaults.data(forKey: "bs_hotkey_26"), new)
        }
    }
}

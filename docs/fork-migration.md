# Fork migration

## Baselines

- Previous fork: `6b44beaa8ed0cbfb59e32f574dc82e5a1b4a6ede` (0.3.6).
- New upstream: `9054ab5e5e64449ac92c4a63ae70aff9c819c288` (0.5.3, macOS 26+).
- Local recovery branch: `chore/backup-before-upstream-migration-20260915`.

The old fork and upstream started with different Git histories. Merge commit
`3d80145` connects both histories and uses the exact upstream tree as the new
baseline. The previous fork remains a parent, so no published history is rewritten.
Snap Capture and the isolated build/test setup are separate commits on top of
that baseline. Upstream website, media, and skill changes belong to the upstream
history rather than the Snap feature commit.

To review only the fork additions at this migration baseline:

```bash
git diff 9054ab5e5e64449ac92c4a63ae70aff9c819c288...HEAD
```

Future upstream merges can use the shared ancestry. No remote changes were made.
The pre-organization worktree was also retained in the stash named
`移植結果の履歴整理前バックアップ`; the older recovery branch and app/settings/history
backups remain available.

## Preserved fork behavior

Snap Capture freezes the pointer display, fits a rough rectangle to content,
adds real surrounding pixels, and passes a lossless crop to the common pipeline.
Sensitivity presets, manual margin entry, 4 pt margin steps, cancellation and focus
restoration remain available. Region capture already supports Space in upstream.
ScreenCaptureKit replaces the obsolete CGDisplayCreateImage implementation.

Shortcut ID 26 is Snap; upstream ID 6 remains recording. Before upstream shortcut
migration, the old fork binding is moved byte-for-byte to ID 26, including disabled
and custom bindings. The original bytes remain under `bs_legacySnapHotkey_6`.
Profiles with upstream's 0.5 migration markers retain their recording binding.
Snap defaults to Command-Shift-E. Existing sensitivity and margin preference keys
are retained; their historical Px suffix refers to logical points.

## Local verification and rollback

Before migration, the old runnable app and exported preferences were copied into
`.git/migration-backup-20260915/`. These are machine-local backups, never committed.
Keep this directory and the recovery branch until the new app has been accepted.

Tests must use `.build-test`; never put an unsigned test build in `.build`.
Build the runnable app with the same `BS_SIGN_ID` and compare `codesign -d -r-`
against the backed-up app before launching. Tests never launch BetterShot.app.

To roll back, first preserve any new working changes and quit BetterShot normally.
The old source is available on the recovery branch. The backed-up BetterShot.app
can be restored to its original `.build/Build/Products/Debug/BetterShot.app` path.
Import `preferences.plist` from the backup only while the app is closed. Restoring
preferences replaces subsequent settings, so preserve the newer export first.
Capture/history files should likewise be preserved before reverting their format.
Do not reset macOS permissions or replace the signing certificate as a rollback step.

## Verification results

The migrated build and fixed-identity Debug build passed. The existing 25 standalone
checks passed, as did 7 content-snap and 4 shortcut-migration logic tests.
Snap's offscreen integration check covers tight crop bounds, Retina margins,
Return/Cancel callbacks, lossless PNG roundtrip and light/dark panel rendering.
The common screenshot pipeline check includes Snap in all Copy/Edit/retention combinations.

The full upstream video test fails at `Tests/ExportIntegration.swift` in
`checkFrameReuse`, at time 0.06 (cached versus fresh GPU pixels). This also
reproduces in an untouched archive of upstream main on this machine. Neither
the renderer nor the assertion was changed or disabled to pass the migration.
Later video export checks cannot be claimed as passing because this assertion
terminates that runner first.

Use `make test-snap` for ongoing background verification. The full upstream
`make test` includes live windows and should not run while the desktop is in use.

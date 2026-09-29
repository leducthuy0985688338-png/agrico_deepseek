# AGRICO local development with VS Code

Open the repository folder in VS Code. Install the recommended Dart and Flutter extensions, and verify `flutter doctor` in the integrated terminal. The tasks in **Terminal → Run Task** use the Flutter SDK on your computer.

On a clean checkout of `architecture/v2-foundation`, use a focused branch for each change:

```powershell
git status --short
git fetch origin
git switch architecture/v2-foundation
git pull --ff-only origin architecture/v2-foundation
git switch -c architecture/my-focused-change
flutter pub get
```

If `git status --short` lists local changes, preserve them and resolve the checkout before pulling or switching branches. Never reset or force-push to satisfy a checkpoint.

During development, run **AGRICO: focused tests** and **AGRICO: analyze**. Run an individual test from the terminal when narrowing a failure, for example:

```powershell
flutter test test/features/farm/application/land_parcel_spatial_contract_test.dart
```

Before a PR, run **AGRICO: full tests**, **AGRICO: analyze**, and `git diff --check`. Push the focused branch once the local checks pass; the PR runs FULL CI independently. Use **AGRICO: debug APK** only when a device build is needed. Android builds require the local Firebase configuration at `android/app/google-services.json`; this file is ignored by Git and must never be committed.

The current analyzer baseline includes existing warnings and infos. The CI command tolerates those existing findings but new warnings should be fixed in the focused change. Keep Sprint 11 metadata semantics, Sprint 12 spatial identity guards, and the Sprint 13A–13B write integrity rules intact.

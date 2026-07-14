# Rebrand to DejaVi (complete)

The whole product is now **DejaVi**. A competitor shipped an identical app under
the project's former name, so every trace of the old name was removed from the
repo — file and directory names, target/module/type names, string literals,
comments, docs, and build scripts. No data migration: there are no shipped users,
so old keychain items / Application Support / cache dirs under the old identity
are abandoned (the app re-asks for the Gemini key on first launch — expected).

## What changed

- [x] SPM package → `DejaVi` (Package.swift, project.yml package ref)
- [x] Shared module/target → `DejaViCore` (`Sources/DejaViCore/`)
- [x] macOS target → `DejaViMac` (`Sources/DejaViMac/`)
- [x] iOS target → `DejaViiOS` (`Sources/DejaViiOS/`)
- [x] project.yml project `name` → `DejaVi` → `DejaVi.xcodeproj`
- [x] Both app entry-point structs → `DejaViApp`; files → `DejaViApp.swift`
- [x] macOS entitlements file → `DejaVi.entitlements`
- [x] macOS bundle id → `com.rafa.dejavi.mac`
- [x] Keychain service string → `com.rafa.dejavi` (SettingsManager)
- [x] Persistence paths → `Application Support/DejaVi`, `dejavi.db`
- [x] SwiftPM resource bundle → `DejaVi_DejaViMac.bundle`
- [x] build.sh (`DejaVi.app` / `DejaVi.dmg`), README.md, RELEASE.md, all UI strings
- [x] All renames done with `git mv` so history follows

## Constraints honored (live TestFlight)

- iOS bundle id `com.rafa.dejavi` unchanged (live in App Store Connect).
- iOS product name `DejaVi`; `DEVELOPMENT_TEAM` untouched.
- iOS `Info.plist` is xcodegen-generated from project.yml `info.properties`;
  never hand-edited. Preserved `ITSAppUsesNonExemptEncryption`, both orientation
  arrays (iPhone + iPad), the two photo-permission strings, `CFBundleDisplayName`.

## Verification

- grep / find for the old name across the tree return nothing.
- `swift build` (macOS/SPM) succeeds.
- `xcodegen generate` + `xcodebuild -project DejaVi.xcodeproj -scheme DejaViiOS`
  build succeeds; built bundle CFBundleIdentifier=com.rafa.dejavi,
  CFBundleDisplayName=DejaVi.
- `./build.sh` produces a signed `DejaVi.app` / `DejaVi.dmg`.

## Manual follow-up

Repo-directory / GitHub-repo rename, developer-portal cleanup of the obsolete iOS
App ID, and the TestFlight re-archive are tracked in the session hand-off notes
(out of scope for the in-repo rebrand).

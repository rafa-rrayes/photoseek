# Rename iOS app to DejaVi + TestFlight prep

Approved scope (user picked the name "DejaVi" after offer to do rename + TestFlight prep in one pass).
macOS app/brand intentionally untouched — it has shipped customers; separate decision.

- [x] Flatten logo.png (has alpha) to opaque 1024×1024 AppIcon.png via CoreGraphics
- [x] Create Assets.xcassets with single-size AppIcon set
- [x] Info.plist: CFBundleDisplayName=DejaVi, update permission strings, ITSAppUsesNonExemptEncryption=NO
- [x] project.yml: PRODUCT_BUNDLE_IDENTIFIER=com.rafa.dejavi, PRODUCT_NAME=DejaVi, wire in asset catalog + ASSETCATALOG_COMPILER_APPICON_NAME
- [x] iOSContentView.swift: replace 2 user-visible "PhotoSeek" strings
- [x] Regenerate Xcode project (xcodegen)
- [x] Verify: simulator build compiles, icon in built app, plist values correct

## Review

- App Store search: no name collision for "DejaVi" (only unrelated "Tajale" matched).
- Gotcha found: `xcodegen generate` OVERWRITES Sources/PhotoSeekiOS/Resources/Info.plist
  (project.yml `info:` block = generated plist). Prior hand-edits were being silently
  clobbered. Fixed properly: all plist keys now live in project.yml `info.properties`,
  so generation is reproducible. Never hand-edit that Info.plist.
- Keychain service "com.rafa.photoseek" in PhotoSeekCore/SettingsManager.swift left
  unchanged on purpose — it's a hardcoded service string shared with macOS, not tied
  to bundle ID.
- Verified: simulator build succeeds; built bundle is DejaVi.app with
  CFBundleIdentifier=com.rafa.dejavi, CFBundleDisplayName=DejaVi, Assets.car with
  compiled AppIcon, CFBundleIconName=AppIcon present (App Store validation requirement),
  icon PNG is 1024×1024 with no alpha (transparency is an upload rejection).
- macOS target, PhotoSeekCore, repo name: still PhotoSeek (unchanged).

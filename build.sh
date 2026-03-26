#!/bin/bash
set -e

APP_NAME="PhotoSeek"
BUNDLE_DIR="build/${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
ENTITLEMENTS="Sources/PhotoSeekMac/Resources/PhotoSeek.entitlements"

echo "Building ${APP_NAME} macOS (release)..."
swift build -c release --target PhotoSeekMac

echo "Creating app bundle..."
rm -rf "${BUNDLE_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# Copy binary
cp ".build/release/PhotoSeekMac" "${MACOS_DIR}/${APP_NAME}"

# Copy Info.plist
cp "Sources/PhotoSeekMac/Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"

# Copy app icon if it exists
if [ -f "Sources/PhotoSeekMac/Resources/AppIcon.icns" ]; then
    cp "Sources/PhotoSeekMac/Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

# Copy menu bar icons into the SwiftPM resource bundle
BUNDLE_RES="${RESOURCES_DIR}/PhotoSeekMac_PhotoSeekMac.bundle"
mkdir -p "${BUNDLE_RES}"
cp "Sources/PhotoSeekMac/Resources/MenuBarIcon.png" "${BUNDLE_RES}/"
cp "Sources/PhotoSeekMac/Resources/MenuBarIcon@2x.png" "${BUNDLE_RES}/"

echo "Done: ${BUNDLE_DIR}"

# --- Code Signing ---
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
if [ -z "$SIGNING_IDENTITY" ]; then
    SIGNING_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep "Developer ID Application" | head -1 | awk -F'"' '{print $2}' || true)
fi

if [ -n "$SIGNING_IDENTITY" ]; then
    echo "Signing with: ${SIGNING_IDENTITY}"
    codesign --force --options runtime --deep \
        --sign "$SIGNING_IDENTITY" \
        --entitlements "$ENTITLEMENTS" \
        "${BUNDLE_DIR}"
    echo "Signed"
else
    echo "No signing identity found — app will trigger Gatekeeper warnings."
    echo "  Users will need to right-click > Open on first launch."
    echo "  To sign: export SIGNING_IDENTITY='Developer ID Application: ...'"
fi

# --- Create DMG ---
DMG_DIR="build/dmg"
DMG_PATH="build/${APP_NAME}.dmg"

echo "Creating DMG..."
rm -rf "${DMG_DIR}" "${DMG_PATH}"
mkdir -p "${DMG_DIR}"
cp -r "${BUNDLE_DIR}" "${DMG_DIR}/"
ln -s /Applications "${DMG_DIR}/Applications"

hdiutil create -volname "${APP_NAME}" \
  -srcfolder "${DMG_DIR}" \
  -ov -format UDZO \
  "${DMG_PATH}"

rm -rf "${DMG_DIR}"

# Sign DMG if identity available
if [ -n "$SIGNING_IDENTITY" ]; then
    codesign --sign "$SIGNING_IDENTITY" "${DMG_PATH}"
fi

# --- Notarization (optional) ---
if [ -n "$SIGNING_IDENTITY" ] && [ -n "$APPLE_ID" ] && [ -n "$TEAM_ID" ]; then
    echo "Notarizing..."
    xcrun notarytool submit "${DMG_PATH}" \
        --apple-id "$APPLE_ID" \
        --team-id "$TEAM_ID" \
        --keychain-profile "notarize-profile" \
        --wait
    xcrun stapler staple "${DMG_PATH}"
    echo "Notarized"
elif [ -n "$SIGNING_IDENTITY" ]; then
    echo "Skipping notarization (set APPLE_ID and TEAM_ID to enable)"
fi

echo ""
echo "DMG ready: ${DMG_PATH}"
echo "  Distribute this file — users open it and drag ${APP_NAME} to Applications."

#!/bin/bash
#
# DejaVi macOS release build, sign, notarize, staple, package.
#
# Stages:
#   1. swift build (universal arm64 + x86_64 unless ARCHS overrides)
#   2. Assemble DejaVi.app, copying SwiftPM resource bundles into
#      Contents/Resources/ (canonical macOS layout). The app uses
#      AppResourceBundle to locate them there instead of Bundle.module, whose
#      SwiftPM-generated accessor expects the bundle at the .app root — a path
#      that violates macOS code-signing rules.
#   3. Code-sign with Developer ID Application + hardened runtime, signing
#      nested bundles before the outer .app.
#   4. Build DMG, sign DMG.
#   5. Notarize DMG via notarytool, staple .app and .dmg.
#
# Required env (signing & notarization are no-ops if unset):
#   SIGNING_IDENTITY     "Developer ID Application: <Name> (<TEAMID>)"
#   NOTARY_PROFILE       keychain profile name created via
#                        `xcrun notarytool store-credentials`
#
# Optional env:
#   ARCHS                space-separated list, default "arm64 x86_64".
#                        Set to "arm64" for arm64-only build.
#   APP_VERSION          overrides CFBundleShortVersionString.
#
set -euo pipefail

APP_NAME="DejaVi"
SWIFT_PRODUCT="DejaViMac"
PACKAGE_NAME="DejaVi"   # must match Package.swift `name:` (used for SwiftPM bundle naming)
BUNDLE_ID="com.rafa.dejavi.mac"

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${ROOT}/build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
DMG_PATH="${BUILD_DIR}/${APP_NAME}.dmg"
DMG_STAGING="${BUILD_DIR}/dmg-staging"

ENTITLEMENTS="${ROOT}/Sources/DejaViMac/Resources/DejaVi.entitlements"
INFO_PLIST="${ROOT}/Sources/DejaViMac/Resources/Info.plist"
APP_ICON="${ROOT}/Sources/DejaViMac/Resources/AppIcon.icns"

ARCHS="${ARCHS:-arm64 x86_64}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

# -----------------------------------------------------------------------------
# 1. Build each requested architecture and lipo the executable.
# -----------------------------------------------------------------------------
echo "==> Building ${SWIFT_PRODUCT} (release) for: ${ARCHS}"

ARCH_BINARIES=()
for arch in ${ARCHS}; do
    echo "    swift build --arch ${arch}"
    swift build -c release --arch "${arch}" --product "${SWIFT_PRODUCT}" >/dev/null
    arch_bin="${ROOT}/.build/${arch}-apple-macosx/release/${SWIFT_PRODUCT}"
    if [[ ! -x "${arch_bin}" ]]; then
        echo "ERROR: expected binary not found: ${arch_bin}" >&2
        exit 1
    fi
    ARCH_BINARIES+=("${arch_bin}")
done

# Pick any arch's release dir as the source for the SwiftPM resource bundle —
# its contents are arch-independent (PNGs, plist, etc.).
FIRST_ARCH="${ARCHS%% *}"
RELEASE_DIR="${ROOT}/.build/${FIRST_ARCH}-apple-macosx/release"

# -----------------------------------------------------------------------------
# 2. Assemble the .app bundle.
# -----------------------------------------------------------------------------
echo "==> Assembling ${APP_BUNDLE}"
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# Universal executable.
if [[ ${#ARCH_BINARIES[@]} -gt 1 ]]; then
    lipo -create -output "${MACOS_DIR}/${APP_NAME}" "${ARCH_BINARIES[@]}"
else
    cp "${ARCH_BINARIES[0]}" "${MACOS_DIR}/${APP_NAME}"
fi
chmod +x "${MACOS_DIR}/${APP_NAME}"

# Info.plist + icon.
cp "${INFO_PLIST}" "${CONTENTS_DIR}/Info.plist"
if [[ -n "${APP_VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${APP_VERSION}" \
        "${CONTENTS_DIR}/Info.plist"
fi
if [[ -f "${APP_ICON}" ]]; then
    cp "${APP_ICON}" "${RESOURCES_DIR}/AppIcon.icns"
fi

# SwiftPM resource bundles — copied into Contents/Resources/ (canonical macOS
# layout, what `codesign` requires). The app reads them via AppResourceBundle,
# not Bundle.module, because the SwiftPM-generated `Bundle.module` accessor on
# macOS looks at the .app root (Bundle.main.bundleURL/<bundle>), which violates
# the "Contents/-only at the root" rule that codesign enforces.
#
# Naming is <PackageName>_<TargetName>.bundle. Verify by inspecting
# .build/<arch>-apple-macosx/release/<Package>_<Target>.bundle.
RESOURCE_BUNDLES=(
    "${PACKAGE_NAME}_${SWIFT_PRODUCT}.bundle"
)
for bundle in "${RESOURCE_BUNDLES[@]}"; do
    src="${RELEASE_DIR}/${bundle}"
    if [[ ! -d "${src}" ]]; then
        echo "ERROR: expected SwiftPM resource bundle missing: ${src}" >&2
        echo "       (did the target's resources: declaration change?)" >&2
        exit 1
    fi
    dst="${RESOURCES_DIR}/${bundle}"
    cp -R "${src}" "${dst}"

    if [[ ! -f "${dst}/Info.plist" ]]; then
        bundle_id_suffix="${bundle%.bundle}"
        cat > "${dst}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}.${bundle_id_suffix}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${bundle_id_suffix}</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
</dict>
</plist>
EOF
    fi
done

echo "    .app contents:"
ls -1 "${APP_BUNDLE}" | sed 's/^/      /'

# -----------------------------------------------------------------------------
# 3. Code-sign (Developer ID Application + hardened runtime).
# -----------------------------------------------------------------------------
if [[ -z "${SIGNING_IDENTITY}" ]]; then
    auto_id="$(security find-identity -v -p codesigning 2>/dev/null \
        | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
    if [[ -n "${auto_id}" ]]; then
        SIGNING_IDENTITY="${auto_id}"
    fi
fi

if [[ -n "${SIGNING_IDENTITY}" ]]; then
    echo "==> Signing with: ${SIGNING_IDENTITY}"

    # Sign nested resource bundles first, then the outer .app.
    # Avoid --deep: it's deprecated and skips entitlements on nested items.
    for bundle in "${RESOURCE_BUNDLES[@]}"; do
        codesign --force --options runtime --timestamp \
            --sign "${SIGNING_IDENTITY}" \
            "${RESOURCES_DIR}/${bundle}"
    done

    codesign --force --options runtime --timestamp \
        --entitlements "${ENTITLEMENTS}" \
        --sign "${SIGNING_IDENTITY}" \
        "${APP_BUNDLE}"

    echo "    verifying signature..."
    codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"
else
    echo "==> No Developer ID Application identity found; producing UNSIGNED app."
    echo "    This DMG will trigger Gatekeeper 'damaged' on customer Macs."
    echo "    See RELEASE.md for how to obtain the cert."
fi

# -----------------------------------------------------------------------------
# 4. Build & sign DMG.
# -----------------------------------------------------------------------------
echo "==> Building DMG"
rm -rf "${DMG_STAGING}" "${DMG_PATH}"
mkdir -p "${DMG_STAGING}"
cp -R "${APP_BUNDLE}" "${DMG_STAGING}/"
ln -s /Applications "${DMG_STAGING}/Applications"

hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${DMG_STAGING}" \
    -ov -format UDZO \
    "${DMG_PATH}" >/dev/null

rm -rf "${DMG_STAGING}"

if [[ -n "${SIGNING_IDENTITY}" ]]; then
    codesign --force --timestamp --sign "${SIGNING_IDENTITY}" "${DMG_PATH}"
fi

# -----------------------------------------------------------------------------
# 5. Notarize + staple.
# -----------------------------------------------------------------------------
if [[ -n "${SIGNING_IDENTITY}" && -n "${NOTARY_PROFILE}" ]]; then
    echo "==> Notarizing ${DMG_PATH} (this can take several minutes)"
    xcrun notarytool submit "${DMG_PATH}" \
        --keychain-profile "${NOTARY_PROFILE}" \
        --wait

    echo "==> Stapling .app and .dmg"
    xcrun stapler staple "${APP_BUNDLE}"
    xcrun stapler staple "${DMG_PATH}"

    echo "==> Final verification"
    xcrun stapler validate "${APP_BUNDLE}"
    xcrun stapler validate "${DMG_PATH}"
    spctl -a -vvv --type execute "${APP_BUNDLE}" || true
elif [[ -n "${SIGNING_IDENTITY}" ]]; then
    echo "==> Skipping notarization (set NOTARY_PROFILE to enable)"
fi

echo ""
echo "Done."
echo "  .app: ${APP_BUNDLE}"
echo "  .dmg: ${DMG_PATH}"

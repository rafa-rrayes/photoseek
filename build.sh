#!/bin/bash
set -e

APP_NAME="PhotoSeek"
BUNDLE_DIR="build/${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "Building ${APP_NAME} (release)..."
swift build -c release

echo "Creating app bundle..."
rm -rf "${BUNDLE_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# Copy binary
cp ".build/release/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"

# Copy Info.plist
cp "Sources/${APP_NAME}/Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"

# Copy app icon if it exists
if [ -f "Sources/${APP_NAME}/Resources/AppIcon.icns" ]; then
    cp "Sources/${APP_NAME}/Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

echo ""
echo "✓ Built: ${BUNDLE_DIR}"
echo ""
echo "To run:  open build/${APP_NAME}.app"
echo "To install: cp -r build/${APP_NAME}.app /Applications/"

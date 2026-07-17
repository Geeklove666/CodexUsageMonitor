#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode-beta.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi

APP_NAME="Codex Usage Monitor"
EXECUTABLE_NAME="CodexUsageMonitor"
BUNDLE_ID="local.codex-usage-monitor"
INFO_PLIST="$ROOT_DIR/CodexUsageMonitor/Resources/Info.plist"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")}"
BUILD_NUMBER="${BUILD_NUMBER:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")}"
SIGNING_IDENTITY="${CODESIGN_IDENTITY:--}"

if [[ "$SIGNING_IDENTITY" == "-" && "${ALLOW_ADHOC:-0}" != "1" ]]; then
  echo "拒绝生成对外分发包：未配置 Developer ID Application 证书。" >&2
  echo "仅本机开发测试可显式设置 ALLOW_ADHOC=1。" >&2
  exit 2
fi
if [[ "$SIGNING_IDENTITY" != "-" && -z "${NOTARY_PROFILE:-}" && "${SKIP_NOTARIZATION:-0}" != "1" ]]; then
  echo "拒绝生成未公证的分享包：请设置 NOTARY_PROFILE。" >&2
  echo "仅内部测试可显式设置 SKIP_NOTARIZATION=1。" >&2
  exit 2
fi

PRODUCTS_DIR="$ROOT_DIR/.build/out/Products/Release"
EXECUTABLE="$PRODUCTS_DIR/$EXECUTABLE_NAME"
RESOURCE_BUNDLE="$PRODUCTS_DIR/CodexUsageMonitor_CodexUsageMonitor.bundle"
DIST_DIR="$ROOT_DIR/Dist"
WORK_DIR="$DIST_DIR/.package-work"
APP_PATH="$DIST_DIR/$APP_NAME.app"
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  DMG_NAME="Codex-Usage-Monitor-$VERSION-local-test-universal.dmg"
else
  DMG_NAME="Codex-Usage-Monitor-$VERSION-universal.dmg"
fi
DMG_PATH="$DIST_DIR/$DMG_NAME"

echo "Building Universal 2 release for macOS 14+..."
swift build -c release --arch arm64 --arch x86_64 --jobs "${BUILD_JOBS:-2}"

if [[ ! -x "$EXECUTABLE" || ! -d "$RESOURCE_BUNDLE" ]]; then
  echo "Release products are incomplete." >&2
  exit 1
fi

rm -rf "$WORK_DIR" "$APP_PATH" "$DMG_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources" "$WORK_DIR/dmg"

ditto "$EXECUTABLE" "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
ditto "$RESOURCE_BUNDLE" "$APP_PATH/Contents/Resources/$(basename "$RESOURCE_BUNDLE")"
ditto "$INFO_PLIST" "$APP_PATH/Contents/Info.plist"
ditto "$ROOT_DIR/CodexUsageMonitor/Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
ditto "$ROOT_DIR/CodexUsageMonitor/Resources/PrivacyInfo.xcprivacy" "$APP_PATH/Contents/Resources/PrivacyInfo.xcprivacy"

/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $EXECUTABLE_NAME" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion 14.0" "$APP_PATH/Contents/Info.plist"

chmod 755 "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
xattr -cr "$APP_PATH"

SIGN_ARGS=(--force --sign "$SIGNING_IDENTITY")
if [[ "$SIGNING_IDENTITY" != "-" ]]; then
  SIGN_ARGS+=(--options runtime --timestamp)
fi
codesign "${SIGN_ARGS[@]}" "$APP_PATH/Contents/Resources/$(basename "$RESOURCE_BUNDLE")"
codesign "${SIGN_ARGS[@]}" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

ditto "$APP_PATH" "$WORK_DIR/dmg/$APP_NAME.app"
ln -s /Applications "$WORK_DIR/dmg/Applications"
ditto "$ROOT_DIR/Docs/DMG安装说明.txt" "$WORK_DIR/dmg/安装说明.txt"

if diskutil image create from --help >/dev/null 2>&1; then
  diskutil image create from \
    --volumeName "$APP_NAME" \
    --format UDZO \
    "$WORK_DIR/dmg" \
    "$DMG_PATH"
else
  hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$WORK_DIR/dmg" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov "$DMG_PATH"
fi

codesign "${SIGN_ARGS[@]}" "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"

if [[ -n "${NOTARY_PROFILE:-}" && "$SIGNING_IDENTITY" != "-" ]]; then
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"
fi

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  echo "警告：这是 ad-hoc 签名的本机测试包，不能作为可分享发行版。" >&2
  echo "其他 Mac 的 Gatekeeper 可能拒绝启动；正式分发必须使用 Developer ID 并完成公证。" >&2
fi

ARCHS="$(lipo -archs "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME")"
MIN_VERSIONS="$(otool -l "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME" | awk '/LC_BUILD_VERSION/{found=1;next} found&&/minos/{print $2;found=0}' | sort -u | tr '\n' ' ')"
shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"
rm -rf "$WORK_DIR"

echo
echo "Created: $DMG_PATH"
echo "Architectures: $ARCHS"
echo "Minimum macOS: $MIN_VERSIONS"
echo "Signing identity: $SIGNING_IDENTITY"
echo "SHA-256: $(cut -d ' ' -f 1 "$DMG_PATH.sha256")"

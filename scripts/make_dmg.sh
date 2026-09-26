#!/bin/bash
# 首版 DMG 打包（M5）：Release 构建 + hdiutil 压缩镜像
# 用法：scripts/make_dmg.sh [版本号]
# 签名说明：当前 ad-hoc 免签构建；M5 发布前接入 Developer ID 签名 + 公证后，
# 在 xcodebuild 处补 CODE_SIGN_IDENTITY="Developer ID Application" TEAMID 并先 codesign 再打 DMG。
set -euo pipefail

VERSION="${1:-$(grep -o 'MARKETING_VERSION: "[^"]*"' project.yml | head -1 | cut -d'"' -f2 || echo 0.5.0)}"
BUILD_DIR="build"
APP_NAME="VehicleParameter"
DMG_NAME="VehicleParameter-${VERSION}-arm64.dmg"

echo "=== 1. Release 构建（arm64，复用默认 DerivedData 的包解析）"
xcodegen generate
xcodebuild -project "${APP_NAME}.xcodeproj" \
    -scheme "${APP_NAME}" \
    -configuration Release \
    -destination 'platform=macOS,arch=arm64' \
    CODE_SIGNING_ALLOWED=NO build

APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "${APP_NAME}.app" -path "*Release*" 2>/dev/null | head -1)
[ -n "$APP_PATH" ] || { echo "构建产物缺失"; exit 1; }

echo "=== 2. 组装 DMG 源目录"
rm -rf "${BUILD_DIR}/dmg-staging" "${BUILD_DIR}/${DMG_NAME}"
mkdir -p "${BUILD_DIR}/dmg-staging"
cp -R "$APP_PATH" "${BUILD_DIR}/dmg-staging/"
ln -s /Applications "${BUILD_DIR}/dmg-staging/Applications"

echo "=== 3. hdiutil 打包（UDZO 压缩）"
hdiutil create \
    -volname "${APP_NAME} ${VERSION}" \
    -srcfolder "${BUILD_DIR}/dmg-staging" \
    -ov -format UDZO \
    "${BUILD_DIR}/${DMG_NAME}"

echo "=== 完成：${BUILD_DIR}/${DMG_NAME}"
ls -lh "${BUILD_DIR}/${DMG_NAME}"
echo ""
echo "发布前待办：Developer ID 签名 → 公证（notarytool）→ Sparkle appcast（sign_update）"

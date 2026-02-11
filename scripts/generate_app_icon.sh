#!/bin/zsh

set -euo pipefail

assetDir="${PROJECT_DIR}/Hush/Assets.xcassets/AppIcon.appiconset"
iconsetDir="${TEMP_DIR}/HushAppIcon.iconset"
destDir="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
destFile="${destDir}/AppIcon.icns"

requiredFiles=(
  "appIcon_16x16.png"
  "appIcon_16x16@2x.png"
  "appIcon_32x32.png"
  "appIcon_32x32@2x.png"
  "appIcon_128x128.png"
  "appIcon_128x128@2x.png"
  "appIcon_256x256.png"
  "appIcon_256x256@2x.png"
  "appIcon_512x512.png"
  "appIcon_512x512@2x.png"
)

for filename in "${requiredFiles[@]}"; do
  if [[ ! -f "${assetDir}/${filename}" ]]; then
    echo "[generate_app_icon] Missing icon asset: ${assetDir}/${filename}" >&2
    exit 1
  fi
done

rm -rf "${iconsetDir}"
mkdir -p "${iconsetDir}"

cp "${assetDir}/appIcon_16x16.png" "${iconsetDir}/icon_16x16.png"
cp "${assetDir}/appIcon_16x16@2x.png" "${iconsetDir}/icon_16x16@2x.png"
cp "${assetDir}/appIcon_32x32.png" "${iconsetDir}/icon_32x32.png"
cp "${assetDir}/appIcon_32x32@2x.png" "${iconsetDir}/icon_32x32@2x.png"
cp "${assetDir}/appIcon_128x128.png" "${iconsetDir}/icon_128x128.png"
cp "${assetDir}/appIcon_128x128@2x.png" "${iconsetDir}/icon_128x128@2x.png"
cp "${assetDir}/appIcon_256x256.png" "${iconsetDir}/icon_256x256.png"
cp "${assetDir}/appIcon_256x256@2x.png" "${iconsetDir}/icon_256x256@2x.png"
cp "${assetDir}/appIcon_512x512.png" "${iconsetDir}/icon_512x512.png"
cp "${assetDir}/appIcon_512x512@2x.png" "${iconsetDir}/icon_512x512@2x.png"

mkdir -p "${destDir}"
/usr/bin/iconutil --convert icns --output "${destFile}" "${iconsetDir}"

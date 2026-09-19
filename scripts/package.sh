#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export BUILD_ARCH="${BUILD_ARCH:-universal}"
bash scripts/build.sh "$@"
app_path="$PWD/dist/划词翻译.app"
version="$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
case "$version" in *[!0-9.]*|'') printf 'Invalid version\n' >&2; exit 1 ;; esac
asset_name="SelectionTranslate-$version-macOS-$BUILD_ARCH"
staging="$(mktemp -d "$PWD/dist/.dmg-build.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
ditto "$app_path" "$staging/划词翻译.app"
ln -s /Applications "$staging/Applications"
cp docs/INSTALL.txt "$staging/安装说明.txt"
cp Resources/Help.html "$staging/使用帮助.html"
[[ ! -f LICENSE ]] || cp LICENSE "$staging/LICENSE.txt"
hdiutil create -volname "划词翻译 $version" -srcfolder "$staging" -format UDZO -ov "dist/$asset_name.dmg"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "dist/$asset_name.zip"
hdiutil verify "dist/$asset_name.dmg"
unzip -t "dist/$asset_name.zip" > "$staging/zip-check.log"
(cd dist && shasum -a 256 "$asset_name.dmg" "$asset_name.zip" > "$asset_name.sha256")
printf '发布文件：dist/%s.{dmg,zip,sha256}\n' "$asset_name"

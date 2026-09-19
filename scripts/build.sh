#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
architecture="${BUILD_ARCH:-$(uname -m)}"
case "$architecture" in
    arm64|x86_64) architectures=("$architecture") ;;
    universal) architectures=(arm64 x86_64) ;;
    *) printf 'BUILD_ARCH must be arm64, x86_64, or universal.\n' >&2; exit 1 ;;
esac
binaries=()
for build_arch in "${architectures[@]}"; do
    build_options=(-c release --triple "$build_arch-apple-macosx15.0" --scratch-path ".build/$build_arch")
    swift build "${build_options[@]}" "$@"
    binary_dir="$(swift build "${build_options[@]}" --show-bin-path "$@")"
    binaries+=("$binary_dir/SelectionTranslate")
done
mkdir -p dist
staging="$(mktemp -d "$PWD/dist/.app-build.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
staged_app="$staging/划词翻译.app"
app_path="$PWD/dist/划词翻译.app"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
if [[ "$architecture" == universal ]]; then
    xcrun lipo -create "${binaries[@]}" -output "$staged_app/Contents/MacOS/SelectionTranslate"
else
    cp "${binaries[0]}" "$staged_app/Contents/MacOS/SelectionTranslate"
fi
chmod 755 "$staged_app/Contents/MacOS/SelectionTranslate"
cp Resources/Info.plist "$staged_app/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/Help.html "$staged_app/Contents/Resources/"
plutil -lint "$staged_app/Contents/Info.plist"
signing_identity="${SIGNING_IDENTITY:--}"
if [[ "$signing_identity" == "-" ]]; then
    codesign --force --sign - "$staged_app"
    printf '提示：临时签名、未公证。重新构建后可能需要重新授予辅助功能权限。\n'
else
    codesign --force --options runtime --timestamp --sign "$signing_identity" "$staged_app"
fi
codesign --verify --strict "$staged_app"
if [[ -d "$app_path" ]]; then
    mv "$app_path" "$staging/previous.app"
fi
mv "$staged_app" "$app_path"
touch "$app_path"
printf '已生成：%s (%s)\n' "$app_path" "$architecture"

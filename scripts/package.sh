#!/bin/sh
# 将编译产物打包为 deb + TrollFools 可用的 zip。
# 用法：make package 或 sh scripts/package.sh v3.6.0
set -eu
umask 022

VERSION="${1:-v3.6.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DYLIB="$ROOT/build/AntManorPort-$VERSION.dylib"
PKG="$ROOT/antforest/Package"
OUT="$ROOT/dist"
DEB_VERSION="$(echo "$VERSION" | sed 's/^v//')"

if [ ! -f "$DYLIB" ]; then
  echo "[package] 未找到 $DYLIB"
  echo "[package] 请先在 macOS + Xcode 环境执行 make，再运行 make package"
  exit 1
fi
for bin in zip tar ar; do
  command -v "$bin" >/dev/null 2>&1 || {
    echo "[package] 缺少命令：$bin"
    exit 1
  }
done

STAGE="$OUT/deb-root"
rm -rf "$STAGE"
mkdir -p "$STAGE/DEBIAN"
mkdir -p "$STAGE/Library/MobileSubstrate/DynamicLibraries"
mkdir -p "$OUT"

cp "$PKG/DEBIAN/control" "$STAGE/DEBIAN/control"
sed -i '' -e "s/^Version:.*/Version: $DEB_VERSION/" "$STAGE/DEBIAN/control" 2>/dev/null || \
  sed -i -e "s/^Version:.*/Version: $DEB_VERSION/" "$STAGE/DEBIAN/control"
cp "$PKG/Library/MobileSubstrate/DynamicLibraries/antmanor.plist" "$STAGE/Library/MobileSubstrate/DynamicLibraries/antmanor.plist"
cp "$DYLIB" "$STAGE/Library/MobileSubstrate/DynamicLibraries/antmanor.dylib"
chmod 644 "$STAGE/Library/MobileSubstrate/DynamicLibraries/antmanor.dylib"

DEB="$OUT/com.vknote.antmanor_${DEB_VERSION}_iphoneos-arm.deb"
if command -v dpkg-deb >/dev/null 2>&1; then
  dpkg-deb -Zgzip -b "$STAGE" "$DEB"
else
  echo "[package] 未找到 dpkg-deb，使用 ar + tar 生成 deb"
  mkdir -p "$OUT/.deb"
  cp -R "$STAGE/DEBIAN" "$OUT/.deb/DEBIAN"
  cp -R "$STAGE/Library" "$OUT/.deb/Library"
  (cd "$OUT/.deb" && tar -czf ../control.tar.gz DEBIAN)
  (cd "$OUT/.deb" && tar -czf ../data.tar.gz Library)
  echo "2.0" > "$OUT/debian-binary"
  rm -f "$DEB"
  (cd "$OUT" && ar r "$DEB" debian-binary control.tar.gz data.tar.gz)
  rm -rf "$OUT/.deb" "$OUT/control.tar.gz" "$OUT/data.tar.gz" "$OUT/debian-binary"
fi

ZIP="$OUT/AntManorPort-${VERSION}-TrollFools.zip"
rm -f "$ZIP"
(cd "$STAGE" && zip -qry "$ZIP" Library)
cp "$ROOT/config/manor-config.example.json" "$OUT/manor-config.example.json"

if [ ! -f "$DEB" ] || [ ! -f "$ZIP" ]; then
  echo "[package] 打包产物缺失：$DEB 或 $ZIP"
  exit 1
fi

echo "[package] 完成："
echo "  $DEB"
echo "  $ZIP"
echo "[package] 安装后把 manor-config.example.json 复制为 App 沙盒 Documents/AntManor/manor-config.json 并按抓包结果填写。"

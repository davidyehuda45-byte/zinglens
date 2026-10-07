#!/bin/sh
# ZigLens release packaging (Spec Sec.71-73). Usage: ./scripts/release.sh 0.5.0
set -e
VERSION="${1:-0.5.0}"
mkdir -p dist
for t in x86_64-linux aarch64-linux x86_64-macos aarch64-macos x86_64-windows aarch64-windows; do
  echo "== $t"
  zig build -Doptimize=ReleaseSafe -Dtarget="$t" --prefix "dist/ziglens-$t"
  case "$t" in
    *windows) (cd "dist/ziglens-$t/bin" && zip -j "../../ziglens-$t.zip" ziglens.exe) ;;
    *) tar -czf "dist/ziglens-$t.tar.gz" -C "dist/ziglens-$t/bin" ziglens ;;
  esac
done
(cd dist && sha256sum ziglens-*.zip ziglens-*.tar.gz > SHA256SUMS)
echo "Release artifacts in dist/ (version $VERSION)"

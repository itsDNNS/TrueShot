#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION_VALUE="$(tr -d '[:space:]' < VERSION)"
RUN_GATE=1
RUN_WOW_GATE=0

for arg in "$@"; do
    case "$arg" in
        --skip-gate)
            RUN_GATE=0
            ;;
        --wow)
            RUN_WOW_GATE=1
            ;;
        *)
            VERSION_VALUE="$arg"
            ;;
    esac
done

if [[ ! "$VERSION_VALUE" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "Invalid version: $VERSION_VALUE" >&2
    exit 2
fi

if [[ "$RUN_GATE" -eq 1 ]]; then
    if [[ "$RUN_WOW_GATE" -eq 1 ]]; then
        scripts/release_gate.sh --wow
    else
        scripts/release_gate.sh
    fi
fi

if ! command -v zip >/dev/null 2>&1; then
    echo "zip not found" >&2
    exit 127
fi

if ! command -v unzip >/dev/null 2>&1; then
    echo "unzip not found" >&2
    exit 127
fi

DIST_DIR="$ROOT/dist"
STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT

ADDON_DIR="$STAGE_DIR/TrueShot"
mkdir -p "$ADDON_DIR"

cp TrueShot.toc "$ADDON_DIR/"
cp ./*.lua "$ADDON_DIR/"
cp icon.svg LICENSE README.md CHANGELOG.md "$ADDON_DIR/"
cp -R Profiles State "$ADDON_DIR/"

sed "s/@project-version@/$VERSION_VALUE/g" "$ADDON_DIR/TrueShot.toc" > "$ADDON_DIR/TrueShot.toc.tmp"
mv "$ADDON_DIR/TrueShot.toc.tmp" "$ADDON_DIR/TrueShot.toc"

if grep -q "@project-version@" "$ADDON_DIR/TrueShot.toc"; then
    echo "Packaged TOC still contains @project-version@" >&2
    exit 1
fi

if ! grep -q "^## Version: $VERSION_VALUE$" "$ADDON_DIR/TrueShot.toc"; then
    echo "Packaged TOC does not contain expected version $VERSION_VALUE" >&2
    exit 1
fi

if ! grep -q "^## Interface: 120007$" "$ADDON_DIR/TrueShot.toc"; then
    echo "Packaged TOC Interface is not 120007" >&2
    exit 1
fi

if find "$ADDON_DIR" \( -path "*/tests/*" -o -path "*/scripts/*" -o -path "*/.git/*" -o -path "*/tasks/*" -o -path "*/dist/*" \) -print -quit | grep -q .; then
    echo "Packaged addon contains dev-only files" >&2
    exit 1
fi

mkdir -p "$DIST_DIR"
ZIP_PATH="$DIST_DIR/TrueShot-$VERSION_VALUE.zip"
rm -f "$ZIP_PATH"

(cd "$STAGE_DIR" && zip -qr "$ZIP_PATH" TrueShot)

if unzip -Z1 "$ZIP_PATH" | grep -E '/(tests|scripts|\.git|tasks|dist)/' >/dev/null; then
    echo "Zip contains dev-only paths" >&2
    unzip -Z1 "$ZIP_PATH" | grep -E '/(tests|scripts|\.git|tasks|dist)/' >&2
    exit 1
fi

if ! unzip -p "$ZIP_PATH" TrueShot/TrueShot.toc | grep -q "^## Version: $VERSION_VALUE$"; then
    echo "Zip TOC version check failed" >&2
    exit 1
fi

echo "Built $ZIP_PATH"

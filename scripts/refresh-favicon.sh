#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

command -v magick >/dev/null 2>&1 || { echo "error: ImageMagick 7 (magick) is required" >&2; exit 1; }

source_png=public/favicon.png
target_ico=public/favicon.ico

[[ -f $source_png ]] || { echo "error: $source_png not found" >&2; exit 1; }

echo "==> Generating $target_ico from $source_png"
magick "$source_png" -background none -define icon:auto-resize=256,128,64,48,32,16 "$target_ico"

magick identify -format "    %wx%h\n" "$target_ico"

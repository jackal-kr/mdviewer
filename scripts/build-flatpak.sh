#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 JOD
# Build a single-file Flatpak bundle: dist/markdown-viewer_<version>_<arch>.flatpak
set -euo pipefail

cd "$(dirname "$(dirname "$(realpath "$0")")")"

app_id="io.github.jackal_kr.MarkdownViewer"
manifest="flatpak/${app_id}.yml"
version="$(sed -n "s/^[[:space:]]*version:[[:space:]]*'\\([^']*\\)'.*/\\1/p" meson.build | head -n1)"
arch="$(flatpak --default-arch)"
out="dist/markdown-viewer_${version}_${arch}.flatpak"

mkdir -p dist
flatpak-builder --user --install-deps-from=flathub --force-clean \
    --repo=flatpak/repo flatpak/build "$manifest"
flatpak build-bundle --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo \
    flatpak/repo "$out" "$app_id"

echo
echo "Bundle created: $out"
echo "Install with: flatpak install --user $out"

#!/usr/bin/env bash
set -euo pipefail

src_dir="$(realpath "${1:?Missing source directory}")"
build_dir="$(realpath "${2:?Missing build directory}")"

project_name="markdown-viewer"
version="$(sed -n "s/^[[:space:]]*version:[[:space:]]*'\\([^']*\\)'.*/\\1/p" \
    "$src_dir/meson.build" | head -n1)"
version="${version:-0.1.0}"

arch="$(dpkg --print-architecture)"
package="${project_name}_${version}_${arch}.deb"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

command -v dpkg-deb >/dev/null || {
    echo "Missing dpkg-deb. Install it with: sudo apt install dpkg-dev" >&2
    exit 1
}

# Install the Meson install manifest into a temporary package root.
DESTDIR="$stage" meson install -C "$build_dir" --no-rebuild

install -d "$stage/DEBIAN"
cat > "$stage/DEBIAN/control" <<CONTROL
Package: markdown-viewer
Version: ${version}
Section: utils
Priority: optional
Architecture: ${arch}
Maintainer: Markdown Viewer contributors
Description: GTK application for reading Markdown documents
 A lightweight desktop Markdown viewer using GTK 4 and WebKitGTK.
Depends: libgtk-4-1, libwebkitgtk-6.0-4
CONTROL

dpkg-deb --root-owner-group --build "$stage" "$build_dir/$package"
echo
echo "Package created: $build_dir/$package"

#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 JOD
set -Eeuo pipefail

cd "$(dirname "$(dirname "$(realpath "$0")")")"

OLD_ID="io.github.jackal_kr.MarkdownViewer"
HYPHEN_ID="io.github.jackal_kr.MarkdownViewer"
NEW_ID="io.github.jackal_kr.MarkdownViewer"
PACKAGE="markdown-viewer"
BUILD_DIR="builddir"

echo "==> Checking project"
test -f meson.build
test -f src/main.vala
test -f scripts/build-deb.sh

echo "==> Updating application IDs in project text files"
while IFS= read -r -d '' file; do
    sed -i \
        -e "s/${OLD_ID}/${NEW_ID}/g" \
        -e "s/${HYPHEN_ID}/${NEW_ID}/g" \
        -e 's/jackal_kr/jackal_kr/g' \
        "$file"
done < <(
    find . \
        -path './.git' -prune -o \
        -path "./${BUILD_DIR}" -prune -o \
        -path './.venv' -prune -o \
        -type f \( \
            -name '*.vala' -o -name '*.desktop' -o \
            -name '*.svg' -o -name '*.xml' -o \
            -name '*.sh' -o -name '*.ini' -o \
            -name '*.md' -o -name 'meson.build' \
        \) -print0
)

echo "==> Renaming desktop and icon files"
for ext in desktop svg png; do
    old="data/io.github.jackal_kr.MarkdownViewer.${ext}"
    new="data/io.github.jackal_kr.MarkdownViewer.${ext}"
    if [[ -f "$old" ]]; then
        mv "$old" "$new"
    fi

    old="data/icons/hicolor/scalable/apps/io.github.jackal_kr.MarkdownViewer.${ext}"
    new="data/icons/hicolor/scalable/apps/io.github.jackal_kr.MarkdownViewer.${ext}"
    if [[ -f "$old" ]]; then
        mv "$old" "$new"
    fi
done

DESKTOP="data/io.github.jackal_kr.MarkdownViewer.desktop"
ICON="io.github.jackal_kr.MarkdownViewer"

if [[ ! -f "$DESKTOP" ]]; then
    echo "ERROR: Desktop file not found: $DESKTOP" >&2
    exit 1
fi

echo "==> Fixing desktop launcher identity"
if grep -q '^Icon=' "$DESKTOP"; then
    sed -i "s|^Icon=.*|Icon=${ICON}|" "$DESKTOP"
else
    printf '\nIcon=%s\n' "$ICON" >> "$DESKTOP"
fi

if grep -q '^StartupWMClass=' "$DESKTOP"; then
    sed -i "s|^StartupWMClass=.*|StartupWMClass=${ICON}|" "$DESKTOP"
else
    printf 'StartupWMClass=%s\n' "$ICON" >> "$DESKTOP"
fi

# Ensure the desktop file has the correct launcher command.
if grep -q '^Exec=' "$DESKTOP"; then
    sed -i 's|^Exec=.*|Exec=mdviewer %F|' "$DESKTOP"
else
    printf 'Exec=mdviewer %%F\n' >> "$DESKTOP"
fi

echo "==> Checking Meson install rules"
if ! grep -q "install: true" meson.build; then
    echo "WARNING: Verify that the mdviewer executable has install: true in meson.build."
fi

echo "==> Configuring build with Debian prefix /usr"
if [[ -d "$BUILD_DIR" ]]; then
    meson setup "$BUILD_DIR" --reconfigure --prefix=/usr
else
    meson setup "$BUILD_DIR" --prefix=/usr
fi

echo "==> Building application"
meson compile -C "$BUILD_DIR"

echo "==> Building Debian package"
meson compile -C "$BUILD_DIR" package

DEB="$(find "$BUILD_DIR" -maxdepth 1 -type f \
    -name "${PACKAGE}_*_amd64.deb" -print -quit)"

if [[ -z "$DEB" ]]; then
    echo "ERROR: Debian package was not created." >&2
    exit 1
fi

echo "==> Checking package contents"
dpkg-deb -c "$DEB"

echo "==> Removing previously installed package, if present"
if dpkg-query -W -f='${Status}' "$PACKAGE" 2>/dev/null |
    grep -q 'install ok installed'; then
    sudo apt remove -y "$PACKAGE"
fi

echo "==> Installing corrected package"
sudo apt install -y "./$DEB"

echo "==> Refreshing desktop database and icon cache"
sudo update-desktop-database /usr/share/applications || true
sudo gtk-update-icon-cache -f /usr/share/icons/hicolor || true

echo
echo "==> Installed executable"
command -v mdviewer || true

echo
echo "==> Installed desktop entry"
ls -l "/usr/share/applications/${ICON}.desktop"

echo
echo "==> Installed icon"
find /usr/share/icons/hicolor -type f -name "${ICON}.*" -print

echo
echo "Deployment complete. Fully quit Markdown Viewer, then launch it again."

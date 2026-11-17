# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 JOD

project(
  'markdown-viewer',
  'vala',
  version: '0.1.0',
  license: 'GPL-3.0-or-later',
  meson_version: '>= 0.60.0',
)

gtk = dependency('gtk4')
webkit = dependency('webkitgtk-6.0')
cc = meson.get_compiler('c')
math = cc.find_library('m', required: true)
gnome = import('gnome')
adw = dependency('libadwaita-1')

resources = gnome.compile_resources(
  'mdviewer-resources',
  'resources.gresource.xml',
  source_dir: 'resources',
  c_name: 'mdviewer_resources'
)

executable(
  'mdviewer',
  'src/main.vala',
  resources,
  dependencies: [gtk, webkit, adw, math],
  install: true
)

# Application icon and desktop launcher
install_data(
  'data/icons/hicolor/scalable/apps/io.github.jackal_kr.MarkdownViewer.svg',
  install_dir: get_option('datadir') / 'icons/hicolor/scalable/apps',
)

install_data(
  'data/io.github.jackal_kr.MarkdownViewer.desktop',
  install_dir: get_option('datadir') / 'applications',
)

# License texts (GPL for this program, notices for the bundled parser)
install_data(
  'LICENSE',
  'THIRD_PARTY_NOTICES.md',
  install_dir: get_option('datadir') / 'doc' / meson.project_name(),
)

# Build the application
run_target(
  'build',
  command: [
    find_program('meson'),
    'compile',
    '-C',
    meson.current_build_dir(),
  ],
)

# Create a Debian package
run_target(
  'package',
  command: [
    find_program('bash'),
    files('scripts/build-deb.sh'),
    meson.current_source_dir(),
    meson.current_build_dir(),
  ],
)

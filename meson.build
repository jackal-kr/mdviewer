project('markdown-viewer', 'vala', version: '0.1.0', meson_version: '>= 0.60.0')

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

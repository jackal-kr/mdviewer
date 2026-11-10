# Markdown Viewer (bundled markdown-it)

This variant removes the `cmark-gfm` subprocess. The parser JavaScript is embedded into the executable as a GResource, so the built app does not need npm or a separate Markdown renderer at runtime.

## Build on Ubuntu 26.04

Install build tools and the GTK/WebKit development dependencies if they are not already present:

```bash
sudo apt update
sudo apt install build-essential meson ninja-build valac libgtk-4-dev libwebkitgtk-6.0-dev npm
```

From this project directory, fetch the pinned parser source and embed it:

```bash
./fetch-markdown-it.sh
meson setup build
meson compile -C build
./build/mdviewer
```

If `build` already exists, use `meson setup --reconfigure build` instead.

## Notes

- Markdown is rendered by the bundled `markdown-it` parser inside WebKitGTK.
- Raw HTML in Markdown is disabled (`html: false`). Markdown source is base64-encoded before being inserted into the generated document, so its contents cannot break out into script syntax.
- Relative image links resolve against the directory containing the Markdown file.
- Use the hamburger menu for Theme (Dark, Light, System), Zoom (Zoom In, Zoom Out, Reset Zoom), and Quit. The document canvas fills the full WebKit viewport in both themes.
- `markdown-it` is MIT-licensed; its license is distributed in the npm package. Keep the license notice when redistributing the bundled parser.
- This implementation has not been compiled in the assistant's environment. Please run the build and share any compiler output if a correction is needed.

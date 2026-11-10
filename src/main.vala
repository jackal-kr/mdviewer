using GLib;
using Gtk;
using WebKit;

public class MarkdownViewer : Gtk.Application {
    private Gtk.ApplicationWindow? window;
    private WebKit.WebView? web_view;
    private string? current_path;
    private FileMonitor? file_monitor;
    private Cancellable? load_cancellable;
    private uint reload_timeout_id = 0;
    private string? markdown_it_source;
    private string? last_rendered_source;
    private bool dark_theme = true;
    private string theme_mode = "system";
    private string settings_path = "";
    private Gtk.Settings? gtk_settings;
    private bool defer_initial_present = false;
    private Gtk.CssProvider? window_css_provider;

    // Zoom state
    private double current_zoom = 1.0;
    private const double ZOOM_STEP = 0.1;
    private const double ZOOM_MIN = 0.2;
    private const double ZOOM_MAX = 3.0;

    // Workaround for a Vala vapi bug with Widget.add_controller.
    [CCode (cname = "gtk_widget_add_controller", cheader_filename = "gtk/gtk.h")]
    private extern static void widget_add_controller (
        Gtk.Widget widget,
        Gtk.EventController controller
    );

    private const string DOCUMENT_CSS = """
:root { color-scheme: light; --page-bg: #ffffff; --text: #242424; --border: #d0d0d0; --code-bg: #f1f1f1; --link: #0969da; }
:root[data-theme="dark"] { color-scheme: dark; --page-bg: #242424; --text: #eeeeec; --border: #505050; --code-bg: #303030; --link: #78aeed; }
html, body { background-color: var(--page-bg) !important; color: var(--text) !important; min-height: 100%; width: 100%; }
body { font: 16px/1.65 system-ui, sans-serif; margin: 0; padding: 30px 36px 60px; overflow-wrap: anywhere; background: var(--page-bg) !important; color: var(--text) !important; min-height: calc(100vh - 90px); box-sizing: border-box; }
main { max-width: 900px; margin: 0 auto; }
h1,h2,h3,h4,h5,h6 { line-height: 1.25; margin-top: 1.5em; }
h1 { border-bottom: 1px solid var(--border); padding-bottom: .3em; }
pre { padding: 14px 16px; border-radius: 8px; overflow-x: auto; background: var(--code-bg); }
code { font-family: ui-monospace, "Liberation Mono", monospace; font-size: .92em; }
:not(pre) > code { padding: .12em .3em; border-radius: 4px; background: var(--code-bg); }
blockquote { margin-left: 0; padding-left: 1em; border-left: 3px solid var(--border); opacity: .9; }
table { border-collapse: collapse; margin: 1em 0; width: 100%; }
th,td { border: 1px solid var(--border); padding: 6px 10px; }
th { font-weight: bold; }
img { max-width: 100%; height: auto; }
a { color: var(--link); }
hr { border: 0; border-top: 1px solid var(--border); }
""";

    public MarkdownViewer () {
        Object (
            application_id: "io.github.jackal_kr.MarkdownViewer",
            flags: ApplicationFlags.HANDLES_OPEN
        );
    }


    private void load_preferences () {
        string config_dir = Path.build_filename (
            Environment.get_user_config_dir (),
            "markdown-viewer"
        );
        settings_path = Path.build_filename (config_dir, "settings.ini");

        var key_file = new KeyFile ();
        try {
            key_file.load_from_file (settings_path, KeyFileFlags.NONE);
            string saved_mode = key_file.get_string ("Appearance", "theme");
            if (saved_mode == "dark" ||
                saved_mode == "light" ||
                saved_mode == "system") {
                theme_mode = saved_mode;
            }
        } catch (Error e) {
            // Missing or unreadable settings: keep the default.
        }
    }

    private void save_preferences () {
        if (settings_path.length == 0)
            return;

        var key_file = new KeyFile ();
        key_file.set_string ("Appearance", "theme", theme_mode);

        try {
            string? directory = Path.get_dirname (settings_path);
            if (directory != null)
                DirUtils.create_with_parents (directory, 0755);

            string data = key_file.to_data ();
            FileUtils.set_contents (settings_path, data);
        } catch (Error e) {
            warning ("Could not save preferences: %s", e.message);
        }
    }

    protected override void startup () {
        base.startup ();

        load_preferences ();
        gtk_settings = Gtk.Settings.get_default ();
        if (gtk_settings != null) {
            gtk_settings.notify["gtk-application-prefer-dark-theme"].connect (() => {
                if (theme_mode == "system") {
                    update_effective_theme ();
                }
            });
        }

        calculate_effective_theme ();

        try {
            Bytes parser_bytes = resources_lookup_data (
                "/io/github/jackal_kr/MarkdownViewer/markdown-it.min.js",
                ResourceLookupFlags.NONE
            );
            markdown_it_source = (string) parser_bytes.get_data ();
        } catch (Error e) {
            warning ("Could not load bundled markdown-it: %s", e.message);
        }

        var open_action = new SimpleAction ("open", null);
        open_action.activate.connect (() => open_dialog ());
        add_action (open_action);

        var reload_action = new SimpleAction ("reload", null);
        reload_action.activate.connect (() => reload_file ());
        add_action (reload_action);

        var zoom_in_action = new SimpleAction ("zoom-in", null);
        zoom_in_action.activate.connect (() => zoom_in ());
        add_action (zoom_in_action);

        var zoom_out_action = new SimpleAction ("zoom-out", null);
        zoom_out_action.activate.connect (() => zoom_out ());
        add_action (zoom_out_action);

        var zoom_reset_action = new SimpleAction ("zoom-reset", null);
        zoom_reset_action.activate.connect (() => zoom_reset ());
        add_action (zoom_reset_action);

        var theme_action = new SimpleAction.stateful (
            "theme",
            new VariantType ("s"),
            new Variant.string (theme_mode)
        );
        theme_action.activate.connect ((parameter) => {
            if (parameter != null) {
                set_theme_mode (parameter.get_string ());
            }
        });
        add_action (theme_action);

        var quit_action = new SimpleAction ("quit", null);
        quit_action.activate.connect (() => this.quit ());
        add_action (quit_action);

        set_accels_for_action ("app.open", { "<Primary>o" });
        set_accels_for_action ("app.reload", { "<Primary>r" });
        set_accels_for_action (
            "app.zoom-in",
            { "<Primary>bracketright", "<Primary>plus", "<Primary>equal" }
        );
        set_accels_for_action (
            "app.zoom-out",
            { "<Primary>bracketleft", "<Primary>minus" }
        );
        set_accels_for_action ("app.zoom-reset", { "<Primary>0" });
    }

    protected override void activate () {
        ensure_window ();

        if (current_path == null && !defer_initial_present) {
            show_welcome ();
        }

        var win = window;
        if (win != null) {
            win.present ();
        }
    }

    protected override void open (File[] files, string hint) {
        bool new_window = window == null;
        defer_initial_present = new_window && files.length > 0;
        ensure_window ();

        if (files.length > 0) {
            load_path_async.begin (files[0].get_path ());
        } else {
            defer_initial_present = false;
            var win = window;
            if (win != null) {
                win.present ();
            }
        }
    }

    protected override void shutdown () {
        if (reload_timeout_id != 0) {
            Source.remove (reload_timeout_id);
            reload_timeout_id = 0;
        }

        if (file_monitor != null) {
            file_monitor.cancel ();
            file_monitor = null;
        }

        if (load_cancellable != null) {
            load_cancellable.cancel ();
            load_cancellable = null;
        }

        base.shutdown ();
    }

    private void ensure_window () {
        if (window != null) {
            return;
        }

        var win = new Gtk.ApplicationWindow (this);
        win.add_css_class ("markdown-viewer-window");
        install_window_css ();
        win.add_css_class (
            dark_theme ? "markdown-viewer-dark" : "markdown-viewer-light"
        );
        win.set_default_size (1000, 760);
        win.set_title ("Markdown Viewer");
        window = win;

        var header = new Gtk.HeaderBar ();
        win.set_titlebar (header);

        var open_button = new Gtk.Button.from_icon_name (
            "document-open-symbolic"
        );
        open_button.set_tooltip_text ("Open Markdown file (Ctrl+O)");
        open_button.clicked.connect (() => open_dialog ());
        header.pack_start (open_button);

        // Application menu:
        // Reset Zoom, separator, Theme submenu, separator, Quit.
        var menu = new GLib.Menu ();

        var reset_section = new GLib.Menu ();
        reset_section.append ("Reset Zoom", "app.zoom-reset");
        menu.append_section (null, reset_section);

        var theme_menu = new GLib.Menu ();
        theme_menu.append ("Dark", "app.theme::dark");
        theme_menu.append ("Light", "app.theme::light");
        theme_menu.append ("System", "app.theme::system");

        var theme_section = new GLib.Menu ();
        theme_section.append_submenu ("Theme", theme_menu);
        menu.append_section (null, theme_section);

        var quit_section = new GLib.Menu ();
        quit_section.append ("Quit", "app.quit");
        menu.append_section (null, quit_section);

        var menu_button = new Gtk.MenuButton ();
        menu_button.set_icon_name ("open-menu-symbolic");
        menu_button.set_tooltip_text ("Application menu");
        menu_button.set_menu_model (menu);
        header.pack_end (menu_button);

        // Reload button.
        var reload_button = new Gtk.Button.from_icon_name (
            "view-refresh-symbolic"
        );
        reload_button.set_tooltip_text ("Reload file (Ctrl+R)");
        reload_button.clicked.connect (() => reload_file ());
        header.pack_end (reload_button);

        // Zoom buttons to the left of Reload, with 12 px separation.
        var zoom_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);

        var zoom_in_button = new Gtk.Button.from_icon_name (
            "zoom-in-symbolic"
        );
        zoom_in_button.set_tooltip_text ("Zoom In (Ctrl++)");
        zoom_in_button.clicked.connect (() => zoom_in ());
        zoom_box.append (zoom_in_button);

        var zoom_out_button = new Gtk.Button.from_icon_name (
            "zoom-out-symbolic"
        );
        zoom_out_button.set_tooltip_text ("Zoom Out (Ctrl+-)");
        zoom_out_button.clicked.connect (() => zoom_out ());
        zoom_box.append (zoom_out_button);

        zoom_box.set_margin_end (12);
        header.pack_end (zoom_box);

        var view = new WebKit.WebView ();
        view.get_settings ().enable_javascript = true;

        Gdk.RGBA initial_background = Gdk.RGBA ();
        initial_background.parse (dark_theme ? "#242424" : "#ffffff");
        view.set_background_color (initial_background);

        view.set_hexpand (true);
        view.set_vexpand (true);
        win.set_child (view);
        web_view = view;

        view.load_changed.connect ((event) => {
            if (event == WebKit.LoadEvent.FINISHED && defer_initial_present) {
                defer_initial_present = false;
                var ready_window = window;
                if (ready_window != null) {
                    ready_window.present ();
                }
            }
        });

        update_effective_theme ();

        // Ctrl + mouse wheel zoom.
        var scroll_controller = new Gtk.EventControllerScroll (
            Gtk.EventControllerScrollFlags.VERTICAL
        );

        scroll_controller.scroll.connect ((dx, dy) => {
            var state = scroll_controller.get_current_event_state ();

            if ((state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                if (dy < 0) {
                    zoom_in ();
                } else if (dy > 0) {
                    zoom_out ();
                }
                return true;
            }

            return false;
        });

        widget_add_controller (view, scroll_controller);
    }

    private void zoom_in () {
        change_zoom (ZOOM_STEP);
    }

    private void zoom_out () {
        change_zoom (-ZOOM_STEP);
    }

    private void change_zoom (double delta) {
        int tenths = (int) Math.round ((current_zoom + delta) * 10.0);
        int min_tenths = (int) Math.round (ZOOM_MIN * 10.0);
        int max_tenths = (int) Math.round (ZOOM_MAX * 10.0);

        if (tenths < min_tenths) {
            tenths = min_tenths;
        } else if (tenths > max_tenths) {
            tenths = max_tenths;
        }

        current_zoom = tenths / 10.0;
        apply_zoom ();
    }

    private void zoom_reset () {
        current_zoom = 1.0;
        apply_zoom ();
    }

    private void apply_zoom () {
        var view = web_view;
        if (view != null) {
            view.set_zoom_level (current_zoom);
        }
    }

    private void show_welcome () {
        var view = web_view;
        if (view == null) {
            return;
        }

        string html = """
<!doctype html>
<html lang="en" data-theme="THEME_MODE">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
:root { color-scheme: light; --page-bg: #fff; --text: #242424; --border: #d0d0d0; --code-bg: #f1f1f1; }
:root[data-theme="dark"] { color-scheme: dark; --page-bg: #1e1e1e; --text: #dedede; --border: #454545; --code-bg: #2b2b2b; }
html, body { background-color: var(--page-bg) !important; color: var(--text) !important; min-height: 100%; width: 100%; }
body { font: 16px/1.65 system-ui, sans-serif; margin: 0; padding: 30px 36px 60px; box-sizing: border-box; background: var(--page-bg) !important; color: var(--text) !important; }
body > * { max-width: 900px; margin-left: auto; margin-right: auto; }
h1 { line-height: 1.25; border-bottom: 1px solid var(--border); padding-bottom: .3em; }
code { background: var(--code-bg); padding: .12em .3em; border-radius: 4px; }
p { opacity: .85; }
</style>
</head>
<body>
<h1>Markdown Viewer</h1>
<p>Open a <code>.md</code> file to read it here.</p>
<p>Use <strong>Ctrl+O</strong> to open a file and <strong>Ctrl+R</strong> to reload it.</p>
<p>Use <strong>Ctrl+Scroll</strong>, <strong>Ctrl+]</strong> / <strong>Ctrl+[</strong>, or <strong>Ctrl++</strong> / <strong>Ctrl+-</strong> to zoom.</p>
</body>
</html>
""";

        view.load_html (
            html.replace ("THEME_MODE", dark_theme ? "dark" : "light"),
            "file:///"
        );
    }

    private void set_theme_mode (string mode) {
        if (mode != "dark" && mode != "light" && mode != "system") {
            return;
        }

        theme_mode = mode;
        save_preferences ();

        var action = lookup_action ("theme") as SimpleAction;
        if (action != null) {
            action.set_state (new Variant.string (theme_mode));
        }

        update_effective_theme ();
    }

    private void calculate_effective_theme () {
        bool new_dark_theme;

        if (theme_mode == "dark") {
            new_dark_theme = true;
        } else if (theme_mode == "light") {
            new_dark_theme = false;
        } else {
            var settings = gtk_settings ?? Gtk.Settings.get_default ();
            new_dark_theme = settings != null && (
                settings.gtk_application_prefer_dark_theme ||
                (
                    settings.gtk_theme_name != null &&
                    settings.gtk_theme_name.down ().contains ("dark")
                )
            );
        }

        dark_theme = new_dark_theme;

        Gdk.RGBA color = Gdk.RGBA ();
        color.parse (dark_theme ? "#242424" : "#ffffff");

        var view = web_view;
        if (view != null) {
            view.set_background_color (color);
        }

        var win = window;
        if (win != null) {
            win.remove_css_class (
                dark_theme ? "markdown-viewer-light" : "markdown-viewer-dark"
            );
            win.add_css_class (
                dark_theme ? "markdown-viewer-dark" : "markdown-viewer-light"
            );
        }
    }

    private void update_effective_theme () {
        bool previous_dark_theme = dark_theme;
        calculate_effective_theme ();

        if (previous_dark_theme == dark_theme) {
            return;
        }

        if (current_path != null) {
            last_rendered_source = null;
            load_path_async.begin (current_path);
        } else if (!defer_initial_present) {
            show_welcome ();
        }
    }

    private void install_window_css () {
        if (window_css_provider != null) {
            return;
        }

        var display = Gdk.Display.get_default ();
        if (display == null) {
            return;
        }

        var provider = new Gtk.CssProvider ();

        string css = """
window.markdown-viewer-window {
    background-color: #ffffff;
}
window.markdown-viewer-window.markdown-viewer-dark {
    background-color: #242424;
}
window.markdown-viewer-window.markdown-viewer-light {
    background-color: #ffffff;
}
""";

        // GTK4 expects the CSS data as bytes.
        provider.load_from_data ((uint8[]) css.data);

        Gtk.StyleContext.add_provider_for_display (
            display,
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );

        window_css_provider = provider;
    }

    private void open_dialog () {
        var dialog = new Gtk.FileDialog ();
        dialog.set_title ("Open Markdown file");
        dialog.set_modal (true);

        var markdown_filter = new Gtk.FileFilter ();
        markdown_filter.name = "Markdown files";
        markdown_filter.add_pattern ("*.md");
        markdown_filter.add_pattern ("*.markdown");
        markdown_filter.add_pattern ("*.mdown");

        var all_filter = new Gtk.FileFilter ();
        all_filter.name = "All files";
        all_filter.add_pattern ("*");

        var filters = new GLib.ListStore (typeof (Gtk.FileFilter));
        filters.append (markdown_filter);
        filters.append (all_filter);
        dialog.set_filters (filters);
        dialog.set_default_filter (markdown_filter);

        dialog.open.begin (window, null, (obj, res) => {
            try {
                var file = dialog.open.end (res);
                if (file != null) {
                    load_path_async.begin (file.get_path ());
                }
            } catch (Gtk.DialogError e) {
                // The user dismissed the dialog.
            } catch (Error e) {
                show_error (e.message);
            }
        });
    }

    private string build_document (string markdown_source) throws Error {
        string? parser_js = markdown_it_source;

        if (parser_js == null || parser_js.length == 0) {
            throw new IOError.NOT_FOUND (
                "The bundled markdown-it parser could not be loaded. Rebuild the app after running ./fetch-markdown-it.sh."
            );
        }

        // Base64 keeps Markdown data out of JavaScript/HTML syntax.
        string encoded_source = Base64.encode (
            (uint8[]) markdown_source.data
        );

        string html = """
<!doctype html>
<html lang="en" data-theme="THEME_MODE">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
""" + DOCUMENT_CSS + """
</style>
<script>
""" + parser_js + """
</script>
</head>
<body>
<main id="markdown-content" aria-label="Markdown document"></main>
<script>
(() => {
  'use strict';
  const parser = window.markdownit({
    html: false,
    linkify: true,
    typographer: false,
    breaks: false
  });
  const encoded = '""" + encoded_source + """';
  const bytes = Uint8Array.from(atob(encoded), c => c.charCodeAt(0));
  const markdown = new TextDecoder('utf-8').decode(bytes);
  document.getElementById('markdown-content').innerHTML = parser.render(markdown);
})();
</script>
</body>
</html>
""";

        return html.replace (
            "THEME_MODE",
            dark_theme ? "dark" : "light"
        );
    }

    private async void load_path_async (string? path) {
        if (path == null || path.length == 0) {
            return;
        }

        if (load_cancellable != null) {
            load_cancellable.cancel ();
        }

        load_cancellable = new Cancellable ();
        var cancellable = load_cancellable;

        try {
            var file = File.new_for_path (path);
            uint8[] contents;
            yield file.load_contents_async (cancellable, out contents, null);

            if (cancellable.is_cancelled ()) {
                return;
            }

            string source = (string) contents;
            var win = window;
            var view = web_view;

            if (win == null || view == null) {
                return;
            }

            bool unchanged =
                current_path == path && last_rendered_source == source;

            if (!unchanged) {
                string html = build_document (source);

                if (cancellable.is_cancelled ()) {
                    return;
                }

                view.load_html (
                    html,
                    File.new_for_path (Path.get_dirname (path)).get_uri () + "/"
                );

                last_rendered_source = source;
            }

            current_path = path;
            win.set_title (
                "%s — Markdown Viewer".printf (Path.get_basename (path))
            );
            setup_file_monitor (path);
        } catch (Error e) {
            if (!(e is IOError.CANCELLED)) {
                if (defer_initial_present) {
                    defer_initial_present = false;
                    var failed_window = window;
                    if (failed_window != null) {
                        failed_window.present ();
                    }
                }

                show_error (e.message);
            }
        }
    }

    private void setup_file_monitor (string path) {
        if (file_monitor != null) {
            file_monitor.cancel ();
            file_monitor = null;
        }

        try {
            var directory = File.new_for_path (Path.get_dirname (path));
            file_monitor = directory.monitor_directory (
                FileMonitorFlags.WATCH_MOVES,
                null
            );

            string watched_path = File.new_for_path (path).get_path () ?? path;

            file_monitor.changed.connect (
                (changed_file, other_file, event_type) => {
                    string? changed_path = changed_file.get_path ();
                    string? other_path = other_file != null
                        ? other_file.get_path ()
                        : null;

                    bool is_target =
                        changed_path == watched_path ||
                        other_path == watched_path;

                    if (is_target && (
                        event_type == FileMonitorEvent.CHANGED ||
                        event_type == FileMonitorEvent.CHANGES_DONE_HINT ||
                        event_type == FileMonitorEvent.CREATED ||
                        event_type == FileMonitorEvent.MOVED_IN ||
                        event_type == FileMonitorEvent.RENAMED ||
                        event_type == FileMonitorEvent.DELETED
                    )) {
                        schedule_reload ();
                    }
                }
            );
        } catch (Error e) {
            warning ("Could not monitor file: %s", e.message);
        }
    }

    private void schedule_reload () {
        if (reload_timeout_id != 0) {
            Source.remove (reload_timeout_id);
        }

        reload_timeout_id = Timeout.add (300, () => {
            reload_timeout_id = 0;

            if (current_path != null) {
                load_path_async.begin (current_path);
            }

            return Source.REMOVE;
        });
    }

    private void reload_file () {
        if (current_path != null) {
            load_path_async.begin (current_path);
        }
    }

    private void show_error (string message) {
        var dialog = new Gtk.AlertDialog (message);
        dialog.set_detail ("Please check the file and try again.");

        var win = window;
        if (win != null) {
            dialog.show (win);
        }
    }

    public static int main (string[] args) {
        var app = new MarkdownViewer ();
        return app.run (args);
    }
}
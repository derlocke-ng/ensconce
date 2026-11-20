"""The dialogs: export this computer, an export's details, restore.

Widths from ui-rules 7: 560 for a form, 720 for details.
"""

from __future__ import annotations

from gi.repository import Adw, GLib, Gtk

from ..core import exports

MAX_ITEMS = 200  # rows under one part in the details; the rest is counted


def _esc(text: str) -> str:
    return GLib.markup_escape_text(text)


def _shell(title: str, subtitle: str, width: int, page: Adw.PreferencesPage, buttons: list) -> Adw.Dialog:
    """A dialog: header bar, the page, a row of buttons at the bottom."""
    dialog = Adw.Dialog(content_width=width, content_height=640)
    view = Adw.ToolbarView()
    bar = Adw.HeaderBar()
    bar.set_title_widget(Adw.WindowTitle(title=title, subtitle=subtitle))
    view.add_top_bar(bar)
    view.set_content(page)
    if buttons:
        row = Gtk.Box(spacing=12, margin_top=12, margin_bottom=12, margin_start=12, margin_end=12)
        for widget in buttons:
            row.append(widget)
        view.add_bottom_bar(row)
    dialog.set_child(view)
    return dialog


def _button(label: str, css: str | None = None, *, start: bool = False) -> Gtk.Button:
    button = Gtk.Button(label=label, hexpand=start, halign=Gtk.Align.START if start else Gtk.Align.END)
    if css:
        button.add_css_class(css)
    return button


def _part_subtitle(part: exports.Part, base: str = "") -> str:
    bits = [base] if base else []
    if part.note:
        bits.append(part.note)
    if part.root:
        bits.append("asks for your password")
    return " · ".join(bits)


# ── Export This Computer ──────────────────────────────────────────────────
class ExportDialog:
    def __init__(self, window) -> None:
        self.window = window
        page = Adw.PreferencesPage()

        where = Adw.PreferencesGroup()
        dest = Adw.ActionRow(
            title="Into",
            subtitle=_esc(f"{window.folder}/{exports.this_host()}/"),
            subtitle_selectable=True,
        )
        dest.add_prefix(Gtk.Image(icon_name="folder-symbolic"))
        where.add(dest)
        page.add(where)

        chosen = set(window.settings["export_parts"]) or set(exports.DEFAULT_PARTS)
        files, size = exports.my_fonts()
        group = Adw.PreferencesGroup(
            title="What to Export",
            description="Parts marked private may hold your Nextcloud server, certificates "
            "or SSH paths. Everybody who can read the exports folder sees them.",
        )
        self.switches: dict[str, Adw.SwitchRow] = {}
        for part in exports.PARTS:
            sub = "private" if part.private else ""
            note = part.note
            if part.key == "fonts":
                note = (
                    f"{files} files, {exports.size_text(size)} in your font folders"
                    if files
                    else "you have no fonts of your own"
                )
            row = Adw.SwitchRow(title=part.title, subtitle=_esc(" · ".join(filter(None, [sub, note]))))
            row.add_prefix(Gtk.Image(icon_name=part.icon))
            row.set_active(part.key in chosen)
            row.connect("notify::active", lambda *_a: self._check())
            self.switches[part.key] = row
            group.add(row)
        page.add(group)

        self.go = _button("Export", "suggested-action")
        self.go.connect("clicked", self._on_export)
        self.dialog = _shell(
            "Export This Computer", exports.this_host(), 560, page, [Gtk.Box(hexpand=True), self.go]
        )
        self._check()

    def _check(self) -> None:
        self.go.set_sensitive(any(r.get_active() for r in self.switches.values()))

    def _on_export(self, *_a) -> None:
        parts = [k for k, r in self.switches.items() if r.get_active()]
        self.window.settings.set("export_parts", [] if parts == exports.DEFAULT_PARTS else parts)
        self.dialog.close()
        self.window.run_export(parts)

    def present(self, parent) -> None:
        self.dialog.present(parent)


# ── an export's details ───────────────────────────────────────────────────
class Details:
    def __init__(self, window, export: exports.Export, contents: list[exports.Content]) -> None:
        self.window, self.export = window, export
        page = Adw.PreferencesPage()

        about = Adw.PreferencesGroup()
        who = export.host + (f" ({export.user})" if export.user else "")
        for title, value in (
            ("Computer", who + (" — this computer" if export.mine else "")),
            ("Exported", export.when),
            ("System", export.image),
            ("Ensconce", export.version),
        ):
            if value:
                about.add(Adw.ActionRow(title=title, subtitle=_esc(value), subtitle_selectable=True))
        folder = Adw.ActionRow(title="Folder", subtitle=_esc(str(export.path)), subtitle_selectable=True)
        open_button = Gtk.Button(
            icon_name="folder-open-symbolic", valign=Gtk.Align.CENTER, tooltip_text="Open Folder"
        )
        open_button.add_css_class("flat")
        open_button.connect("clicked", lambda *_a: window.open_folder(export.path))
        folder.add_suffix(open_button)
        about.add(folder)
        page.add(about)

        inside = Adw.PreferencesGroup(title="What Is in It")
        if not contents:
            inside.set_description("Nothing but settings.sh: this export would change nothing.")
        for c in contents:
            row = Adw.ExpanderRow(title=c.part.title, subtitle=_esc(_part_subtitle(c.part, c.summary)))
            row.add_prefix(Gtk.Image(icon_name=c.part.icon))
            for item in c.items[:MAX_ITEMS]:
                line = Adw.ActionRow(title=_esc(item), title_selectable=True)
                line.add_css_class("property")
                row.add_row(line)
            if len(c.items) > MAX_ITEMS:
                row.add_row(Adw.ActionRow(title=f"… and {len(c.items) - MAX_ITEMS} more"))
            inside.add(row)
        page.add(inside)

        delete = _button("Delete", "destructive-action", start=True)
        delete.connect("clicked", self._on_delete)
        use = _button("Use as Setup Config")
        use.set_tooltip_text("Make this export the config the ensconce command uses")
        use.connect("clicked", self._on_use)
        restore = _button("Restore…", "suggested-action")
        restore.set_sensitive(bool(contents))
        restore.connect("clicked", self._on_restore)
        self.contents = contents
        self.dialog = _shell(export.host, export.when, 720, page, [delete, use, restore])

    def present(self, parent) -> None:
        self.dialog.present(parent)

    def _on_restore(self, *_a) -> None:
        self.dialog.close()
        Restore(self.window, self.export, self.contents).present(self.window)

    def _on_use(self, *_a) -> None:
        alert = Adw.AlertDialog(
            heading="Use This Export as Your Setup Config?",
            body="The `ensconce` command then applies this export when you run it. "
            "Your config as it is now is copied to ~/.local/state/ensconce first. "
            "Of settings.sh, only the settings ensconce knows are taken over.",
        )
        alert.add_response("cancel", "Cancel")
        alert.add_response("use", "Use This Export")
        alert.set_response_appearance("use", Adw.ResponseAppearance.SUGGESTED)
        alert.set_default_response("cancel")

        def answered(_d, response) -> None:
            if response == "use":
                self.dialog.close()
                self.window.use_as_config(self.export)

        alert.connect("response", answered)
        alert.present(self.dialog)

    def _on_delete(self, *_a) -> None:
        alert = Adw.AlertDialog(
            heading="Delete This Export?",
            body=f"The export of {self.export.host} from {self.export.when} is deleted from the "
            "exports folder — and so from every computer that syncs that folder.",
        )
        alert.add_response("cancel", "Cancel")
        alert.add_response("delete", "Delete")
        alert.set_response_appearance("delete", Adw.ResponseAppearance.DESTRUCTIVE)
        alert.set_default_response("cancel")

        def answered(_d, response) -> None:
            if response == "delete":
                self.dialog.close()
                self.window.delete(self.export)

        alert.connect("response", answered)
        alert.present(self.dialog)


# ── Restore ───────────────────────────────────────────────────────────────
class Restore:
    def __init__(self, window, export: exports.Export, contents: list[exports.Content]) -> None:
        self.window, self.export = window, export
        page = Adw.PreferencesPage()

        group = Adw.PreferencesGroup(
            title="What to Apply",
            description="Each part is applied by its ensconce step. "
            "What this computer has already is left as it is.",
        )
        self.switches: dict[str, Adw.SwitchRow] = {}
        for c in contents:
            row = Adw.SwitchRow(title=c.part.title, subtitle=_esc(_part_subtitle(c.part, c.summary)))
            row.add_prefix(Gtk.Image(icon_name=c.part.icon))
            row.set_active(True)
            row.connect("notify::active", lambda *_a: self._check())
            self.switches[c.part.key] = row
            group.add(row)
        page.add(group)

        before = Adw.PreferencesGroup(title="Before")
        self.first = Adw.SwitchRow(
            title="Export This Computer First",
            subtitle="so you can go back to how it is now",
            active=window.settings["export_first"],
        )
        self.first.connect(
            "notify::active", lambda r, *_a: window.settings.set("export_first", r.get_active())
        )
        self.dry = Adw.SwitchRow(title="Dry Run", subtitle="only show in the output what would change")
        self.dry.connect("notify::active", lambda *_a: self._check())
        before.add(self.first)
        before.add(self.dry)
        page.add(before)

        self.go = _button("Restore", "suggested-action")
        self.go.connect("clicked", self._on_go)
        self.dialog = _shell(
            "Restore", f"from {export.host}, {export.when}", 560, page, [Gtk.Box(hexpand=True), self.go]
        )
        self._check()

    def _check(self) -> None:
        self.go.set_sensitive(any(r.get_active() for r in self.switches.values()))
        self.go.set_label("Try" if self.dry.get_active() else "Restore")
        self.first.set_sensitive(not self.dry.get_active())

    def _on_go(self, *_a) -> None:
        steps = [k for k, r in self.switches.items() if r.get_active()]
        self.dialog.close()
        self.window.run_restore(self.export, steps, self.first.get_active(), self.dry.get_active())

    def present(self, parent) -> None:
        self.dialog.present(parent)

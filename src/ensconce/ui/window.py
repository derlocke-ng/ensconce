"""The main window: the exports, grouped by the computer that made them.

The kit's: header bar, menu, About, Preferences, window size, job strip.
Ensconce's: the list of exports, the export, details and restore dialogs,
its group in Preferences. Exporting and restoring run the `ensconce`
command in the job strip, so the app and the command cannot disagree.
"""

from __future__ import annotations

from datetime import datetime
from pathlib import Path

from gi.repository import Adw, Gio, GLib, Gtk

from .. import INFO
from ..core import cli, exports
from ..kit import geometry, header, worker
from ..kit.progress import JobArea
from ..kit.settings import Store
from . import dialogs, prefs

CONTENT_WIDTH = 760  # the page's column; Adw.PreferencesPage would cap it at 600

DEFAULTS = {
    "exports_folder": "",  # "" = ~/Ensconce
    "export_parts": [],  # what the export dialog had on last time; [] = all
    "export_first": True,  # restore: export this computer first
}


class Window(Adw.ApplicationWindow):
    def __init__(self, **kwargs) -> None:
        super().__init__(title=INFO.name, **kwargs)
        self.settings = Store(INFO, DEFAULTS)
        geometry.restore(self, INFO)
        self._exports: list[exports.Export] = []
        self._monitor = None
        self._pending = 0
        self._build()
        self.connect("notify::is-active", self._on_active)
        self.refresh()

    # ── the exports folder ────────────────────────────────────────────────
    @property
    def folder(self) -> Path:
        chosen = self.settings["exports_folder"]
        return Path(chosen).expanduser() if chosen else exports.default_folder()

    def set_folder(self, path: Path) -> None:
        self.settings.set("exports_folder", str(path))
        self.refresh()

    # ── layout ────────────────────────────────────────────────────────────
    def _build(self) -> None:
        for name, callback in (
            ("open-exports", lambda: self.open_folder(self.folder)),
            ("open-config", self._open_config),
        ):
            action = Gio.SimpleAction.new(name, None)
            action.connect("activate", lambda *_a, c=callback: c())
            self.add_action(action)

        self.jobs = JobArea(self.settings)
        self.header = header.build(
            self,
            INFO,
            main=("Export This Computer", "list-add-symbolic", self.new_export),
            on_refresh=self.refresh,
            on_preferences=lambda: prefs.show(self),
            menu_actions=[
                ("Open Exports Folder", "win.open-exports"),
                ("Open Setup Config Folder", "win.open-config"),
            ],
            extra_end=[self.jobs.output_button],
        )

        self.banner = Adw.Banner()
        self.banner.connect("button-clicked", lambda *_a: prefs.choose_folder(self))

        self._groups = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=24)
        page = Gtk.Box(
            orientation=Gtk.Orientation.VERTICAL,
            spacing=24,
            margin_top=24,
            margin_bottom=24,
            margin_start=12,
            margin_end=12,
        )
        self._where = Gtk.Label(xalign=0, wrap=True)
        self._where.add_css_class("dim-label")
        page.append(self._where)
        page.append(self._groups)
        clamp = Adw.Clamp(child=page, maximum_size=CONTENT_WIDTH, tightening_threshold=CONTENT_WIDTH - 120)
        scroll = Gtk.ScrolledWindow(child=clamp, vexpand=True)
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)

        self.empty = Adw.StatusPage(
            icon_name=INFO.app_id,
            title="No Exports Yet",
            description="An export holds this computer's setup: its apps, packages, "
            "desktop settings and more. Keep the exports folder in Nextcloud, and "
            "your other computers can restore from it.",
        )
        add = Gtk.Button(label="Export This Computer", halign=Gtk.Align.CENTER)
        add.add_css_class("pill")
        add.add_css_class("suggested-action")
        add.connect("clicked", lambda *_a: self.new_export())
        self.empty.set_child(add)

        self.stack = Gtk.Stack(vexpand=True)
        self.stack.add_named(scroll, "list")
        self.stack.add_named(self.empty, "empty")

        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        body.append(self.banner)
        body.append(self.stack)
        body.append(self.jobs)
        self.toasts = Adw.ToastOverlay(child=body)
        view = Adw.ToolbarView(content=self.toasts)
        view.add_top_bar(self.header)
        self.set_content(view)

    def toast(self, text: str) -> None:
        self.toasts.add_toast(Adw.Toast(title=GLib.markup_escape_text(text), timeout=5))

    def open_folder(self, path: Path) -> None:
        path.mkdir(parents=True, exist_ok=True)
        Gio.AppInfo.launch_default_for_uri(GLib.filename_to_uri(str(path), None), None)

    def _open_config(self) -> None:
        def done(path) -> None:
            if path:
                self.open_folder(path)
            else:
                self.toast("ensconce has no setup config yet")

        worker.run(cli.config_dir, done)

    # ── refresh ───────────────────────────────────────────────────────────
    def _on_active(self, *_a) -> None:
        # exports from the other computers arrive while the window is away
        if self.is_active() and not self.jobs.busy:
            self.refresh()

    def _watch(self) -> None:
        if self._monitor is not None:
            self._monitor.cancel()
            self._monitor = None
        if self.folder.is_dir():
            try:
                self._monitor = Gio.File.new_for_path(str(self.folder)).monitor_directory(
                    Gio.FileMonitorFlags.WATCH_MOVES, None
                )
                self._monitor.connect("changed", lambda *_a: self._soon())
            except GLib.Error:
                self._monitor = None

    def _soon(self) -> None:
        # a sync writes many files at once: one refresh after it settles
        self._pending += 1
        n = self._pending

        def go() -> bool:
            if n == self._pending and not self.jobs.busy:
                self.refresh()
            return GLib.SOURCE_REMOVE

        GLib.timeout_add(1200, go)

    def refresh(self) -> None:
        folder = self.folder

        def work():
            found = exports.scan(folder)
            return found, {e.path: e.contents() for e in found}

        worker.run(work, lambda result: self._populate(folder, *result))

    def _populate(self, folder: Path, found: list, contents: dict) -> None:
        self._exports = found
        self._contents = contents
        self._watch()
        if not cli.available():
            self.banner.set_title("The ensconce command is missing — reinstall ensconce")
            self.banner.set_button_label(None)
            self.banner.set_revealed(True)
        elif self.settings["exports_folder"] and not folder.is_dir():
            self.banner.set_title(f"The exports folder {folder} is not there")
            self.banner.set_button_label("Choose Folder")
            self.banner.set_revealed(True)
        else:
            self.banner.set_revealed(False)

        self._where.set_label(f"Exports in {folder}")
        child = self._groups.get_first_child()
        while child:
            nxt = child.get_next_sibling()
            self._groups.remove(child)
            child = nxt

        hosts: dict[str, list] = {}
        for e in found:
            hosts.setdefault(e.host, []).append(e)
        for host, items in hosts.items():
            mine = items[0].mine
            group = Adw.PreferencesGroup(
                title=GLib.markup_escape_text(host),
                description="This computer" if mine else None,
            )
            for e in items:
                group.add(self._row(e, contents[e.path]))
            self._groups.append(group)

        n, m = len(found), len(hosts)
        self.header.kit_title.set_subtitle(
            f"{n} export{'s' if n != 1 else ''} from {m} computer{'s' if m != 1 else ''}" if n else ""
        )
        self.stack.set_visible_child_name("list" if found else "empty")

    def _row(self, e: exports.Export, contents: list) -> Adw.ActionRow:
        summary = " · ".join(c.summary.split(",")[0] for c in contents[:4])
        if len(contents) > 4:
            summary += f" · {len(contents) - 4} more"
        row = Adw.ActionRow(
            title=GLib.markup_escape_text(e.when),
            subtitle=GLib.markup_escape_text(summary or "nothing in it but settings.sh"),
            activatable=True,
        )
        row.add_prefix(Gtk.Image(icon_name="folder-symbolic"))
        row.add_suffix(Gtk.Image(icon_name="go-next-symbolic"))
        row.connect("activated", lambda *_a: dialogs.Details(self, e, contents).present(self))
        return row

    # ── jobs ──────────────────────────────────────────────────────────────
    def _free(self) -> bool:
        if self.jobs.busy:
            self.toast("Wait until the running job is done")
            return False
        return True

    def new_export(self) -> None:
        if self._free():
            dialogs.ExportDialog(self).present(self)

    def run_export(self, parts: list[str], then=None) -> None:
        """Export this computer into the exports folder. then(ok) runs after."""
        if then is None and not self._free():
            return
        partial, final = exports.new_export_dir(self.folder)
        try:
            partial.parent.mkdir(parents=True, exist_ok=True)
        except OSError as exc:
            self.toast(f"Cannot write to {self.folder}: {exc.strerror}")
            return
        every = len(parts) in (0, len(exports.PARTS))

        def done(rc: int) -> None:
            ok = rc == 0 and (partial / "settings.sh").is_file()
            if ok:
                try:
                    exports.finish(partial, final)
                except OSError as exc:
                    ok = False
                    self.toast(f"Export not saved: {exc.strerror}")
            else:
                exports.discard(partial)
            if then is None:
                self.toast(
                    f"Exported to {final.parent.name}/{final.name}"
                    if ok
                    else "Export failed — see the output"
                )
            self.refresh()
            if then is not None:
                then(ok)

        self.jobs.run(
            "Export This Computer",
            cli.export_argv(partial, [] if every else parts),
            on_done=done,
        )

    def run_restore(self, e: exports.Export, steps: list[str], export_first: bool, dry_run: bool) -> None:
        if not self._free():
            return
        stamp = datetime.now().strftime("%Y-%m-%d_%H%M%S")
        config = cli.state_dir() / "restore" / f"{e.host}-{stamp}"
        try:
            config.parent.mkdir(parents=True, exist_ok=True)
            exports.copy_as_config(e.path, config)
        except OSError as exc:
            self.toast(f"Cannot read the export: {exc.strerror or exc}")
            return
        label = f"{'Try' if dry_run else 'Restore'} from {e.host}"

        def done(rc: int) -> None:
            if dry_run:
                self.toast(
                    "Dry run done — the output shows what would change"
                    if rc == 0
                    else "Dry run failed — see the output"
                )
                self.jobs.output_button.set_active(True)
            elif rc == 0:
                n = len(steps)
                self.toast(f"Restored {n} part{'s' if n != 1 else ''} from {e.host}")
            else:
                self.toast("Restore stopped — see the output")

        def go(ok: bool = True) -> None:
            if not ok:
                self.toast("Export failed, nothing restored — see the output")
                return
            self.jobs.run(
                label,
                cli.restore_argv(config, steps, dry_run),
                steps=len(steps),
                is_step=cli.is_step_line,
                on_done=done,
            )

        if export_first and not dry_run:
            self.run_export(self.settings["export_parts"], then=go)
        else:
            go()

    def use_as_config(self, e: exports.Export) -> None:
        def work():
            config = cli.config_dir()
            if config is None:
                raise RuntimeError("ensconce did not say where its config is")
            kept = exports.backup_config(config, cli.state_dir())
            exports.copy_as_config(e.path, config)
            return config, kept

        def done(result) -> None:
            config, kept = result
            self.toast(f"ensconce now uses this export{f' (the old config is in {kept})' if kept else ''}")

        worker.run(work, done, lambda exc: self.toast(f"Not done: {exc}"))

    def delete(self, e: exports.Export) -> None:
        try:
            exports.delete(e, self.folder)
        except OSError as exc:
            self.toast(f"Not deleted: {exc.strerror}")
            return
        self.toast(f"Deleted the export of {e.when}")
        self.refresh()

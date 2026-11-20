"""Ensconce's own group on the General page of Preferences. The dialog,
Appearance and Window are the kit's."""

from __future__ import annotations

from pathlib import Path

from gi.repository import Adw, Gio, GLib, Gtk

from .. import INFO
from ..core import exports
from ..kit.prefs import Preferences


def choose_folder(window, then=None) -> None:
    """Pick the exports folder (Gtk.FileDialog)."""
    dialog = Gtk.FileDialog(title="Exports Folder", modal=True)
    start = window.folder if window.folder.is_dir() else Path.home()
    dialog.set_initial_folder(Gio.File.new_for_path(str(start)))

    def picked(d, result) -> None:
        try:
            chosen = d.select_folder_finish(result)
        except GLib.Error:
            return  # cancelled
        if chosen and chosen.get_path():
            window.set_folder(Path(chosen.get_path()))
            if then:
                then()

    dialog.select_folder(window, None, picked)


def show(window) -> None:
    group = Adw.PreferencesGroup(
        title="Exports",
        description="Put the folder in Nextcloud, or another folder that syncs, and every "
        "computer sees the others' exports. Each computer writes into a folder of its own name.",
    )
    row = Adw.ActionRow(title="Exports Folder", subtitle_selectable=True)

    def show_folder() -> None:
        default = "" if window.settings["exports_folder"] else " (the default)"
        row.set_subtitle(GLib.markup_escape_text(f"{window.folder}{default}"))

    show_folder()
    choose = Gtk.Button(label="Choose…", valign=Gtk.Align.CENTER)
    choose.connect("clicked", lambda *_a: choose_folder(window, show_folder))
    row.add_suffix(choose)
    open_button = Gtk.Button(
        icon_name="folder-open-symbolic", valign=Gtk.Align.CENTER, tooltip_text="Open Folder"
    )
    open_button.add_css_class("flat")
    open_button.connect("clicked", lambda *_a: window.open_folder(window.folder))
    row.add_suffix(open_button)
    group.add(row)

    if window.settings["exports_folder"]:
        reset = Adw.ActionRow(
            title="Default Folder",
            subtitle=GLib.markup_escape_text(str(exports.default_folder())),
        )
        back = Gtk.Button(label="Use", valign=Gtk.Align.CENTER)

        def use_default(*_a) -> None:
            window.settings.set("exports_folder", "")
            window.refresh()
            show_folder()
            reset.set_visible(False)

        back.connect("clicked", use_default)
        reset.add_suffix(back)
        group.add(reset)

    dialog = Preferences(INFO, window.settings, window, own_groups=[group], jobs=True)
    dialog.present(window)

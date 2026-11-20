"""Adw.Application entry point."""

from __future__ import annotations

import sys

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import Adw, Gio, Gtk  # noqa: E402

from .. import APP_ID  # noqa: E402
from .window import Window  # noqa: E402


class Application(Adw.Application):
    def __init__(self) -> None:
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.DEFAULT_FLAGS)

    def do_startup(self) -> None:  # noqa: N802 - GObject naming
        Adw.Application.do_startup(self)
        Gtk.Window.set_default_icon_name(APP_ID)

    def do_activate(self) -> None:  # noqa: N802
        window = self.props.active_window or Window(application=self)
        window.present()


def main(argv: list[str] | None = None) -> int:
    return Application().run(argv if argv is not None else sys.argv[:1])

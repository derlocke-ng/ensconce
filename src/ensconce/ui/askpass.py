"""The password dialog sudo opens while the app runs ensconce (SUDO_ASKPASS).

sudo runs `ensconce-askpass "<its prompt>"` and reads the password from its
output. Cancel exits with 1, and sudo then fails the one command that asked.
The password goes to sudo and nowhere else.
"""

from __future__ import annotations

import sys

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import Adw, Gio, Gtk  # noqa: E402

from .. import APP_ID, NAME  # noqa: E402


class Askpass(Adw.Application):
    def __init__(self, prompt: str) -> None:
        super().__init__(application_id=f"{APP_ID}.Askpass", flags=Gio.ApplicationFlags.NON_UNIQUE)
        self.prompt = prompt.strip() or "Password:"
        self.answer: str | None = None

    def do_activate(self) -> None:  # noqa: N802
        win = Adw.ApplicationWindow(
            application=self, title="Password Needed", default_width=420, resizable=False
        )
        Gtk.Window.set_default_icon_name(APP_ID)
        box = Gtk.Box(
            orientation=Gtk.Orientation.VERTICAL,
            spacing=18,
            margin_top=12,
            margin_bottom=18,
            margin_start=18,
            margin_end=18,
        )
        text = Gtk.Label(
            label=f"{NAME} is applying a part that changes the system, and sudo asks for your password.",
            wrap=True,
            xalign=0,
        )
        box.append(text)
        rows = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
        rows.add_css_class("boxed-list")
        self.entry = Adw.PasswordEntryRow(title=self.prompt)
        self.entry.connect("entry-activated", lambda *_a: self._done(True))
        rows.append(self.entry)
        box.append(rows)
        buttons = Gtk.Box(spacing=12, halign=Gtk.Align.END)
        cancel = Gtk.Button(label="Cancel")
        cancel.connect("clicked", lambda *_a: self._done(False))
        ok = Gtk.Button(label="Unlock")
        ok.add_css_class("suggested-action")
        ok.connect("clicked", lambda *_a: self._done(True))
        buttons.append(cancel)
        buttons.append(ok)
        box.append(buttons)
        view = Adw.ToolbarView(content=box)
        view.add_top_bar(Adw.HeaderBar())
        win.set_content(view)
        win.connect("close-request", lambda *_a: self._done(False) or False)
        win.present()
        self.entry.grab_focus()

    def _done(self, ok: bool) -> None:
        if ok and self.answer is None:
            self.answer = self.entry.get_text()
        self.quit()


def main() -> int:
    app = Askpass(" ".join(sys.argv[1:]))
    app.run([sys.argv[0]])
    if app.answer is None:
        return 1
    sys.stdout.write(app.answer + "\n")
    sys.stdout.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())

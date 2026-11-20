# Changelog

Releases of ensconce. The newest is on top; kiwi.manifest's VERSION, the
version in ensconce.sh and the app's `__version__` are the same as its
heading (tests/check-version.sh).

## 2.6.0 — unreleased

- **Ensconce, the app.** `ensconce-gui` is a GTK 4 window for exporting and
  restoring setups. It lists the exports in one folder, grouped by the
  computer that made them, and shows what is in each. Restore applies the
  parts you pick, and can export this computer first. Put the folder in
  Nextcloud, and every computer sees the others' exports. Built on the
  kiwi-template kit 0.1.3: header, menu, About, Preferences, icon chooser,
  window size and the job strip with the filling kiwi are the same as in
  the other Kiwi apps.
- **The app never runs a file from an export.** Of `settings.sh` it takes
  only the settings ensconce knows, as text, and writes them anew. "Use as
  Setup Config" does the same, after copying your current config to
  `~/.local/state/ensconce/`.
- **Fonts.** The new `fonts` part exports your own fonts from
  `~/.local/share/fonts` and `~/.fonts`, and the `fonts` step installs the
  missing ones. Fonts are only exported when asked for (`--parts fonts`, or
  the switch in the app): they can be hundreds of MB.
- **Font settings left over from before GNOME 48.** A setting that names
  Cantarell or Source Code Pro wins over GNOME's new Adwaita fonts on an
  updated Bluefin. The `fonts` step, and the `dconf` step after it applies
  your settings, offer to reset such settings; `--export` writes them as
  comments, so they no longer spread to new computers. The app has **Reset
  Old Font Settings…** in its menu.
- **`--export --parts dconf,flatpaks,…`** exports only those parts.
  `settings.sh` is always written. Every export now also gets
  `ensconce-export.info`: the computer, the date, the version, the image and
  the parts.
- **`--yes`** asks nothing: each question takes its default answer.
- **`--only` leaves the other steps' progress alone.** It used to mark every
  step it left out as done, and the next full run then skipped them.
  A run with `--only` also no longer offers to clear the progress at the end.
- **`--dry-run` no longer marks steps as done.** A real run after it ran
  them as if they had been applied already.
- **`--status` with no step done yet** printed an arithmetic error instead
  of "Progress: 0/15".
- **`--init` into a folder that exists but holds no config** copied the
  examples into a `config.example/` folder inside it. It now fills the
  folder itself, and asks before overwriting only when there is a
  `settings.sh`.
- **Each step starts with a `==> Step 2/5: name` line**, which the app counts.
- **No colour codes without a terminal** (or with `NO_COLOR` set).
- **sudo without a terminal asks through `SUDO_ASKPASS`** when it is set.
  The app sets it to its password dialog, `ensconce-askpass`.
- **The re-run under `systemd-inhibit` goes through bash**, so a checkout
  whose files lost their exec bit still starts. Where logind can't be
  reached (a container), ensconce runs without the sleep block instead of
  stopping.

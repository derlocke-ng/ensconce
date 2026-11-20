# Development

This page is for people who change ensconce: where things are, how to add a
step, how the app is built, and how to test and release.

## Project layout

```
ensconce/
├── ensconce.sh             the command
├── install.sh              kiwi's installer: install, update, uninstall
├── kiwi.manifest           what kiwi knows about the app
├── lib/                    shared bash functions
│   ├── logging.sh          output and the log file
│   ├── helpers.sh          run_cmd, confirm, image detection, sudo for the app
│   ├── progress.sh         which steps are done, resuming
│   ├── inhibitor.sh        keeps the computer awake during a run
│   ├── export.sh           --export: reads this computer's setup
│   ├── ssh.sh              SSH paths shared by the ssh step and --export
│   ├── fonts.sh            your fonts, font settings from before GNOME 48
│   └── preflight.sh        checks before a run
├── steps/                  one script per step, NN-name.sh
├── config.example/         the example config that --init copies
├── src/ensconce/           the app (Python, GTK 4)
│   ├── core/               exports and the command, without GTK
│   ├── ui/                 the window, the dialogs, the password dialog
│   └── kit/                shared Kiwi app parts, copied from kiwi-template
├── bin/                    the app's launchers: ensconce-gui, ensconce-askpass
├── data/                   the icon and the app grid entry
├── tests/                  check-version.sh, steps.sh, app.sh, unit/
├── tools/                  kit-update.sh, kit-check.sh
└── dconf-backup.sh         writes the current dconf settings to a file
```

## Add a step

Put a new file in `steps/`:

```bash
#!/bin/bash
# Step: mystep
# Description: What it does, in one line

step_mystep() {
    log_info "Running my step..."
    # use run_cmd for every change, so --dry-run works,
    # and confirm before each change
}
```

Name it `NN-mystep.sh`; the number sets the order. ensconce finds it by
itself. Return 42 when the computer has to restart before the next step.

Use `run_cmd` for every command that changes something, so `--dry-run` only
prints it. Use `confirm` before each change: with `--yes`, which the app uses,
it takes the default answer. Call `sudo` as usual; without a terminal it asks
through the app's password dialog.

To let the app export and restore your part, add an `_export_` function to
`lib/export.sh`, the step's name to `EXPORT_PART_NAMES`, and a `Part` to
`PARTS` in `src/ensconce/core/exports.py`.

## The app

The app is the Python package in `src/ensconce/`. It never applies anything
itself. It runs `ensconce.sh` with `--yes` and `NO_COLOR=1`, and with
`SUDO_ASKPASS` set to `bin/ensconce-askpass`, and shows the output in the job
strip. `core/` has no GTK and is what the unit tests cover.

The header bar, the menu, About, Preferences, the icon chooser, the window
size and the job strip with the filling kiwi come from the kit in
`src/ensconce/kit/`. It is a copy of
[kiwi-template](https://github.com/derlocke-ng/kiwi-template)'s kit, and the
same in every Kiwi app. Do not change it here. `tools/kit-update.sh` copies a
newer release, and `tools/kit-check.sh` checks that the copy is unchanged.

Start the app from a checkout with `bin/ensconce-gui`.

## Use ensconce in an image build

ensconce can be the base of a custom image build (like
[finpilot](https://github.com/projectbluefin/finpilot)):

- `config.example/` is the config others start from.
- `config/` is ignored by git: fork the repository, change the examples and
  ship them.
- The scripts in `steps/` can be sourced one at a time from other scripts.
- The files in `lib/` do not depend on each other.

## Tests

Run them in a container or on a computer you do not mind changing; they use
a temporary `$HOME` and stub commands, and change nothing outside it.

| Test | What it checks |
|---|---|
| `bash tests/check-version.sh` | the version is the same in `kiwi.manifest`, `ensconce.sh`, the app and `CHANGELOG.md`, and the scripts are executable in git |
| `bash tests/steps.sh` | the ssh, kiwi, sysctl, power and Flatpak language steps, and their export |
| `bash tests/app.sh` | what the app needs from the command: `--export --parts`, the info file, `--yes`, no colour codes, sudo through `SUDO_ASKPASS`, `--init`, progress |
| `python3 -m pytest` | the app's `core/`: reading exports, the settings it takes over, replacing a config |
| `bash tools/kit-check.sh` | the kit is the unchanged copy |

CI runs all of them, `ruff` on the Python code, `shellcheck` on the app's
scripts and the installer, and checks that the app imports with GTK 4 and
libadwaita.

## Release

1. Raise the version in `kiwi.manifest`, `ensconce.sh`
   (`ENSCONCE_VERSION`), `src/ensconce/__init__.py` and `pyproject.toml`, and
   add its section to `CHANGELOG.md`.
2. Merge to `main`. The release workflow tags `v<version>` and publishes the
   GitHub release with the changelog section as its notes.

kiwi installs the newest version tag. kiwi-network.eu pulls `docs/` at that
tag.

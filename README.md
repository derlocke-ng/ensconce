# Ensconce

Modular post-installation setup for [Bluefin-DX](https://projectbluefin.io/).

Ensconce transforms a fresh Bluefin installation into your fully configured
development workstation — custom packages, Flatpaks, GNOME extensions,
Nextcloud sync, desktop settings, a synced SSH config with Bitwarden as the
agent, kiwi apps, and more.

## Quick Start

Via [kiwi-updater](https://github.com/derlocke-ng/kiwi-updater) (it is in the
[kiwi-catalog](https://github.com/derlocke-ng/kiwi-catalog)):

```bash
kiwi install ensconce
ensconce --init          # create ~/.config/ensconce from examples
ensconce                 # run setup
```

…or straight from a clone:

```bash
git clone https://github.com/derlocke-ng/ensconce.git
cd ensconce
./ensconce.sh --init     # Create config/ from examples
# Edit files in config/ to match your setup
./ensconce.sh            # Run setup
```

## Features

- **Modular steps** — each setup phase is a self-contained script in `steps/`
- **Simple config** — plain text list files, one item per line
- **Auto-resume** — saves progress and lets you continue after reboots
- **`--skip` / `--only`** — run or skip any step by name
- **Dry-run mode** — preview changes before applying
- **Logging** — capture full output for debugging
- **Preflight checks** — validates environment before running

## Cloning a Machine

`--export` reads the live system and writes an ensconce config tree — the
inverse of what the steps do. Set one machine up by hand, export it, edit, and
run ensconce on the next one.

```bash
ensconce --export ./my-setup     # on the configured machine
#   ...review and edit ./my-setup, copy it across...
ensconce --init                  # on the new machine
cp -rT ./my-setup "$(ensconce --config-dir)"
ensconce --dry-run && ensconce
```

| Exported | From |
|---|---|
| `packages.list` | `rpm-ostree` **requested** packages only, not the whole image |
| `flatpaks.list` | installed apps; non-Flathub origins commented out |
| `extensions.list` | user-installed extensions only, and only those actually from extensions.gnome.org |
| `flatpak-overrides/` | `~/.local/share/flatpak/overrides/` (minus `global`) |
| `repos.d/` | `/etc/yum.repos.d/` minus RPM-owned and Bluefin-provided files |
| `certs/` | `/etc/pki/ca-trust/source/anchors/` |
| `sysctl.d/` | `/etc/sysctl.d/*.conf` minus RPM-owned files |
| `dconf-settings.ini` | curated dconf subtrees, not a full `dconf dump /` |
| `gtk3-bookmarks` | `~/.config/gtk-3.0/bookmarks` |
| `nextcloud/` | parsed back out of `nextcloud.cfg`, per-folder excludes become tags |
| `gdm/` | `/etc/dconf/db/gdm.d/` + the greeter's display layout |
| `kiwi-apps.list` | apps `kiwi list` shows as installed (pins kept as comments) |
| `settings.sh` | `NEXTCLOUD_SERVER` from the Nextcloud client config; `FLATPAK_LANGUAGES` from `flatpak config` (system, else user); `SYSTEM_SLEEP=off` when `suspend.target` is masked; `SSH_SYNCED_DIR` from where `~/.ssh/config` links to, `SSH_CONTROL_DIR` from its `ControlPath`, `SSH_AGENT` from the session's `SSH_AUTH_SOCK`; `KIWI_INSTALL` from how kiwi-updater was installed |

An export is a **starting point, not a finished config**. Three deliberate
choices worth knowing about:

- **Repos** are classified three ways. RPM-owned files ship with the image and
  are skipped. Files matching Bluefin's runtime-written repos (`vscode`,
  `tailscale`, `docker-ce`, `_copr:*`, `rpmfusion*`, …) are exported as
  `<name>.repo.disabled` — present for reference, ignored by the repos step.
  Rename one to `.repo` to bring it back. Everything else is treated as yours.
- **dconf** is limited to subtrees that travel well. A full dump also carries
  window positions, monitor layout and recently-used lists, which are wrong on
  different hardware.
- **Nextcloud excludes** are deduplicated by content. A rule set used by
  several folders is named `browser` or `shared`; one used by a single folder
  is named after that folder.

`certs/` and `nextcloud/` can contain private material — check before sharing
an export.

## Staying Awake

A stock Bluefin desktop suspends after ~15 minutes idle, and typing in a
terminal does not reliably reset that timer — so a long `rpm-ostree` or
`ujust bbrew` run can put the machine to sleep mid-setup. Ensconce defends the
run with three layers, because none of them is sufficient alone:

| Layer | Blocks | How |
|---|---|---|
| logind | suspend, hibernate, lid switch | the script re-execs itself under `systemd-inhibit --mode=block` |
| gnome-session | idle timer, screen blank, lock | a parked `gnome-session-inhibit --inhibit-only` child |
| dconf | `gsd-power`'s own idle→suspend timer | `idle-delay` and `sleep-inactive-*-type` forced to never |

The dconf keys are saved before the run and put back afterwards — except
the ones your `dconf-settings.ini` or `SYSTEM_SLEEP=off` set, which are
yours and stay. That holds even when your value is the same one the run
forced, like `sleep-inactive-ac-type='nothing'`.

> A session inhibitor requested with a one-shot `gdbus call` is dropped the
> instant that D-Bus connection closes, so it looks like it worked and does
> nothing. That is why the inhibitor is held by a live child process instead.

## Project Structure

```
ensconce/
├── ensconce.sh             Main entry point
├── install.sh              kiwi installer (install|update|uninstall)
├── kiwi.manifest           kiwi app metadata
├── lib/                    Shared library modules
│   ├── logging.sh          Output formatting & log-to-file
│   ├── helpers.sh          run_cmd, confirm, image detection
│   ├── progress.sh         Checkpoint tracking & resume
│   ├── inhibitor.sh        Prevent sleep during setup
│   ├── export.sh           --export: capture this machine's setup
│   ├── ssh.sh              SSH paths shared by the ssh step and --export
│   └── preflight.sh        Pre-run validation checks
├── steps/                  Modular setup steps (NN-name.sh)
│   ├── 01-rebase.sh        Switch to Bluefin-DX
│   ├── 02-ujust.sh         Developer groups & CLI tools
│   ├── 03-repos.sh         Add RPM repositories
│   ├── 04-packages.sh      Layer RPM packages
│   ├── 05-flatpaks.sh      Install Flatpak apps
│   ├── 06-overrides.sh     Flatpak permission overrides
│   ├── 07-extensions.sh    GNOME Shell extensions
│   ├── 08-cacert.sh        Custom CA certificates
│   ├── 09-nextcloud.sh     Preseed Nextcloud folder sync
│   ├── 10-dconf.sh         GNOME desktop settings
│   ├── 11-gdm.sh           Login screen (GDM) settings
│   ├── 12-ssh.sh           Synced SSH config, Bitwarden as the SSH agent
│   ├── 13-kiwi.sh          kiwi-updater and kiwi apps
│   ├── 14-sysctl.sh        Kernel tunables (sysctl.d drop-ins)
│   └── 15-power.sh         Turn off suspend, hibernation, lid-close sleep
├── config/                 Your personal configuration (gitignored)
├── config.example/         Template configuration (committed)
├── tests/                  check-version.sh (release gate), steps.sh
└── dconf-backup.sh         Utility: export current dconf settings
```

## Configuration

The config directory is searched in this order, first match wins:

| Location | Used when |
|---|---|
| `$ENSCONCE_CONFIG` | explicitly set |
| `~/.config/ensconce/` | installed via kiwi |
| `<repo>/config/` | working from a clone (gitignored) |
| `<repo>/config.example/` | fallback — warns on every run |

`--init` creates one: an installed copy writes to `~/.config/ensconce`, a clone
writes to `config/`. `ensconce --config-dir` prints the active one and nothing
else, so it can be used in scripts.

Then edit:

| File / Directory | Purpose |
|---|---|
| `config/settings.sh` | Server URLs, SSH, kiwi-updater, feature toggles |
| `config/packages.list` | RPM packages to layer (one per line) |
| `config/flatpaks.list` | Flatpak app IDs (one per line) |
| `config/extensions.list` | GNOME extension UUIDs (one per line) |
| `config/repos.d/` | `.repo` files copied to `/etc/yum.repos.d/` |
| `config/flatpak-overrides/` | Per-app override files (native format) |
| `config/nextcloud/folders.list` | Sync folder definitions |
| `config/nextcloud/exclude.lst` | Global sync exclusion rules |
| `config/nextcloud/exclude.d/` | Per-folder exclusions via tags |
| `config/certs/` | CA certificates (`.pem` files) |
| `config/sysctl.d/` | Kernel tunables (`.conf` files) installed to `/etc/sysctl.d/` |
| `config/dconf-settings.ini` | GNOME desktop settings |
| `config/gtk3-bookmarks` | Nautilus sidebar bookmarks |
| `config/gdm/dconf.d/` | Login screen settings, installed to `/etc/dconf/db/gdm.d/` |
| `config/gdm/monitors.xml` | Login screen display layout (optional) |
| `config/kiwi-apps.list` | kiwi apps to install (one name per line) |

### List file format

All `.list` files use the same simple format:

```
# Comments start with #
# Blank lines are ignored

some-package       # Inline comments work too
another-package
```

### Nextcloud folder tags

Sync folders can have *tags* that link to per-folder exclusion files:

```
# folders.list — format: localPath|remotePath[|tags]
Documents|/cloud/Documents
.var/app/io.gitlab.librewolf-community|/cloud/apps/librewolf|browser
```

The `browser` tag causes `exclude.d/browser.lst` to be placed as
`.sync-exclude.lst` inside that folder, preventing SQLite corruption
while still syncing safe files like `user.js` and `bookmarkbackups/`.

### Login screen (GDM)

The greeter runs as the `gdm` user, so nothing in `config/dconf-settings.ini`
reaches it. Two separate knobs control it:

**`config/gdm/dconf.d/`** — keyfiles installed to `/etc/dconf/db/gdm.d/` and
compiled with `dconf update`. This is where pointer and interface settings go:

```ini
[org/gnome/desktop/peripherals/mouse]
accel-profile='flat'          # 'flat' = no mouse acceleration

[org/gnome/desktop/interface]
scaling-factor=uint32 1       # 0 = let mutter guess, 1 = 100%, 2 = 200%
```

**`config/gdm/monitors.xml`** — the greeter's display layout, installed to
`/var/lib/gdm/.config/monitors.xml`. This is what decides the login screen's
resolution and *fractional* scale. If it is missing, mutter picks a scale on
its own, which is where a stray 125% login screen comes from. Leave the file
out and the step offers to copy your own `~/.config/monitors.xml`, which makes
the greeter match your desktop exactly.

### SSH: one config everywhere, keys in Bitwarden

Three settings in `settings.sh`, each skipped when empty:

```bash
SSH_SYNCED_DIR=".ssh/.sshsynched"      # a folder Nextcloud syncs, holding `config`
SSH_CONTROL_DIR=".ssh/control_sockets" # where the config's ControlPath points
SSH_AGENT="bitwarden"                  # bitwarden | gnome | empty
```

with the folder listed in `nextcloud/folders.list` (`.ssh/.sshsynched|/ssh`).
That gives every machine this layout:

```
~/.ssh/
├── .sshsynched/          synced by Nextcloud: config (and anything else shared)
├── config -> .sshsynched/config
├── control_sockets/      local: sockets cannot be synced
└── known_hosts           local to each machine
```

- **The link is relative**, so it means the same on a machine with another
  user name or home directory. An existing absolute link to the same file is
  rewritten as a relative one.
- **An existing `~/.ssh/config`** is never lost. If the synced folder already
  has one, the local file is kept as `config.ensconce-<date>`. If it does not,
  ensconce offers to move yours into it, so it becomes the one that syncs.
- **Permissions:** `~/.ssh` and both directories are `0700`, and the synced
  config is `0600`. ssh refuses a config others can write.
- **Before Nextcloud has synced**, the link points at nothing yet and ssh
  simply runs without a config.

**`SSH_AGENT=bitwarden`** makes the Bitwarden Flatpak's built-in agent the
session's `SSH_AUTH_SOCK`. Your keys stay in the vault, and Bitwarden asks
before each use. The Flatpak listens on
`~/.var/app/com.bitwarden.desktop/data/.bitwarden-ssh-agent.sock`. Ensconce
writes that to `~/.config/environment.d/90-ensconce-ssh-agent.conf`, which the
whole desktop session reads. It also masks GNOME's `gcr-ssh-agent.socket`:
GNOME 46 and later starts it in every session, and it sets `SSH_AUTH_SOCK`
back to itself. Two things are left to you, in Bitwarden's settings: **Enable
SSH agent**, and **Start automatically on login**. Then log out and back in.
`SSH_AGENT=gnome` undoes all of it.

### kiwi apps

`KIWI_INSTALL` installs [kiwi-updater](https://github.com/derlocke-ng/kiwi-updater)
if it is missing, through its own `get-kiwi.sh`:

| `KIWI_INSTALL` | Installs |
|---|---|
| `recommended` | user + system scope: one password now, passwordless updates after |
| `manual` | the same, but every system change asks for your password |
| `minimal` | user scope only, never root (enough for user-only apps) |

Then it installs every app in `kiwi-apps.list` that is not installed yet.
Put `ensconce` itself in that list, and a copy run from a clone hands over to a
kiwi-managed one that kiwi keeps updated.

### Flatpak languages

Flatpak apps get their translations and locale data (the part behind date and
number formats) from separate *Locale* extensions, and Flatpak only installs
them for the languages it thinks you use. By default that is the language
you run in. So with an English desktop and German formats, `de` is missing
and apps such as Epiphany can't show German dates. Set the list yourself in
`settings.sh`:

```bash
FLATPAK_LANGUAGES="en;de"    # ";"-separated, or "*" for all
```

The flatpaks step writes it with `flatpak config --set languages` for both
the system and the user installation, since each keeps its own list. Then it
runs `flatpak update` for any installation that already has apps, which
fetches the new languages. That update also updates the apps themselves.
Leave it empty to keep Flatpak's own choice.

### Sleep: suspend, hibernation, lid close

For machines that don't wake up reliably, `SYSTEM_SLEEP="off"` in
`settings.sh` makes the `power` step turn sleep off at every level:

| Level | What it does |
|---|---|
| systemd | masks `sleep`, `suspend`, `hibernate`, `hybrid-sleep` and `suspend-then-hibernate.target`, so nothing can start them, not even `systemctl suspend` |
| logind | `/etc/systemd/logind.conf.d/90-ensconce-no-sleep.conf` ignores the lid (on battery, on power and docked), the suspend and hibernate keys, and the idle action. Applied by reloading logind, without ending your session |
| GNOME | `sleep-inactive-ac-type` and `sleep-inactive-battery-type` set to `'nothing'`, so GNOME doesn't try an idle suspend that can only fail |

Closing the lid then leaves the machine running. The screen still blanks and
locks as GNOME is set to. `SYSTEM_SLEEP="on"` unmasks the targets and removes
the logind file. It leaves GNOME's idle suspend alone; set that in
`dconf-settings.ini` or in Settings → Power.

### Kernel tunables (sysctl)

Every `.conf` file in `config/sysctl.d/` is installed to `/etc/sysctl.d/`
and applied right away with `sysctl --system`, so it also holds after a
reboot. Files that are already installed unchanged are left alone.

The example ships `99-dirty-writeback.conf`, a fix for desktops that freeze
during big writes on a slow SSD:

```ini
# start background writeback at 256 MiB, throttle writers at 1 GiB
vm.dirty_background_bytes = 268435456
vm.dirty_bytes = 1073741824
```

By default the kernel lets 10–20% of RAM fill with unwritten data before
it flushes. With a lot of RAM that is several GB, and a slow SSD stalls
everything while it writes them out. Delete the file if your disk keeps up.

### Flatpak overrides

Files in `config/flatpak-overrides/` use the **native Flatpak override
format**. The filename is the app ID:

```ini
# config/flatpak-overrides/com.valvesoftware.Steam
[Context]
filesystems=~/games;xdg-run/gvfs
```

## Usage

```bash
./ensconce.sh                          # Run all steps
./ensconce.sh --skip rebase,ujust      # Skip specific steps
./ensconce.sh --only extensions,dconf  # Run only specific steps
./ensconce.sh --dry-run                # Preview without making changes
./ensconce.sh --log                    # Save output to log file
./ensconce.sh --log /tmp/debug.log     # Log to specific file
./ensconce.sh --status                 # Show progress
./ensconce.sh --list-steps             # List available steps
./ensconce.sh --reset                  # Clear progress, start fresh
./ensconce.sh --init                   # Create config from examples
./ensconce.sh --export [dir]           # Capture this machine's setup
./ensconce.sh --config-dir             # Print the active config directory
```

## Installation Layout

Installed by kiwi (`SCOPES=user`, no root):

| Path | Contents |
|---|---|
| `~/.local/share/ensconce/` | runtime — `ensconce.sh`, `lib/`, `steps/`, `config.example/` |
| `~/.local/bin/ensconce` | symlink onto the above |
| `~/.config/ensconce/` | your config — untouched by install, update and uninstall |
| `~/.local/state/ensconce/` | progress, logs, dconf backups |

`install.sh uninstall --purge` also removes the last two. The steps that need
root (`rpm-ostree`, `/etc`, GDM) ask for it themselves, which is why this is a
user-scope app — installing it as root would apply your dconf and Flatpak
settings to the wrong account.

## Adding Custom Steps

Drop a new file in `steps/` following the naming convention:

```bash
#!/bin/bash
# Step: mystep
# Description: Do something awesome

step_mystep() {
    log_info "Running my custom step..."
    # Your logic here — use run_cmd, confirm, log_*, etc.
}
```

Name it `NN-mystep.sh` where the number controls execution order. The runner
auto-discovers it — no registration needed.

## For Template Builders

Ensconce is designed to be reusable for custom OS image builds
(like [finpilot](https://github.com/projectbluefin/finpilot)):

- **`config.example/`** serves as the template others start from
- **`config/`** is gitignored — fork the repo, customize examples, ship it
- **Step modules** in `steps/` can be sourced individually from other scripts
- **Library modules** in `lib/` are self-contained and reusable


## License

GPL-3.0

Copyright (C) 2026 derlocke-ng

# Configuration

ensconce reads its config from one folder: `settings.sh` for a few settings,
and a list file or folder for each part of the setup. `ensconce --init`
creates the folder from the examples in `config.example/`, and
[`--export`](usage.md#move-a-setup-to-another-computer) or
[the Ensconce app](app.md) fill it from a computer that is set up.

## Where the config is

The config directory is searched in this order, first match wins:

| Location | Used when |
|---|---|
| `$ENSCONCE_CONFIG` | explicitly set |
| `~/.config/ensconce/` | installed via kiwi |
| `<repo>/config/` | working from a clone (gitignored) |
| `<repo>/config.example/` | fallback — warns on every run |

`--init` creates one: an installed copy writes to `~/.config/ensconce`, a clone
writes to `config/`. `ensconce --config-dir` prints the active one and nothing
else, so it can be used in scripts. A folder counts as a config when it holds
`settings.sh`.

The Ensconce app keeps its own settings in the same folder:
`settings.json`, `window.json` and `icons/`. ensconce does not read them, and
the app keeps them when it replaces the config.

## The files

Each file is read by one step. A step whose file is missing or empty skips
itself.

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

## List file format

All `.list` files use the same simple format:

```
# Comments start with #
# Blank lines are ignored

some-package       # Inline comments work too
another-package
```

## Nextcloud folder tags

Sync folders can have *tags* that link to per-folder exclusion files:

```
# folders.list — format: localPath|remotePath[|tags]
Documents|/cloud/Documents
.var/app/io.gitlab.librewolf-community|/cloud/apps/librewolf|browser
```

The `browser` tag causes `exclude.d/browser.lst` to be placed as
`.sync-exclude.lst` inside that folder, preventing SQLite corruption
while still syncing safe files like `user.js` and `bookmarkbackups/`.

## Login screen (GDM)

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

## SSH: one config everywhere, keys in Bitwarden

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
  runs without a config.

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

## kiwi apps

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

## Flatpak languages

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

## Sleep: suspend, hibernation, lid close

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

## Kernel tunables (sysctl)

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

## Flatpak overrides

Files in `config/flatpak-overrides/` use the **native Flatpak override
format**. The filename is the app ID:

```ini
# config/flatpak-overrides/com.valvesoftware.Steam
[Context]
filesystems=~/games;xdg-run/gvfs
```

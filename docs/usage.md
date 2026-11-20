# Using the command

`ensconce` applies your config to this computer, step by step. Each *step* is
a script in `steps/` that applies one part of the config, for example the
Flatpak apps or the desktop settings. [Configuration](configuration.md)
describes the files they read. [The Ensconce app](app.md) runs the same
command for you.

## Options

| Command | What it does |
|---|---|
| `ensconce` | runs every step that is not done yet |
| `ensconce --skip rebase,ujust` | runs every step except these, and counts them as done |
| `ensconce --only extensions,dconf` | runs only these steps; the others stay as they were for the next full run |
| `ensconce --dry-run` | shows what each step would do, and changes nothing |
| `ensconce --yes` | asks nothing: every question takes its default answer |
| `ensconce --log` | also writes the output to a log file in `~/.local/state/ensconce/` |
| `ensconce --log /tmp/debug.log` | writes the log to that file |
| `ensconce --status` | shows which steps are done |
| `ensconce --list-steps` | lists the steps with a line on each |
| `ensconce --reset` | forgets the progress, so the next run starts from the first step |
| `ensconce --init` | creates a config from the examples |
| `ensconce --export [dir]` | writes this computer's setup into a config folder (see below) |
| `ensconce --export dir --parts dconf,flatpaks` | exports only these parts |
| `ensconce --config-dir` | prints the config folder in use, and nothing else |

`--skip` and `--only` cannot be used together. Each step asks before it
changes anything; the default answer is shown in capitals (`[Y/n]`).

## The steps

They run in this order:

| Step | What it does |
|---|---|
| `rebase` | switches the computer to Bluefin-DX |
| `ujust` | adds you to the developer groups and sets up Bluefin's command-line tools |
| `repos` | adds RPM repositories from `repos.d/` |
| `packages` | layers the RPM packages in `packages.list` |
| `flatpaks` | installs the Flatpak apps in `flatpaks.list` from Flathub |
| `overrides` | applies the Flatpak permission overrides |
| `extensions` | installs the GNOME Shell extensions |
| `cacert` | installs your CA certificates system-wide |
| `nextcloud` | prepares the Nextcloud client's sync folders |
| `dconf` | applies your GNOME desktop settings and file manager bookmarks |
| `gdm` | applies the login screen settings |
| `ssh` | links the synced SSH config and sets up the SSH agent |
| `kiwi` | installs kiwi-updater and the kiwi apps in `kiwi-apps.list` |
| `sysctl` | installs kernel tunables to `/etc/sysctl.d/` |
| `power` | turns sleep, hibernation and sleep on lid close off or on |

Each step starts with a line such as `==> Step 3/7: flatpaks`. A step that
finds nothing in the config skips itself.

## Resuming after a restart

ensconce remembers which steps are done, in `~/.local/state/ensconce/progress`.
The `rebase` step stops the run for a restart, and packages you layer are in
use only after one. Run `ensconce` again after the restart, and it continues
with the next step that is not done. `--status` shows where it stands, and `--reset` starts over.
A `--dry-run` records no progress.

## Staying awake

A stock Bluefin desktop suspends after about 15 minutes without input, and
typing in a terminal does not reliably reset that timer. A long
`rpm-ostree` or `ujust bbrew` run could put the computer to sleep halfway.
ensconce keeps it awake for the whole run in three ways, because none of them
is enough alone:

| Layer | Blocks | How |
|---|---|---|
| logind | suspend, hibernation, lid switch | ensconce runs itself again under `systemd-inhibit --mode=block` |
| gnome-session | idle timer, screen blank, lock | a child process holds `gnome-session-inhibit --inhibit-only` |
| dconf | the idle suspend timer of `gsd-power` | `idle-delay` and `sleep-inactive-*-type` are set to never |

The dconf keys are saved before the run and put back afterwards. The keys
that your `dconf-settings.ini` or `SYSTEM_SLEEP=off` set are yours and stay,
even when your value is the one the run set. Where logind cannot be reached
(in a container, for example), ensconce runs without the first layer.

A session inhibitor asked for with a one-shot `gdbus call` ends as soon as
that D-Bus connection closes, so it seems to work and does nothing. That is
why a child process holds it for the whole run.

## Move a setup to another computer

`--export` reads this computer's setup and writes it as an ensconce config:
the opposite of what the steps do. Set up one computer by hand, export it,
review the files, and run ensconce on the next one.

```bash
ensconce --export ./my-setup     # on the computer that is set up
#   review and edit ./my-setup, copy it to the new computer, then:
ensconce --init                  # on the new computer
cp -rT ./my-setup "$(ensconce --config-dir)"
ensconce --dry-run && ensconce
```

[The Ensconce app](app.md) does the same with an exports folder that all your
computers share.

| File | Read from |
|---|---|
| `packages.list` | the packages you layered with `rpm-ostree`, not the whole image |
| `flatpaks.list` | installed apps; apps from other remotes than Flathub are commented out |
| `extensions.list` | extensions you installed from extensions.gnome.org |
| `flatpak-overrides/` | `~/.local/share/flatpak/overrides/`, without `global` |
| `repos.d/` | `/etc/yum.repos.d/`, without the files that belong to an RPM or that Bluefin writes |
| `certs/` | `/etc/pki/ca-trust/source/anchors/` |
| `sysctl.d/` | `/etc/sysctl.d/*.conf`, without the files that belong to an RPM |
| `dconf-settings.ini` | chosen dconf subtrees, not all of `dconf dump /` |
| `gtk3-bookmarks` | `~/.config/gtk-3.0/bookmarks` |
| `nextcloud/` | the Nextcloud client's `nextcloud.cfg`; each folder's exclude list becomes a tag |
| `gdm/` | `/etc/dconf/db/gdm.d/` and the login screen's display layout |
| `kiwi-apps.list` | the apps `kiwi list` shows as installed; pins are kept as comments |
| `settings.sh` | the settings worked out from the above: Nextcloud server, Flatpak languages, sleep, SSH and kiwi-updater |
| `ensconce-export.info` | which computer made the export, when, with which version, and its parts; the app reads it, ensconce does not |

`--parts` takes the names of the steps the export has something for:
`packages`, `repos`, `flatpaks`, `overrides`, `extensions`, `cacert`,
`nextcloud`, `dconf`, `gdm`, `ssh`, `kiwi`, `sysctl` and `power`.
`settings.sh` is always written.

An export is a starting point, not a finished config. Three choices are
worth knowing:

- **Repositories** are sorted three ways. Files that belong to an RPM come
  with the image and are left out. Files that match the repositories Bluefin
  writes itself (`vscode`, `tailscale`, `docker-ce`, `_copr:*`,
  `rpmfusion*` and others) are exported as `<name>.repo.disabled`: they are
  there to read, and the `repos` step ignores them. Rename one to `.repo` to
  use it. Every other file is treated as yours.
- **dconf** is limited to subtrees that make sense on another computer. All
  of `dconf dump /` would also carry window positions, the monitor layout and
  lists of recent files, which are wrong on different hardware.
- **Nextcloud exclude lists** are merged when they are the same. A list used
  by several folders is called `browser` or `shared`; a list used by one
  folder is named after it.

`certs/` and `nextcloud/` can hold private things. Check them before you
share an export.

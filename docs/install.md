# Install

Ensconce runs on Bluefin and Bluefin-DX, the Universal Blue images. It is
installed for your user only: it configures your desktop session, and the
steps that change the system ask for your password themselves. Installing it
as root would put your dconf and Flatpak settings on the wrong account.

## With kiwi

```bash
kiwi install ensconce
```

[kiwi-updater](https://github.com/derlocke-ng/kiwi-updater) keeps it up to
date from then on. Put `ensconce` in your `kiwi-apps.list` too (see
[Configuration](configuration.md#kiwi-apps)), and a copy run from a clone
hands over to one that kiwi keeps updated.

## From a clone

```bash
git clone https://github.com/derlocke-ng/ensconce.git
cd ensconce
./install.sh install
```

You can also run `./ensconce.sh` straight from the clone without installing
it. It then keeps its config in `config/` inside the clone, which git
ignores.

## Where the files go

| Path | Contents |
|---|---|
| `~/.local/share/ensconce/` | the command (`ensconce.sh`, `lib/`, `steps/`, `config.example/`) and the app (`python/`, `bin/`, `data/`) |
| `~/.local/bin/ensconce` | a link to `ensconce.sh` |
| `~/.local/bin/ensconce-gui` | a link to the app's launcher |
| `~/.local/share/applications/eu.kiwinetwork.Ensconce.desktop` | the app's entry in the app grid |
| `~/.config/ensconce/` | your config; install, update and uninstall leave it alone |
| `~/.config/ensconce/settings.json` | the app's settings: exports folder, icon, window |
| `~/.local/state/ensconce/` | progress, logs, dconf backups, configs set aside by the app |
| `~/Ensconce/` | the app's default exports folder |

The app is installed when the computer has GTK 4 (kiwi says so with
`KIWI_GUI`). Without it, only the command is installed.

## Update

`kiwi update` installs a new release. From a clone, pull and run
`./install.sh update`. Your config, your progress and your exports stay as
they are. A run that was half done resumes where it stopped.

## Uninstall

```bash
kiwi uninstall ensconce              # or: ./install.sh uninstall
```

This removes the command, the app and the app grid entry. Your config in
`~/.config/ensconce/` and the progress in `~/.local/state/ensconce/` stay.
`kiwi uninstall --purge ensconce` (or `./install.sh uninstall --purge`)
removes those too. The exports folder is never removed: your other computers
read it.

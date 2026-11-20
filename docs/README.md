# Ensconce documentation

Ensconce sets up a Bluefin-DX computer from plain list files: packages,
Flatpaks, extensions, desktop settings and more. Each part is applied by a
*step*, a script in `steps/`. An *export* reads a computer's setup back into
the same files, and the Ensconce app keeps exports in one *exports folder*,
which you can share between your computers with Nextcloud.

| Page | For | What it covers |
|---|---|---|
| [Install](install.md) | everyone | install, update, uninstall, where files go |
| [The Ensconce app](app.md) | everyone | exports folder, export, restore, sharing with your other computers |
| [Using the command](usage.md) | everyone | every option, the steps, resuming, `--export` |
| [Configuration](configuration.md) | everyone | `settings.sh` and every list file and folder |
| [Development](development.md) | contributors | project layout, writing a step, tests, releases |

These pages are also on [kiwi-network.eu](https://kiwi-network.eu/docs/),
where they are pulled from this folder at every release.

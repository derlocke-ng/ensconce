"""Exports: folders that `ensconce --export` wrote, read without running them.

An export is an ensconce config tree (settings.sh, packages.list, …) plus
ensconce-export.info, which says which computer made it and when. The app
keeps all of them in one folder, one subfolder per computer:

    <exports folder>/<host>/<YYYY-MM-DD_HHMMSS>/

Put that folder in Nextcloud and every computer sees the others' exports.
Nothing here runs a file from an export: settings.sh is read as text, and
only the settings ensconce knows are taken from it (see `settings`).
"""

from __future__ import annotations

import contextlib
import os
import re
import shlex
import shutil
import socket
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

INFO_FILE = "ensconce-export.info"


@dataclass(frozen=True)
class Part:
    key: str  # the step's name; also what --parts takes
    title: str
    files: tuple[str, ...]  # what it reads in the export; "dir/" for a folder
    icon: str
    root: bool = False  # applying it asks for the password
    private: bool = False  # may hold something not for everybody
    note: str = ""


# In the order the steps run. rebase and ujust are not here: they set up a
# fresh Bluefin, there is nothing in an export for them.
PARTS: tuple[Part, ...] = (
    Part("repos", "Package Repositories", ("repos.d/",), "folder-download-symbolic", root=True),
    Part(
        "packages",
        "Layered Packages",
        ("packages.list",),
        "package-x-generic-symbolic",
        root=True,
        note="layering needs a restart",
    ),
    Part("flatpaks", "Flatpak Apps", ("flatpaks.list",), "view-app-grid-symbolic"),
    Part("overrides", "Flatpak Permissions", ("flatpak-overrides/",), "security-medium-symbolic"),
    Part("extensions", "GNOME Extensions", ("extensions.list",), "application-x-addon-symbolic"),
    Part("cacert", "CA Certificates", ("certs/",), "channel-secure-symbolic", root=True, private=True),
    Part(
        "nextcloud",
        "Nextcloud Folders",
        ("nextcloud/",),
        "folder-remote-symbolic",
        private=True,
        note="server address and the folders it syncs",
    ),
    Part(
        "dconf",
        "Desktop Settings",
        ("dconf-settings.ini", "gtk3-bookmarks"),
        "preferences-desktop-appearance-symbolic",
    ),
    Part("gdm", "Login Screen", ("gdm/",), "dialog-password-symbolic", root=True),
    Part(
        "ssh",
        "SSH Setup",
        (),
        "network-server-symbolic",
        private=True,
        note="where the synced ssh config is, and which agent",
    ),
    Part("kiwi", "Kiwi Apps", ("kiwi-apps.list",), "software-update-available-symbolic"),
    Part("sysctl", "Kernel Tunables", ("sysctl.d/",), "applications-system-symbolic", root=True),
    Part("power", "Sleep", (), "weather-clear-night-symbolic", root=True),
)
PART = {p.key: p for p in PARTS}

# settings.sh: the only lines taken from an export, and the steps they feed.
SETTINGS = {
    "NEXTCLOUD_SERVER": "nextcloud",
    "FLATPAK_LANGUAGES": "flatpaks",
    "SYSTEM_SLEEP": "power",
    "SSH_SYNCED_DIR": "ssh",
    "SSH_CONTROL_DIR": "ssh",
    "SSH_AGENT": "ssh",
    "KIWI_INSTALL": "kiwi",
}

_SETTING = re.compile(
    r"""^\s*(?:export\s+)?([A-Z_]+)=(?:"([^"$`\\]*)"|'([^']*)'|([^\s#'"$`;&|]*))\s*(?:#.*)?$"""
)


def this_host() -> str:
    return socket.gethostname().split(".")[0] or "this-computer"


def default_folder() -> Path:
    return Path.home() / "Ensconce"


# ── reading an export ─────────────────────────────────────────────────────
def list_entries(path: Path) -> list[str]:
    """A .list file's entries, the way ensconce reads them: no comments, no
    blank lines."""
    try:
        text = path.read_text(errors="replace")
    except OSError:
        return []
    out = []
    for line in text.splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            out.append(line)
    return out


def settings(folder: Path) -> dict[str, str]:
    """The known settings in folder/settings.sh, read as text. A line that
    needs the shell to work out its value (a $variable, a command) is left
    out, and so is every setting ensconce does not know."""
    found: dict[str, str] = {}
    try:
        text = (folder / "settings.sh").read_text(errors="replace")
    except OSError:
        return found
    for line in text.splitlines():
        m = _SETTING.match(line)
        if m and m.group(1) in SETTINGS:
            value = next((g for g in m.groups()[1:] if g is not None), "")
            found[m.group(1)] = value
    return found


def _files(folder: Path, name: str) -> list[Path]:
    if name.endswith("/"):
        d = folder / name.rstrip("/")
        if not d.is_dir():
            return []
        return sorted(p for p in d.rglob("*") if p.is_file() and p.name != ".gitkeep")
    p = folder / name
    return [p] if p.is_file() else []


@dataclass
class Content:
    """What an export holds for one part."""

    part: Part
    summary: str  # "12 packages"
    items: list[str] = field(default_factory=list)  # what the rows list


def _plural(n: int, one: str, many: str | None = None) -> str:
    return f"{n} {one if n == 1 else (many or one + 's')}"


def content(folder: Path, part: Part, conf: dict[str, str] | None = None) -> Content | None:
    """What folder has for this part; None when it has nothing for it."""
    conf = settings(folder) if conf is None else conf
    k = part.key
    if k in ("packages", "flatpaks", "extensions", "kiwi"):
        items = list_entries(folder / part.files[0])
        extra = []
        if k == "flatpaks" and conf.get("FLATPAK_LANGUAGES"):
            extra.append(f"languages {conf['FLATPAK_LANGUAGES']}")
        if k == "kiwi" and conf.get("KIWI_INSTALL"):
            extra.append(f"kiwi-updater: {conf['KIWI_INSTALL']}")
        if not items and not extra:
            return None
        noun = {"packages": "package", "flatpaks": "app", "extensions": "extension", "kiwi": "app"}[k]
        return Content(part, ", ".join([_plural(len(items), noun)] + extra), items)
    if k == "dconf":
        ini = folder / "dconf-settings.ini"
        groups = []
        if ini.is_file():
            groups = [
                line.strip()[1:-1]
                for line in ini.read_text(errors="replace").splitlines()
                if line.strip().startswith("[") and line.strip().endswith("]")
            ]
        marks = list_entries(folder / "gtk3-bookmarks")
        if not groups and not marks:
            return None
        bits = []
        if groups:
            bits.append(_plural(len(groups), "group") + " of settings")
        if marks:
            bits.append(_plural(len(marks), "bookmark"))
        return Content(part, ", ".join(bits), groups + [f"bookmark: {m}" for m in marks])
    if k == "nextcloud":
        rows = list_entries(folder / "nextcloud" / "folders.list")
        server = conf.get("NEXTCLOUD_SERVER", "")
        if not rows and not server:
            return None
        items = [r.split("|")[0] + " ⇄ " + (r.split("|")[1] if "|" in r else "?") for r in rows]
        return Content(part, ", ".join(filter(None, [_plural(len(rows), "folder"), server])), items)
    if k == "ssh":
        items = [
            f"{key}={conf[key]}"
            for key in ("SSH_SYNCED_DIR", "SSH_CONTROL_DIR", "SSH_AGENT")
            if conf.get(key)
        ]
        return Content(part, ", ".join(items), items) if items else None
    if k == "power":
        sleep = conf.get("SYSTEM_SLEEP", "")
        if not sleep:
            return None
        return Content(
            part, "sleep turned off" if sleep == "off" else "sleep turned back on", [f"SYSTEM_SLEEP={sleep}"]
        )
    # a folder of files: repos.d, flatpak-overrides, certs, gdm, sysctl.d
    files = [f for name in part.files for f in _files(folder, name)]
    if k == "repos":
        files = [f for f in files if f.name.endswith(".repo")]  # .repo.disabled is for reference
    if not files:
        return None
    base = folder
    return Content(part, _plural(len(files), "file"), [str(f.relative_to(base)) for f in files])


@dataclass
class Export:
    path: Path
    host: str
    date: datetime | None
    user: str = ""
    version: str = ""
    image: str = ""
    parts: list[str] = field(default_factory=list)  # what --parts it was made with

    @property
    def mine(self) -> bool:
        return self.host == this_host()

    @property
    def when(self) -> str:
        if not self.date:
            return self.path.name
        return self.date.strftime("%-d %b %Y, %H:%M")

    def contents(self) -> list[Content]:
        conf = settings(self.path)
        return [c for p in PARTS if (c := content(self.path, p, conf))]


def read_info(folder: Path) -> dict[str, str]:
    info: dict[str, str] = {}
    try:
        for line in (folder / INFO_FILE).read_text(errors="replace").splitlines():
            if "=" in line and not line.lstrip().startswith("#"):
                key, _, value = line.partition("=")
                info[key.strip()] = value.strip()
    except OSError:
        pass
    return info


def load(folder: Path, host_hint: str = "") -> Export | None:
    """The export in folder, or None when folder is not one."""
    if not (folder / "settings.sh").is_file():
        return None
    info = read_info(folder)
    date = None
    if info.get("DATE"):
        try:
            date = datetime.fromisoformat(info["DATE"])
        except ValueError:
            date = None
    if date is None:
        try:
            date = datetime.fromtimestamp((folder / "settings.sh").stat().st_mtime).astimezone()
        except OSError:
            date = None
    return Export(
        path=folder,
        host=info.get("HOST") or host_hint or folder.name,
        date=date,
        user=info.get("USER", ""),
        version=info.get("VERSION", ""),
        image=info.get("IMAGE", ""),
        parts=info.get("PARTS", "").split(),
    )


def scan(root: Path) -> list[Export]:
    """Every export in root: its subfolders, and theirs (one per computer).
    Hidden folders are left out: an export still being written is one."""
    found: list[Export] = []
    if not root.is_dir():
        return found

    def visible(d: Path) -> list[Path]:
        try:
            return sorted(p for p in d.iterdir() if p.is_dir() and not p.name.startswith("."))
        except OSError:
            return []

    for d in visible(root):
        e = load(d)
        if e:
            found.append(e)
            continue
        for sub in visible(d):
            e = load(sub, host_hint=d.name)
            if e:
                found.append(e)
    epoch = datetime.min.replace(tzinfo=datetime.now().astimezone().tzinfo)
    found.sort(key=lambda e: (not e.mine, e.host.lower(), -(e.date or epoch).timestamp()))
    return found


# ── writing ───────────────────────────────────────────────────────────────
def new_export_dir(root: Path) -> tuple[Path, Path]:
    """(where ensconce writes, where the export ends up): a hidden folder
    next to the final one, renamed by `finish` once the export is complete,
    so another computer never lists half an export."""
    stamp = datetime.now().strftime("%Y-%m-%d_%H%M%S")
    final = root / this_host() / stamp
    return final.parent / f".{stamp}.partial", final


def finish(partial: Path, final: Path) -> None:
    final.parent.mkdir(parents=True, exist_ok=True)
    os.replace(partial, final)


def discard(partial: Path) -> None:
    shutil.rmtree(partial, ignore_errors=True)


def write_settings(src: Path, dst: Path) -> None:
    """dst/settings.sh with src's known settings, quoted, so that what
    ensconce sources holds no line from another computer as it was."""
    conf = settings(src)
    lines = [
        "#!/bin/bash",
        f"# Ensconce settings, taken from the export {src}",
        "# by the Ensconce app: only the settings ensconce knows, nothing else.",
        "# config.example/settings.sh explains each.",
        "",
    ]
    for key in SETTINGS:
        lines.append(f"{key}={shlex.quote(conf.get(key, ''))}")
    (dst / "settings.sh").write_text("\n".join(lines) + "\n")


# The app's own files in ~/.config/ensconce, which is also where the command
# keeps its config: replacing the config keeps them.
APP_FILES = ("settings.json", "window.json", "icons")


def copy_as_config(export: Path, dst: Path) -> None:
    """Copy an export to dst as an ensconce config: its files, with
    settings.sh written anew (write_settings) and the info file left out.
    The app's own files in dst stay."""
    tmp = dst.parent / f".{dst.name}.new"
    shutil.rmtree(tmp, ignore_errors=True)
    shutil.copytree(
        export,
        tmp,
        ignore=shutil.ignore_patterns(INFO_FILE, "settings.sh", ".*.partial", *APP_FILES),
        symlinks=False,
    )
    write_settings(export, tmp)
    for name in APP_FILES:
        old = dst / name
        if old.is_dir():
            shutil.copytree(old, tmp / name, symlinks=True)
        elif old.is_file():
            shutil.copy2(old, tmp / name)
    if dst.exists():
        shutil.rmtree(dst)
    os.replace(tmp, dst)


def backup_config(config: Path, state: Path) -> Path | None:
    """Move the config in use aside, into the state folder. None when there
    is none."""
    if not (config / "settings.sh").is_file():
        return None
    target = state / f"config-before-{datetime.now().strftime('%Y-%m-%d_%H%M%S')}"
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(config, target, symlinks=True)
    return target


def delete(export: Export, root: Path) -> None:
    shutil.rmtree(export.path)
    if export.path.parent != root:
        with contextlib.suppress(OSError):
            export.path.parent.rmdir()  # the computer's folder, once it is empty

"""core.exports: reading exports without running them."""

from __future__ import annotations

import os
from pathlib import Path

import pytest

from ensconce.core import cli, exports


def make(root: Path, host: str, stamp: str, **files: str) -> Path:
    d = root / host / stamp
    d.mkdir(parents=True)
    files.setdefault("settings.sh", 'NEXTCLOUD_SERVER=""\n')
    for name, text in files.items():
        p = d / name.replace("__", "/")
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)
    return d


def test_settings_takes_known_plain_values_only(tmp_path: Path) -> None:
    (tmp_path / "settings.sh").write_text(
        "#!/bin/bash\n"
        'NEXTCLOUD_SERVER="https://cloud.example"   # comment\n'
        "FLATPAK_LANGUAGES='en;de'\n"
        "SYSTEM_SLEEP=off\n"
        'SSH_AGENT="$(touch /tmp/pwned)"\n'
        'KIWI_INSTALL="`id`"\n'
        "OTHER=1\n"
        'SSH_SYNCED_DIR="a" ; rm -rf ~\n'
    )
    assert exports.settings(tmp_path) == {
        "NEXTCLOUD_SERVER": "https://cloud.example",
        "FLATPAK_LANGUAGES": "en;de",
        "SYSTEM_SLEEP": "off",
    }


def test_write_settings_quotes_every_value(tmp_path: Path) -> None:
    src, dst = tmp_path / "src", tmp_path / "dst"
    src.mkdir()
    dst.mkdir()
    (src / "settings.sh").write_text("FLATPAK_LANGUAGES='en;de'\nSSH_SYNCED_DIR=\".ssh/my dir\"\n")
    exports.write_settings(src, dst)
    text = (dst / "settings.sh").read_text()
    assert "FLATPAK_LANGUAGES='en;de'" in text
    assert "SSH_SYNCED_DIR='.ssh/my dir'" in text
    assert "KIWI_INSTALL=''" in text
    assert exports.settings(dst)["SSH_SYNCED_DIR"] == ".ssh/my dir"


def test_scan_groups_by_host_newest_first_and_skips_partial(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setattr(exports, "this_host", lambda: "laptop")
    make(
        tmp_path,
        "desk",
        "2026-01-01_100000",
        **{"ensconce-export.info": "HOST=desk\nDATE=2026-01-01T10:00:00+01:00\nVERSION=2.6.0\n"},
    )
    make(
        tmp_path,
        "laptop",
        "2026-01-01_100000",
        **{"ensconce-export.info": "HOST=laptop\nDATE=2026-01-01T10:00:00+01:00\n"},
    )
    make(
        tmp_path,
        "laptop",
        "2026-02-01_100000",
        **{"ensconce-export.info": "HOST=laptop\nDATE=2026-02-01T10:00:00+01:00\n"},
    )
    make(tmp_path, "laptop", ".2026-03-01_100000.partial")
    (tmp_path / "not-an-export").mkdir()
    found = exports.scan(tmp_path)
    assert [(e.host, e.date.month) for e in found] == [("laptop", 2), ("laptop", 1), ("desk", 1)]
    assert found[0].mine and not found[2].mine
    assert found[2].version == "2.6.0"


def test_scan_without_info_file_uses_folder_names(tmp_path: Path) -> None:
    make(tmp_path, "old-box", "whatever")
    (e,) = exports.scan(tmp_path)
    assert e.host == "old-box" and e.date is not None


def test_contents(tmp_path: Path) -> None:
    d = make(
        tmp_path,
        "h",
        "s",
        **{
            "settings.sh": 'FLATPAK_LANGUAGES="en;de"\nSYSTEM_SLEEP="off"\nSSH_AGENT="bitwarden"\n',
            "packages.list": "# header\nvim\n\nhtop   # inline\n",
            "flatpaks.list": "org.gnome.Epiphany\n#com.example.Other   # origin: other\n",
            "dconf-settings.ini": "[org/gnome/desktop/interface]\nfoo=1\n[org/gnome/shell]\n",
            "repos.d__a.repo": "[a]\n",
            "repos.d__b.repo.disabled": "[b]\n",
            "certs__.gitkeep": "",
            "nextcloud__folders.list": "Documents|/cloud/Documents\n",
            "fonts__X.ttf": "font",
            "fonts__.uuid": "x",
        },
    )
    got = {c.part.key: c for c in exports.load(d).contents()}
    assert set(got) == {"repos", "packages", "flatpaks", "dconf", "nextcloud", "ssh", "power", "fonts"}
    assert got["fonts"].items == ["X.ttf"] and got["fonts"].summary.startswith("1 file, ")
    assert got["packages"].items == ["vim", "htop"]
    assert got["packages"].summary == "2 packages"
    assert got["flatpaks"].summary == "1 app, languages en;de"
    assert got["dconf"].items == ["org/gnome/desktop/interface", "org/gnome/shell"]
    assert got["repos"].items == ["repos.d/a.repo"]
    assert got["ssh"].items == ["SSH_AGENT=bitwarden"]
    assert got["nextcloud"].items == ["Documents ⇄ /cloud/Documents"]


def test_copy_as_config_rewrites_settings_and_drops_info(tmp_path: Path) -> None:
    d = make(
        tmp_path / "x",
        "h",
        "s",
        **{
            "settings.sh": 'SSH_AGENT="$(evil)"\nSYSTEM_SLEEP=off\n',
            "ensconce-export.info": "HOST=h\n",
            "packages.list": "vim\n",
        },
    )
    dst = tmp_path / "config"
    dst.mkdir()
    (dst / "stale.list").write_text("x")
    (dst / "settings.json").write_text('{"exports_folder": "/x"}')  # the app's own
    (dst / "icons").mkdir()
    (dst / "icons" / "mine.svg").write_text("<svg/>")
    exports.copy_as_config(d, dst)
    assert sorted(p.name for p in dst.iterdir()) == ["icons", "packages.list", "settings.json", "settings.sh"]
    assert (dst / "settings.json").read_text() == '{"exports_folder": "/x"}'
    assert (dst / "icons" / "mine.svg").is_file()
    assert "evil" not in (dst / "settings.sh").read_text()
    assert exports.settings(dst)["SYSTEM_SLEEP"] == "off"


def test_restore_config_links_the_fonts(tmp_path: Path) -> None:
    d = make(tmp_path / "x", "h", "s", **{"fonts__A.ttf": "font", "packages.list": "vim\n"})
    dst = tmp_path / "restore"
    exports.copy_as_config(d, dst, link_fonts=True)
    assert (dst / "fonts").is_symlink() and (dst / "fonts" / "A.ttf").read_text() == "font"
    full = tmp_path / "config"
    exports.copy_as_config(d, full)
    assert not (full / "fonts").is_symlink() and (full / "fonts" / "A.ttf").is_file()


def test_default_parts_leave_out_fonts() -> None:
    assert "fonts" not in exports.DEFAULT_PARTS and "dconf" in exports.DEFAULT_PARTS


def test_partial_finish_and_delete(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setattr(exports, "this_host", lambda: "me")
    partial, final = exports.new_export_dir(tmp_path)
    assert partial.parent == final.parent == tmp_path / "me" and partial.name.startswith(".")
    partial.mkdir(parents=True)
    (partial / "settings.sh").write_text("")
    exports.finish(partial, final)
    (e,) = exports.scan(tmp_path)
    exports.delete(e, tmp_path)
    assert not (tmp_path / "me").exists() and tmp_path.is_dir()


def test_backup_config(tmp_path: Path) -> None:
    assert exports.backup_config(tmp_path / "none", tmp_path / "state") is None
    conf = tmp_path / "conf"
    conf.mkdir()
    (conf / "settings.sh").write_text("x")
    kept = exports.backup_config(conf, tmp_path / "state")
    assert (kept / "settings.sh").read_text() == "x"


def test_cli_argv() -> None:
    argv = cli.export_argv(Path("/e"), ["dconf", "flatpaks"])
    assert argv[0] == "env" and "NO_COLOR=1" in argv
    assert argv[-5:] == ["--yes", "--export", "/e", "--parts", "dconf,flatpaks"]
    r = cli.restore_argv(Path("/c"), ["dconf"], dry_run=True)
    assert "ENSCONCE_CONFIG=/c" in r and r[-4:] == ["--yes", "--only", "dconf", "--dry-run"]
    assert cli.is_step_line("==> Step 1/2: dconf — Apply")
    assert not cli.is_step_line("[INFO] ==> Step")


@pytest.mark.skipif(not os.access(cli.SCRIPT, os.R_OK), reason="needs the checkout")
def test_parts_match_the_steps() -> None:
    steps = {p.name[3:-3] for p in (cli.SCRIPT.parent / "steps").glob("[0-9][0-9]-*.sh")}
    assert {p.key for p in exports.PARTS} <= steps
    text = (cli.SCRIPT.parent / "lib" / "export.sh").read_text()
    names = text.split("EXPORT_PART_NAMES=(", 1)[1].split(")", 1)[0].split()
    assert names == [p.key for p in exports.PARTS] or set(names) == {p.key for p in exports.PARTS}

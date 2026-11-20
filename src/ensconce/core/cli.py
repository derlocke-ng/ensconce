"""The `ensconce` command, as the app runs it.

The app never applies anything itself: it runs ensconce.sh, with --yes
(every question takes its default; the user chose in the app what to apply)
and SUDO_ASKPASS set to bin/ensconce-askpass, so the steps that need root ask
for the password in a dialog instead of a terminal nobody sees.
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

from .. import ROOT

SCRIPT = ROOT / "ensconce.sh"
ASKPASS = ROOT / "bin" / "ensconce-askpass"


def state_dir() -> Path:
    base = os.environ.get("XDG_STATE_HOME") or str(Path.home() / ".local" / "state")
    return Path(base) / "ensconce"


def available() -> bool:
    return SCRIPT.is_file()


def _env(**extra: str) -> list[str]:
    """env(1) arguments: the job strip runs one argv, so the environment
    goes in front of it."""
    pairs = {"NO_COLOR": "1", **extra}
    if ASKPASS.is_file():
        pairs["SUDO_ASKPASS"] = str(ASKPASS)
    return ["env"] + [f"{k}={v}" for k, v in pairs.items()]


def export_argv(target: Path, parts: list[str]) -> list[str]:
    argv = _env() + ["bash", str(SCRIPT), "--yes", "--export", str(target)]
    if parts:
        argv += ["--parts", ",".join(parts)]
    return argv


def restore_argv(config: Path, steps: list[str], dry_run: bool = False) -> list[str]:
    argv = _env(ENSCONCE_CONFIG=str(config)) + ["bash", str(SCRIPT), "--yes", "--only", ",".join(steps)]
    if dry_run:
        argv.append("--dry-run")
    return argv


def fonts_argv() -> list[str]:
    """The fonts step alone: installs the config's fonts/, if it has any, and
    resets font settings that name GNOME's fonts from before GNOME 48."""
    return _env() + ["bash", str(SCRIPT), "--yes", "--only", "fonts"]


def is_step_line(line: str) -> bool:
    """ensconce.sh prints "==> Step 2/5: name — …" as each step starts."""
    return line.startswith("==> Step ")


def config_dir() -> Path | None:
    """The config ensconce uses now (`ensconce --config-dir`)."""
    if not available():
        return None
    try:
        out = subprocess.run(
            ["bash", str(SCRIPT), "--config-dir"],
            capture_output=True,
            text=True,
            timeout=20,
            stdin=subprocess.DEVNULL,
        ).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return None
    return Path(out) if out else None

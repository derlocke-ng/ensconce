"""Ensconce, the app — the GTK window for the `ensconce` command.

The command (ensconce.sh with lib/ and steps/) is bash and does all the work:
it exports a computer's setup into a folder and applies one. This package is
the window on top of it: the exports in a folder you can share (Nextcloud,
say), what is in each, and restoring one. Its shared parts (header, menu,
About, Preferences, icon chooser, window size, job strip) are the kit from
kiwi-template, in kit/, copied unchanged.
"""

from pathlib import Path

from .kit import AppInfo

__version__ = "2.6.0"
APP = "ensconce"
APP_ID = "eu.kiwinetwork.Ensconce"
NAME = "Ensconce"
HOMEPAGE = "https://github.com/derlocke-ng/ensconce"

# Where ensconce.sh, bin/ and data/ are: the checkout (this file is in
# src/ensconce/) or the install (~/.local/share/ensconce/python/ensconce/).
ROOT = Path(__file__).resolve().parent.parent.parent

INFO = AppInfo(
    app=APP,
    app_id=APP_ID,
    name=NAME,
    version=__version__,
    description="Export a computer's setup into a shared folder and restore it on another",
    homepage=HOMEPAGE,
    glyph="ensconce",
    stock_icon=ROOT / "data" / "ensconce.svg",
    # A list of exports and a details dialog: narrower than the default.
    default_size=(860, 780),
    min_size=(360, 420),
)

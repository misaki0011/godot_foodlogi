#!/usr/bin/env python3
"""Give each web build its own game-data URL, so a browser cannot serve a
previous build's game code from cache.

Why this exists
---------------
Every branch push deploys to the one shared GitHub Pages URL, and the exported
file names never change: `index.pck` today is `index.pck` tomorrow. The pck is
the whole game -- every script and resource -- so a browser or CDN edge holding
yesterday's copy runs yesterday's game against today's HTML, with no visible
sign that anything is stale. That bit us: a deploy landed, the page loaded, and
the review still showed the previous build's behaviour.

`index.wasm` is deliberately left alone. That is the Godot engine binary, it is
36 MB, and it only changes when the engine version does -- re-downloading it on
every push would make each preview load far slower to fix a problem it does not
have. Game code lives in the pck, so busting the pck is what matters.

Godot's loader takes an explicit `mainPack` (see `mainPack || `${exe}.pck`` in
the exported index.js), so pointing it at `index.pck?v=<build>` is enough; the
query rides along on the fetch and the file on disk keeps its name. `fileSizes`
is keyed by the exact path the loader asks for, so the same key has to be added
there too or the loading bar loses the pck's size and stops being accurate.

Usage:  python3 tools/cache_bust_web_build.py build/web <build-id>
"""

import json
import re
import sys
from pathlib import Path

CONFIG_RE = re.compile(r"(const GODOT_CONFIG = )(\{.*?\})(;)", re.DOTALL)


def cache_bust(web_dir: Path, build_id: str) -> None:
    index = web_dir / "index.html"
    html = index.read_text()

    match = CONFIG_RE.search(html)
    if match is None:
        raise SystemExit(
            f"{index}: no GODOT_CONFIG found -- the export template's HTML shell "
            "changed shape, so this patch needs revisiting rather than skipping."
        )

    config = json.loads(match.group(2))

    pack = config.get("mainPack") or f"{config.get('executable', 'index')}.pck"
    if "?" in pack:
        raise SystemExit(f"{index}: mainPack is already cache-busted ({pack})")

    busted = f"{pack}?v={build_id}"
    config["mainPack"] = busted

    # Keyed by the exact path the loader fetches, so the progress bar keeps
    # knowing how big the download is.
    sizes = config.get("fileSizes")
    if isinstance(sizes, dict) and pack in sizes:
        sizes[busted] = sizes[pack]

    patched = json.dumps(config, separators=(",", ":"), sort_keys=True)
    index.write_text(html[: match.start()] + match.group(1) + patched + match.group(3) + html[match.end():])
    print(f"cache_bust_web_build: mainPack -> {busted}")


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(f"usage: {sys.argv[0]} <web-dir> <build-id>")
    web_dir = Path(sys.argv[1])
    build_id = sys.argv[2].strip()
    if not build_id:
        raise SystemExit("build id must not be empty")
    cache_bust(web_dir, build_id)


if __name__ == "__main__":
    main()

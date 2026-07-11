#!/usr/bin/env python3
"""Generate the RustDesk runtime configuration without JavaScript injection."""

from __future__ import annotations

import json
import os
import sys
import tempfile
from collections.abc import Mapping
from pathlib import Path


SETTINGS = (
    ("custom-rendezvous-server", "CUSTOM_RENDEZVOUS_SERVER", ""),
    ("relay-server", "RELAY_SERVER", ""),
    ("api-server", "API_SERVER", "api.rustdesk.com"),
    ("key", "KEY", ""),
)


def render_config(environ: Mapping[str, str]) -> str:
    lines = ["// Generated at container startup. Do not edit.\n"]
    for storage_key, environment_key, default in SETTINGS:
        value = environ.get(environment_key) or default
        lines.append(
            "window.localStorage.setItem("
            f"{json.dumps(storage_key)}, {json.dumps(value, ensure_ascii=False)}"
            ");\n"
        )
    return "".join(lines)


def write_config(output: Path, content: str) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        dir=output.parent,
        prefix=f".{output.name}.",
        delete=False,
    ) as temporary:
        temporary.write(content)
        temporary_path = Path(temporary.name)
    temporary_path.replace(output)


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(f"Usage: {argv[0]} OUTPUT", file=sys.stderr)
        return 64
    write_config(Path(argv[1]), render_config(os.environ))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

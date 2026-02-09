from __future__ import annotations

import os
from glob import glob


def _load_patches() -> dict[str, str]:
    patches: dict[str, str] = {}
    patches_dir = os.path.join(os.path.dirname(__file__), "patches")
    for path in sorted(glob(os.path.join(patches_dir, "*"))):
        name = os.path.basename(path)
        with open(path, "r", encoding="utf-8") as f:
            patches[name] = f.read()
    return patches


patches = _load_patches()

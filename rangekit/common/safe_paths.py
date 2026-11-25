"""Canonical path checks shared by the rangekit command-line tools.

The DFIR helpers take evidence and output paths on the command line, often from an
agent. Every such path is resolved to its canonical form and must sit inside one of
the allowed roots; anything else (``..`` escapes, symlinks out of the tree, another
drive) is refused instead of being read or written.

Allowed roots, in order:

* the current working directory and this repository;
* the system temporary directory;
* the event data workspace (``RANGE_KIT_DATA_ROOT``, else a ``Security-LabData``
  folder next to the repository or its parent);
* any extra roots listed in ``RANGE_KIT_ALLOWED_ROOTS`` (``os.pathsep``-separated).

The older ``SECURITY_LAB_DATA_ROOT`` / ``SECURITY_TOOLS_ALLOWED_ROOTS`` names are still
read when the new ones are unset.

Standard library only.
"""
from __future__ import annotations

import os
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
LAB_DATA_DIRNAME = "Security-LabData"


def _env(name: str, legacy: str) -> str:
    return os.environ.get(name) or os.environ.get(legacy, "")


class UnsafePathError(ValueError):
    """A path resolved outside every allowed root."""


def _is_within(path: Path, root: Path) -> bool:
    return path == root or root in path.parents


def allowed_roots() -> list[Path]:
    roots = [Path.cwd(), REPO_ROOT, Path(tempfile.gettempdir())]
    lab_data = _env("RANGE_KIT_DATA_ROOT", "SECURITY_LAB_DATA_ROOT")
    if lab_data:
        roots.append(Path(lab_data))
    else:
        roots += [base / LAB_DATA_DIRNAME for base in REPO_ROOT.parents[:2]]
    extra = _env("RANGE_KIT_ALLOWED_ROOTS", "SECURITY_TOOLS_ALLOWED_ROOTS")
    roots += [Path(item) for item in extra.split(os.pathsep) if item.strip()]
    return [root.resolve() for root in roots]


def resolve_cli_path(raw: str | os.PathLike[str]) -> Path:
    """Return the canonical form of a user-supplied path inside an allowed root."""
    candidate = Path(raw).resolve()
    for root in allowed_roots():
        if _is_within(candidate, root):
            return candidate
    raise UnsafePathError(
        f"refusing path outside the allowed roots: {candidate} "
        "(set RANGE_KIT_DATA_ROOT or RANGE_KIT_ALLOWED_ROOTS to widen them)"
    )


def join_within(base: str | os.PathLike[str], *parts: str) -> Path:
    """Join untrusted relative parts onto ``base`` and refuse any escape from it."""
    root = Path(base).resolve()
    target = root.joinpath(*parts).resolve()
    if not _is_within(target, root):
        raise UnsafePathError(f"refusing path that escapes {root}: {target}")
    return target

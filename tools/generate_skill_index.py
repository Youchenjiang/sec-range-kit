#!/usr/bin/env python3
"""Generate or verify the skill index at ``skills/INDEX.md``.

The index is a derived artifact: every row is recomputed from the skills that
actually exist on disk plus the provenance recorded in
``skills/SOURCES.json``. Regenerate it after adding, importing, renaming
or removing a skill; ``--check`` exits non-zero when the committed index has
drifted from reality.

Usage:
    python tools/generate_skill_index.py          # rewrite INDEX.md
    python tools/generate_skill_index.py --check  # fail if stale
"""

from __future__ import annotations

import argparse
import difflib
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SKILLS_DIR = REPO_ROOT / "skills"
INDEX_PATH = SKILLS_DIR / "INDEX.md"
SOURCES_PATH = SKILLS_DIR / "SOURCES.json"

#: Keep the index table readable; full text lives in each SKILL.md.
DESCRIPTION_WIDTH = 100

HEADER = """\
# Skill Index (`skills/`)

> **自動產生，請勿手動編輯。**
> 產生：`python tools/generate_skill_index.py`
> 校驗：`python tools/generate_skill_index.py --check`（索引脫節即 exit 1）

## 載入端如何發現（discovery contract）

1. **載入走目錄慣例，不是這份索引**：載入端掃描 `skills/<name>/SKILL.md`，
   只讀 frontmatter 的 `name` + `description` 兩欄作為技能身分，且目錄名必須與 `name` 一致。
2. **本索引不參與載入**：`INDEX.md` 是人／agent 的總表（名稱、描述、來源授權、路徑），
   讓你不必逐目錄翻閱就知道現有能力與授權邊界；它與載入掃描用同一套枚舉邏輯，
   因此「索引列得出」等價於「載入端讀得到」。
3. **自動同步**：索引由 `tools/generate_skill_index.py` 掃描目錄 +
   `SOURCES.json` 重新產生；`--check` 用於測試／doctor，可在索引與實際目錄脫節時中斷。
"""


def _display(path: Path) -> str:
    """Repo-relative posix path, falling back to the raw path when it is outside."""
    try:
        return path.relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return str(path)


def _block_scalar(lines: list[str], start: int, end: int, style: str) -> tuple[str, int]:
    """Collect the indented lines of a ``>``/``|`` block scalar starting at ``start``."""
    block: list[str] = []
    i = start
    while i < end and (not lines[i].strip() or lines[i][:1] in " \t"):
        if lines[i].strip():
            block.append(lines[i].strip())
        i += 1
    joined = " ".join(block) if style.startswith(">") else "\n".join(block)
    return joined, i


def parse_frontmatter(path: Path) -> dict[str, str]:
    """Extract top-level ``key: value`` pairs from a SKILL.md frontmatter block.

    Handles plain scalars, quoted scalars, and folded/literal block scalars
    (``>``, ``>-``, ``|``) as used by ``hitcon-dfir-vm-ops``.
    """
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---"):
        raise ValueError(f"{path}: missing frontmatter opening ---")

    lines = text.splitlines()
    try:
        end = next(i for i, line in enumerate(lines[1:], 1) if line.strip() == "---")
    except StopIteration as exc:
        raise ValueError(f"{path}: frontmatter is not terminated") from exc

    data: dict[str, str] = {}
    i = 1
    while i < end:
        line = lines[i]
        if not line.strip() or line.lstrip().startswith("#"):
            i += 1
            continue

        match = re.match(r"^([A-Za-z0-9_-]+):(.*)$", line)
        if not match:  # indented continuation of a previously handled scalar
            i += 1
            continue

        key, value = match.group(1), match.group(2).strip()
        if value[:1] in (">", "|"):  # block scalar: collect indented lines
            data[key], i = _block_scalar(lines, i + 1, end, value)
            continue

        data[key] = value.strip('"').strip("'")
        i += 1
    return data


def load_sources() -> dict:
    if not SOURCES_PATH.exists():
        raise ValueError(f"provenance file missing: {_display(SOURCES_PATH)}")
    try:
        payload = json.loads(SOURCES_PATH.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ValueError(f"provenance file is not valid JSON: {exc}") from exc
    if not isinstance(payload.get("sources"), list):
        raise ValueError("provenance file must contain a 'sources' list")
    return payload


def collect_records() -> list[dict]:
    """Return one record per skill, with provenance resolved from SOURCES.json."""
    if not SKILLS_DIR.is_dir():
        raise ValueError(f"skills directory missing: {_display(SKILLS_DIR)}")

    skills = sorted(
        path.parent.name
        for path in SKILLS_DIR.glob("*/SKILL.md")
        if path.parent.is_dir()
    )

    attribution = _attribution(load_sources()["sources"])
    _check_coverage(skills, attribution)
    return [_record(name, attribution[name]) for name in skills]


def _attribution(sources: list[dict]) -> dict[str, dict]:
    """Map each skill to the one source that claims it."""
    attribution: dict[str, dict] = {}
    for source in sources:
        for skill in source.get("skills", []):
            if skill in attribution:
                raise ValueError(
                    f"skill {skill!r} is attributed to both "
                    f"{attribution[skill].get('id')!r} and {source.get('id')!r}"
                )
            attribution[skill] = source
    return attribution


def _check_coverage(skills: list[str], attribution: dict[str, dict]) -> None:
    """Every skill on disk is attributed, and every attributed skill is on disk."""
    unknown = [name for name in skills if name not in attribution]
    if unknown:
        raise ValueError(
            "unattributed skills (add them to SOURCES.json): " + ", ".join(unknown)
        )
    stale = [name for name in attribution if name not in skills]
    if stale:
        raise ValueError(
            "SOURCES.json lists skills that are absent from "
            f"skills/: {', '.join(sorted(stale))}"
        )


def _record(name: str, source: dict) -> dict:
    skill_path = SKILLS_DIR / name / "SKILL.md"
    frontmatter = parse_frontmatter(skill_path)
    declared = frontmatter.get("license", "").strip()
    return {
        "name": frontmatter.get("name") or name,
        "directory": name,
        "description": " ".join(frontmatter.get("description", "").split()),
        "license": declared or source.get("license") or "Not specified",
        "license_origin": "frontmatter" if declared else "source",
        "source": source.get("label") or source.get("id") or "unknown",
        "path": skill_path.relative_to(REPO_ROOT).as_posix(),
    }


def _cell(text: str) -> str:
    """Collapse whitespace and trim so a value stays on one table row."""
    text = " ".join(text.split())
    if len(text) > DESCRIPTION_WIDTH:
        text = text[: DESCRIPTION_WIDTH - 1].rstrip() + "…"
    return text.replace("|", "\\|")


def render(records: list[dict]) -> str:
    sources = load_sources()["sources"]
    by_license: dict[str, int] = {}
    for record in records:
        by_license[record["license"]] = by_license.get(record["license"], 0) + 1

    lines = [HEADER, "\n## 統計\n", f"- 技能總數：**{len(records)}**"]
    for license_name, count in sorted(by_license.items(), key=lambda kv: (-kv[1], kv[0])):
        lines.append(f"- 授權 `{license_name}`：{count}")

    lines.extend([
        "\n## 技能清單\n",
        "| 名稱 | 描述 | 來源 | 授權 | 路徑 |",
        "|------|------|------|------|------|",
    ])
    for record in records:
        lines.append(
            f"| `{record['name']}` | {_cell(record['description'])} "
            f"| {record['source']} | {record['license']} | `{record['path']}` |"
        )

    lines.extend([
        "\n## 來源與授權（provenance）\n",
        "| 來源 | 快照 | commit | 授權 | 技能數 |",
        "|------|------|--------|------|--------|",
    ])
    for source in sources:
        count = len(source.get("skills", []))
        lines.append(
            f"| {source.get('label') or source.get('id')} | `{source.get('snapshot', '-')}` "
            f"| `{source.get('commit') or '-'}` | {source.get('license', '-')} | {count} |"
        )

    lines.append(
        "\n> 註：`授權` 欄優先取 SKILL.md frontmatter 的 `license`；"
        "若技能未宣告，則回退到 `SOURCES.json` 中其來源的授權。\n"
    )
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Generate or verify skills/INDEX.md")
    parser.add_argument(
        "--check",
        action="store_true",
        help="do not write; exit 1 if INDEX.md does not match a fresh regeneration",
    )
    args = parser.parse_args(argv)

    try:
        generated = render(collect_records())
    except ValueError as exc:
        print(f"ERROR {exc}", file=sys.stderr)
        return 2

    if not args.check:
        INDEX_PATH.write_text(generated, encoding="utf-8", newline="\n")
        print(f"wrote {_display(INDEX_PATH)}")
        return 0

    current = INDEX_PATH.read_text(encoding="utf-8") if INDEX_PATH.exists() else ""
    if current == generated:
        print("skill index is up to date")
        return 0

    print("ERROR skills/INDEX.md is stale; regenerate with", file=sys.stderr)
    print("  python tools/generate_skill_index.py", file=sys.stderr)
    diff = difflib.unified_diff(
        current.splitlines(keepends=True),
        generated.splitlines(keepends=True),
        fromfile="INDEX.md (committed)",
        tofile="INDEX.md (regenerated)",
    )
    sys.stderr.writelines(list(diff)[:60])
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

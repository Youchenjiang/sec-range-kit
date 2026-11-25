#!/usr/bin/env python3
"""Re-runnable, verifiable importer for the external skills under ``skills/``.

Every directory under ``skills/`` that comes from outside this repository is a
*derived artifact*: its files are copied from a pinned commit of an external snapshot,
optionally passed through a documented normalisation. The rules that do this live in
``skills/import-rules.json``; this tool is the only thing allowed to write the
imported trees, ``SOURCES.json`` (provenance) and ``INDEX.md`` (derived index).

Usage:
    python tools/skill_import.py --check                 # fail on any drift
    python tools/skill_import.py                         # import + refresh provenance
    python tools/skill_import.py --check --local-only    # verify without snapshots
    python tools/skill_import.py --check --source ctf-skills

Exit codes: 0 = verified/applied, 1 = drift (content, provenance or stale index),
2 = configuration/environment error (missing snapshot, unknown pin, bad rules).

Verification compares **git blob sha1**, not raw bytes: the local side is hashed with
``git hash-object`` (which applies the checkout filters, so a CRLF working tree still
matches an LF blob) and the upstream side is read out of the object store, so local
carnage in the snapshot working tree cannot masquerade as provenance.
"""

from __future__ import annotations

import argparse
import contextlib
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SKILLS_DIR = REPO_ROOT / "skills"
SOURCES_PATH = SKILLS_DIR / "SOURCES.json"
INDEX_PATH = SKILLS_DIR / "INDEX.md"
RULES_PATH = SKILLS_DIR / "import-rules.json"

PROVENANCE_DESCRIPTION = (
    "Provenance and licensing for skills under skills/. This file is generated "
    "by tools/skill_import.py from skills/import-rules.json; edit the "
    "rules (not this file) when importing, re-pinning or removing a source. INDEX.md is "
    "generated from this file plus each SKILL.md frontmatter."
)
VERIFIED_BY = "python tools/skill_import.py --check"
DEFAULT_ENTRY = "SKILL.md"
SELECT_KINDS = ("entry_dirs", "explicit", "frontmatter", "in_repo")


class RuleError(Exception):
    """Configuration or environment error: exit 2, never a content verdict."""


# --------------------------------------------------------------------- git glue


def _git(repo: Path, *args: str, data: bytes | None = None) -> bytes:
    proc = subprocess.run(
        ["git", "-C", str(repo), *args], input=data, capture_output=True
    )
    if proc.returncode != 0:
        raise RuleError(
            f"git -C {repo} {' '.join(args)} failed: "
            f"{proc.stderr.decode('utf-8', 'replace').strip()}"
        )
    return proc.stdout


def _git_ok(repo: Path, *args: str) -> bool:
    return subprocess.run(["git", "-C", str(repo), *args], capture_output=True).returncode == 0


def blob_sha1(content: bytes) -> str:
    """Git blob id of in-memory content (as the object store would store it)."""
    return hashlib.sha1(b"blob %d\0" % len(content) + content).hexdigest()


def upstream_tree(repo: Path, commit: str) -> dict[str, str]:
    """``{path: blob sha1}`` for every file at ``commit``; refuses symlinks."""
    tree: dict[str, str] = {}
    for line in _git(repo, "ls-tree", "-r", "-z", commit).split(b"\0"):
        if not line:
            continue
        meta, raw_path = line.split(b"\t", 1)
        mode, kind, sha = meta.split()
        path = raw_path.decode("utf-8")
        if mode == b"120000" or kind != b"blob":
            raise RuleError(f"upstream {commit[:8]}:{path} is not a regular file")
        tree[path] = sha.decode()
    return tree


def read_blob(repo: Path, sha: str) -> bytes:
    return _git(repo, "cat-file", "blob", sha)


def assert_pin_present(repo: Path, commit: str) -> None:
    if not re.fullmatch(r"[0-9a-f]{7,40}", commit or ""):
        raise RuleError(f"{repo}: rule has no usable commit pin ({commit!r})")
    if not _git_ok(repo, "cat-file", "-e", f"{commit}^{{commit}}"):
        raise RuleError(
            f"{repo}: pinned commit {commit} is not in the snapshot "
            "(fetch the snapshot or re-pin the rule)"
        )


def snapshot_head(repo: Path) -> str:
    return _git(repo, "rev-parse", "HEAD").decode().strip()


def head_delta(repo: Path, commit: str) -> int | None:
    """How many commits the snapshot HEAD is ahead of the pin (None if unrelated)."""
    proc = subprocess.run(
        ["git", "-C", str(repo), "rev-list", "--count", f"{commit}..HEAD"],
        capture_output=True,
    )
    if proc.returncode != 0:
        return None
    return int(proc.stdout.decode().strip())


def local_blob_sha(repo_root: Path, path: Path) -> str:
    """Blob sha1 of a working-tree file, checkout filters applied (CRLF-safe)."""
    rel = path.relative_to(repo_root).as_posix()
    return _git(repo_root, "hash-object", "--", rel).decode().strip()


def is_tracked(repo_root: Path, path: Path) -> bool:
    rel = path.relative_to(repo_root).as_posix()
    return _git_ok(repo_root, "ls-files", "--error-unmatch", "--", rel)


def ignore_rule(repo_root: Path, path: Path) -> str | None:
    """The ``.gitignore`` entry hiding ``path``, for actionable messages."""
    rel = path.relative_to(repo_root).as_posix()
    proc = subprocess.run(
        ["git", "-C", str(repo_root), "check-ignore", "-v", "--", rel],
        capture_output=True,
    )
    if proc.returncode != 0:
        return None
    return proc.stdout.decode("utf-8", "replace").strip()


def sha256_normalized(raw: bytes) -> str:
    """sha256 over LF-normalised bytes, so a CRLF checkout still matches the pin."""
    return hashlib.sha256(raw.replace(b"\r\n", b"\n")).hexdigest()


# ----------------------------------------------------------------- frontmatter


def split_frontmatter(text: str) -> tuple[list[str], int]:
    """``(block lines, index of the closing ---)`` or ``([], -1)`` when absent."""
    lines = text.splitlines(keepends=True)
    if not lines or lines[0].rstrip("\r\n") != "---":
        return [], -1
    for i, line in enumerate(lines[1:], 1):
        if line.rstrip("\r\n") == "---":
            return lines[1:i], i
    return [], -1


def parse_frontmatter(text: str) -> dict[str, object]:
    """Top-level scalars (unquoted) plus ``key:`` blocks of ``- item`` lists."""
    block, _ = split_frontmatter(text)
    data: dict[str, object] = {}
    key: str | None = None
    for line in block:
        body = line.rstrip("\r\n")
        if not body.strip() or body.lstrip().startswith("#"):
            continue
        if body.lstrip().startswith("- ") and key is not None:
            # YAML block lists may be indented or flush left; both mean "an item".
            value = data.setdefault(key, [])
            if isinstance(value, list):
                value.append(body.lstrip()[2:].strip().strip("\"'"))
            continue
        if body[:1] in " \t" and key is not None:  # continuation of the previous key
            continue
        match = re.match(r"^([A-Za-z0-9_-]+):[ \t]*(.*)$", body)
        if not match:
            continue
        key, value = match.group(1), match.group(2).strip()
        if value:
            data[key] = value.strip("\"'")
        else:
            data.setdefault(key, [])
    return data


def normalize_entry(raw: bytes, name: str, spec: dict) -> bytes:
    """Apply a source's documented frontmatter normalisation to its entry file.

    Only the keys a rule names are touched: comment lines may be dropped, declared
    keys unquoted, and ``name`` rewritten to the local directory name. Every other
    line (and the whole body) stays byte-identical, so the imports never drift further
    from upstream than the rule says.
    """
    rule = spec.get("frontmatter")
    if not rule:
        return raw
    text = raw.decode("utf-8")
    block, closing = split_frontmatter(text)
    if closing < 0:
        raise RuleError(f"{name}: entry file has no delimited frontmatter block")
    lines = text.splitlines(keepends=True)
    unquote = set(rule.get("unquote", []))
    out: list[str] = [lines[0]]
    for line in block:
        body = line.rstrip("\r\n")
        if rule.get("strip_comments") and body.lstrip().startswith("#"):
            continue
        match = re.match(r"^([A-Za-z0-9_-]+):[ \t]*(.*)$", body)
        if match:
            key, value = match.group(1), match.group(2)
            rewritten: str | None = None
            if key in unquote:
                rewritten = value.strip().strip('"').strip("'")
            if key == "name" and rule.get("set_name"):
                rewritten = name
            if rewritten is not None:
                line = f"{key}: {rewritten}" + ("\r\n" if line.endswith("\r\n") else "\n")
        out.append(line)
    out.extend(lines[closing:])
    return "".join(out).encode("utf-8")


# ------------------------------------------------------------------ selection


@dataclass(frozen=True)
class SkillRef:
    """One selected skill and its upstream provenance."""

    name: str
    upstream_dir: str = ""
    files: dict[str, str] = field(default_factory=dict)  # upstream-relative path -> blob sha1
    entry: str | None = None  # upstream entry file name


@dataclass(frozen=True)
class ImportFile:
    """One file the rules say must exist inside a skill directory."""

    rel: str  # destination path relative to the skill directory
    upstream_sha: str  # blob id at the pin
    blob_sha: str  # blob id expected after normalisation
    content: bytes | None = None  # expected bytes when normalisation applies


@dataclass(frozen=True)
class Problem:
    kind: str
    detail: str

    def __str__(self) -> str:  # pragma: no cover - cosmetic
        return f"{self.kind}: {self.detail}"


@dataclass
class SourcePlan:
    spec: dict
    repo: Path | None
    skills: dict[str, SkillRef]
    universe: int | None = None
    recorded: dict = field(default_factory=dict)  # previous SOURCES.json entry


def load_rules(path: Path) -> dict:
    if not path.is_file():
        raise RuleError(f"import rules missing: {path}")
    try:
        rules = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise RuleError(f"import rules are not valid JSON: {exc}") from exc
    sources = rules.get("sources")
    if not isinstance(sources, list) or not sources:
        raise RuleError("import rules must contain a non-empty 'sources' list")
    seen: set[str] = set()
    for source in sources:
        sid = source.get("id")
        if not sid:
            raise RuleError("every source needs an 'id'")
        if sid in seen:
            raise RuleError(f"duplicate source id {sid!r}")
        seen.add(sid)
        select = source.get("select") or {}
        if select.get("kind") not in SELECT_KINDS:
            raise RuleError(f"{sid}: select.kind must be one of {', '.join(SELECT_KINDS)}")
        if select["kind"] != "in_repo":
            for key in ("snapshot", "commit", "license"):
                if not source.get(key):
                    raise RuleError(f"{sid}: rule is missing '{key}'")
    return rules


def snapshot_candidates(
    spec: dict, snapshot_root: Path | None, repo_root: Path
) -> list[Path]:
    """Where a rule's relative ``snapshot`` may live, most specific first.

    Snapshots sit outside this repository (in the shared lab-data workspace), so a
    relative path is tried against the workspace root, the repository's parent and the
    repository itself. ``--snapshot-root`` pins the search to one base.
    """
    raw = spec["snapshot"]
    if os.path.isabs(raw):
        return [Path(raw)]
    if snapshot_root is not None:
        return [Path(snapshot_root) / raw]
    bases = [repo_root]
    for parent in repo_root.parents[:2]:
        bases.append(parent)
    return [base / raw for base in bases]


def _matches(where: dict, frontmatter: dict[str, object]) -> bool:
    for clause in where.get("any", []):
        if "in" in clause and frontmatter.get(clause["key"]) in clause["in"]:
            return True
        if "contains_any" in clause:
            values = frontmatter.get(clause["key"]) or []
            if isinstance(values, str):
                values = [values]
            if any(v in values for v in clause["contains_any"]):
                return True
    return False


def derive_selection(
    spec: dict, repo: Path | None, tree: dict[str, str]
) -> tuple[dict[str, SkillRef], int | None]:
    """Re-derive ``{local name: SkillRef}`` (and the upstream universe size) from rules."""
    select = spec["select"]
    kind = select["kind"]
    skills: dict[str, SkillRef] = {}
    universe: int | None = None

    if kind == "in_repo":
        for name in select.get("skills", []):
            skills[name] = SkillRef(name=name)
        return skills, universe

    assert repo is not None
    entry = select.get("entry", DEFAULT_ENTRY)

    def collect(name: str, upstream_dir: str) -> SkillRef:
        prefix = upstream_dir.rstrip("/") + "/"
        files = {p[len(prefix):]: s for p, s in tree.items() if p.startswith(prefix)}
        present = [f for f in files if f == select.get("entry") or f == DEFAULT_ENTRY]
        if not present:
            raise RuleError(f"{spec['id']}: {upstream_dir} carries no {entry!r} at the pin")
        return SkillRef(name=name, upstream_dir=upstream_dir, files=files, entry=present[0])

    if kind == "entry_dirs":
        for path in sorted(tree):
            parts = path.split("/")
            if len(parts) == 2 and parts[1] == entry:
                skills[parts[0]] = collect(parts[0], parts[0])
    elif kind == "explicit":
        for name, upstream_dir in select["map"].items():
            skills[name] = collect(name, upstream_dir)
    elif kind == "frontmatter":
        root = select.get("root", "").rstrip("/")
        prefix = (root + "/") if root else ""
        candidates: dict[str, str] = {}
        for path in sorted(tree):
            if not path.startswith(prefix):
                continue
            rest = path[len(prefix):].split("/")
            if len(rest) == 2 and rest[1] == entry:
                candidates[rest[0]] = tree[path]
        universe = len(candidates)
        expected = select.get("expect_universe")
        if expected is not None and universe != expected:
            raise RuleError(
                f"{spec['id']}: upstream holds {universe} candidates but the rule expects "
                f"{expected}; the pin or the upstream layout changed"
            )
        for name, sha in candidates.items():
            frontmatter = parse_frontmatter(read_blob(repo, sha).decode("utf-8", "replace"))
            if _matches(select.get("where", {}), frontmatter):
                skills[name] = collect(name, prefix + name)
    else:  # pragma: no cover - guarded by load_rules
        raise RuleError(f"{spec['id']}: unsupported select.kind {kind!r}")

    if not skills:
        raise RuleError(f"{spec['id']}: rules select zero skills")
    return skills, universe


def build_plans(
    rules: dict,
    repo_root: Path,
    snapshot_root: Path | None = None,
    only: list[str] | None = None,
    need_upstream: bool = True,
    previous: dict | None = None,
) -> list[SourcePlan]:
    previous = previous or {}
    recorded = {
        source.get("id"): source for source in previous.get("sources", [])
    }
    plans: list[SourcePlan] = []
    for spec in rules["sources"]:
        if only and spec["id"] not in only:
            continue
        sid = spec["id"]
        prior = recorded.get(sid) or {}
        plan = SourcePlan(spec=spec, repo=None, skills={}, recorded=prior)
        if spec["select"]["kind"] == "in_repo":
            plan.skills, _ = derive_selection(spec, None, {})
            plans.append(plan)
            continue
        if not need_upstream:
            plan.skills = {name: SkillRef(name=name) for name in prior.get("skills", [])}
            plans.append(plan)
            continue
        candidates = snapshot_candidates(spec, snapshot_root, repo_root)
        repo = next((path for path in candidates if path.is_dir()), None)
        if repo is None:
            tried = ", ".join(str(path) for path in candidates)
            raise RuleError(
                f"{sid}: snapshot not found (tried {tried}); pass --snapshot-root, fetch "
                "the snapshot, or use --local-only"
            )
        assert_pin_present(repo, spec["commit"])
        selections, universe = derive_selection(spec, repo, upstream_tree(repo, spec["commit"]))
        plan.repo = repo
        plan.skills = selections
        plan.universe = universe
        plans.append(plan)
    if only:
        unknown = sorted(set(only) - {p.spec["id"] for p in plans})
        if unknown:
            raise RuleError(f"--source: unknown source id(s) {', '.join(unknown)}")
    return plans


# --------------------------------------------------------------- destination


def destination_files(plan: SourcePlan) -> dict[str, dict[str, ImportFile]]:
    """``{skill name: {relative path: ImportFile}}`` — what the rules require on disk."""
    spec = plan.spec
    normalize = spec.get("normalize") or {}
    entry_name = normalize.get("entry_name", DEFAULT_ENTRY)
    out: dict[str, dict[str, ImportFile]] = {}
    for skill in plan.skills.values():
        files: dict[str, ImportFile] = {}
        for rel in sorted(skill.files):
            sha = skill.files[rel]
            if skill.entry and rel == skill.entry:
                content = normalize_entry(
                    read_blob(plan.repo, sha), skill.name, normalize
                ) if plan.repo else None
                dest = entry_name
                files[dest] = ImportFile(
                    rel=dest,
                    upstream_sha=sha,
                    blob_sha=blob_sha1(content) if content is not None else sha,
                    content=content,
                )
            else:
                files[rel] = ImportFile(rel=rel, upstream_sha=sha, blob_sha=sha)
        out[skill.name] = files
    return out


def _diff_hint(expected: bytes | None, actual: bytes) -> str:
    if expected is None:
        return ""
    if expected.replace(b"\r\n", b"\n") == actual.replace(b"\r\n", b"\n"):
        return " (line endings differ only)"
    for left, right in zip(expected.splitlines(), actual.splitlines()):
        if left != right:
            return f" (first differing line: expected {left[:60]!r}, found {right[:60]!r})"
    return f" ({len(expected)} vs {len(actual)} bytes)"


# ---------------------------------------------------------------- verification


def check_license_pin(plan: SourcePlan) -> list[Problem]:
    spec = plan.spec
    if plan.repo is None or not spec.get("license_file"):
        return []
    lic = spec["license_file"]
    try:
        upstream = upstream_tree(plan.repo, spec["commit"])
        sha = sha256_normalized(read_blob(plan.repo, upstream[lic["path"]]))
    except KeyError:
        return [Problem("license", f"{spec['id']}: upstream {lic['path']} missing at the pin")]
    if sha != lic["sha256"]:
        return [
            Problem(
                "license",
                f"{spec['id']}: rule pins {lic['sha256'][:12]}… but upstream {lic['path']} "
                f"hashes to {sha[:12]}…",
            )
        ]
    return []


def check_source(
    plan: SourcePlan,
    skills_dir: Path,
    repo_root: Path,
    allow_untracked: bool = False,
) -> list[Problem]:
    problems = check_license_pin(plan)
    spec = plan.spec
    wanted = destination_files(plan)

    for name, files in wanted.items():
        dest_dir = skills_dir / name
        if not dest_dir.is_dir():
            problems.append(Problem("missing", f"{name}/ (whole directory)"))
            continue

        on_disk = {
            path.relative_to(dest_dir).as_posix(): path
            for path in sorted(dest_dir.rglob("*"))
            if path.is_file()
        }
        for rel, want in sorted(files.items()):
            path = dest_dir / rel
            if rel not in on_disk:
                problems.append(Problem("missing", f"{name}/{rel}"))
                continue
            actual_sha = local_blob_sha(repo_root, path)
            if actual_sha != want.blob_sha:
                hint = ""
                if want.content is not None:
                    hint = _diff_hint(want.content, path.read_bytes())
                else:
                    try:
                        hint = _diff_hint(
                            read_blob(plan.repo, want.upstream_sha), path.read_bytes()
                        )
                    except RuleError:  # pragma: no cover - upstream vanished mid-run
                        hint = ""
                problems.append(
                    Problem(
                        "changed",
                        f"{name}/{rel}: expected blob {want.blob_sha[:12]}…, local content "
                        f"is {actual_sha[:12]}…{hint}",
                    )
                )
            if not allow_untracked and not is_tracked(repo_root, path):
                reason = ignore_rule(repo_root, path)
                problems.append(
                    Problem(
                        "untracked",
                        f"{name}/{rel} is not tracked by git"
                        + (f" ({reason})" if reason else "")
                        + " — a fresh clone would silently lose it",
                    )
                )
        for rel in sorted(set(on_disk) - set(files)):
            problems.append(Problem("extra", f"{name}/{rel} is not in the upstream selection"))

        entry_path = dest_dir / (spec.get("normalize") or {}).get("entry_name", DEFAULT_ENTRY)
        if entry_path.is_file():
            frontmatter = parse_frontmatter(entry_path.read_text(encoding="utf-8", errors="replace"))
            if frontmatter.get("name") != name:
                problems.append(
                    Problem(
                        "contract",
                        f"{name}/{entry_path.name} declares name {frontmatter.get('name')!r}; "
                        "the loader requires it to equal the directory name",
                    )
                )
            if not str(frontmatter.get("description", "")).strip():
                problems.append(
                    Problem("contract", f"{name}/{entry_path.name} has no description")
                )
            if not str(frontmatter.get("license", "")).strip() and not spec.get("license"):
                problems.append(
                    Problem("license", f"{name}/{entry_path.name} declares no license")
                )

        if spec.get("license_per_skill") and spec.get("license_file"):
            licence = dest_dir / spec["license_file"]["path"]
            if not licence.is_file():
                problems.append(Problem("license", f"{name}/ has no {licence.name}"))
            elif sha256_normalized(licence.read_bytes()) != spec["license_file"]["sha256"]:
                problems.append(
                    Problem("license", f"{name}/{licence.name} is not the pinned license text")
                )
    return problems


def check_local_only(plan: SourcePlan, skills_dir: Path, repo_root: Path) -> list[Problem]:
    """No snapshot available: still insist nothing imported is untracked or absent."""
    problems: list[Problem] = []
    for skill in plan.skills.values():
        dest_dir = skills_dir / skill.name
        if not dest_dir.is_dir():
            problems.append(Problem("missing", f"{skill.name}/ (whole directory)"))
            continue
        if not (dest_dir / DEFAULT_ENTRY).is_file():
            problems.append(Problem("missing", f"{skill.name}/{DEFAULT_ENTRY}"))
        for path in sorted(dest_dir.rglob("*")):
            if path.is_file() and not is_tracked(repo_root, path):
                reason = ignore_rule(repo_root, path)
                problems.append(
                    Problem(
                        "untracked",
                        f"{skill.name}/{path.relative_to(dest_dir).as_posix()} is not tracked"
                        + (f" ({reason})" if reason else ""),
                    )
                )
    return problems


def build_sources_payload(rules: dict, plans: list[SourcePlan]) -> dict:
    by_id = {plan.spec["id"]: plan for plan in plans}
    sources = []
    for spec in rules["sources"]:
        plan = by_id.get(spec["id"])
        entry: dict[str, object] = {
            "id": spec["id"],
            "label": spec.get("label", spec["id"]),
            "snapshot": spec.get("snapshot", "(in-repo)"),
            "commit": spec.get("commit", ""),
            "license": spec.get("license", "Not specified"),
        }
        if plan is not None:
            universe = plan.universe
            if universe is None:
                universe = plan.recorded.get("upstream_total")
            if universe is not None:
                entry["upstream_total"] = universe
        if spec.get("selection"):
            entry["selection"] = spec["selection"]
        entry["skills"] = sorted(plan.skills) if plan else []
        sources.append(entry)
    return {
        "version": rules.get("version", 1),
        "description": PROVENANCE_DESCRIPTION,
        "rules": "skills/import-rules.json",
        "verified_by": VERIFIED_BY,
        "sources": sources,
    }


def write_sources_payload(payload: dict, path: Path = SOURCES_PATH) -> bool:
    text = json.dumps(payload, indent=2, ensure_ascii=False) + "\n"
    if path.is_file() and path.read_text(encoding="utf-8") == text:
        return False
    path.write_text(text, encoding="utf-8", newline="\n")
    return True


def check_attribution(plans: list[SourcePlan], rules: dict, skills_dir: Path) -> list[Problem]:
    """SOURCES.json must equal what the rules imply, and cover every skill directory."""
    problems: list[Problem] = []
    sources_path = skills_dir / "SOURCES.json"
    payload = build_sources_payload(rules, plans)
    if not sources_path.is_file():
        problems.append(Problem("sources", f"{sources_path.name} is missing"))
    elif json.loads(sources_path.read_text(encoding="utf-8")) != payload:
        problems.append(
            Problem(
                "sources",
                f"{sources_path.name} does not match the rules (re-run the importer "
                "without --check to regenerate it)",
            )
        )

    claimed: dict[str, str] = {}
    for plan in plans:
        for name in plan.skills:
            if name in claimed:
                problems.append(
                    Problem("sources", f"{name} is claimed by both {claimed[name]} and {plan.spec['id']}")
                )
            claimed[name] = plan.spec["id"]
    for path in sorted(skills_dir.glob("*/SKILL.md")):
        if path.parent.name not in claimed:
            problems.append(
                Problem("sources", f"{path.parent.name}/ exists on disk but no rule selects it")
            )
    return problems


# ------------------------------------------------------------------- index


def _index_module():
    tools_dir = Path(__file__).resolve().parent
    if str(tools_dir) not in sys.path:
        sys.path.insert(0, str(tools_dir))
    import generate_skill_index  # noqa: PLC0415 - deliberately lazy

    return generate_skill_index


@contextlib.contextmanager
def _point_index_at(skills_dir: Path):
    """Aim generate_skill_index at skills_dir, restoring its module paths on exit."""
    index = _index_module()
    names = ("REPO_ROOT", "SKILLS_DIR", "SOURCES_PATH", "INDEX_PATH")
    saved = {name: getattr(index, name) for name in names}
    # skills_dir is <repo>/skills; index paths are rendered relative to that repo.
    index.REPO_ROOT = skills_dir.resolve().parent
    index.SKILLS_DIR = skills_dir
    index.SOURCES_PATH = skills_dir / "SOURCES.json"
    index.INDEX_PATH = skills_dir / "INDEX.md"
    try:
        yield index
    finally:
        for name, value in saved.items():
            setattr(index, name, value)


def regenerate_index(skills_dir: Path) -> None:
    with _point_index_at(skills_dir) as index:
        code = index.main([])
    if code != 0:  # pragma: no cover - defensive
        raise RuleError(f"index regeneration failed with exit {code}")


def check_index(skills_dir: Path) -> list[Problem]:
    captured = io.StringIO()
    with _point_index_at(skills_dir) as index, contextlib.redirect_stderr(
        captured
    ), contextlib.redirect_stdout(io.StringIO()):
        code = index.main(["--check"])
    if code == 0:
        return []
    detail = captured.getvalue().strip().splitlines()
    return [Problem("index", detail[0] if detail else "INDEX.md is stale")]


# ------------------------------------------------------------------- apply


@dataclass
class ApplyStats:
    written: int = 0
    unchanged: int = 0
    removed_files: list[str] = field(default_factory=list)
    removed_skills: list[str] = field(default_factory=list)

    @property
    def total(self) -> int:
        return self.written + self.unchanged


def apply_plan(
    plan: SourcePlan, skills_dir: Path, repo_root: Path, prune: bool = True
) -> ApplyStats:
    """Materialise the plan on disk; only files that differ are rewritten."""
    stats = ApplyStats()
    if plan.repo is None:
        return stats
    managed = set(plan.skills)
    for stale in sorted(set(plan.recorded.get("skills", [])) - managed):
        stale_dir = skills_dir / stale
        if stale_dir.is_dir():
            shutil.rmtree(stale_dir)
            stats.removed_skills.append(stale)

    wanted = destination_files(plan)
    for name, files in sorted(wanted.items()):
        dest_dir = skills_dir / name
        dest_dir.mkdir(parents=True, exist_ok=True)
        for rel, want in sorted(files.items()):
            target = dest_dir / rel
            expected = want.content
            if expected is None:
                expected = read_blob(plan.repo, want.upstream_sha)
            target.parent.mkdir(parents=True, exist_ok=True)
            if target.is_file() and local_blob_sha(repo_root, target) == want.blob_sha:
                stats.unchanged += 1
                continue
            target.write_bytes(expected)
            stats.written += 1
        if prune:
            for path in sorted(dest_dir.rglob("*"), key=lambda p: len(p.parts), reverse=True):
                rel = path.relative_to(dest_dir).as_posix()
                if path.is_file() and rel not in files:
                    path.unlink()
                    stats.removed_files.append(f"{name}/{rel}")
                elif path.is_dir() and not any(path.iterdir()):
                    path.rmdir()
    return stats


# --------------------------------------------------------------------- main


def _load_previous_sources(path: Path) -> dict:
    if not path.is_file():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Import and verify the external skills under skills/"
    )
    parser.add_argument("--check", action="store_true", help="verify only; never write")
    parser.add_argument(
        "--local-only",
        action="store_true",
        help="with --check: verify provenance/directory consistency without the snapshots",
    )
    parser.add_argument("--source", action="append", default=[], help="limit to one source id")
    parser.add_argument("--rules", default=None, help="override the rules file path")
    parser.add_argument(
        "--snapshot-root",
        default=None,
        help="directory holding the external snapshots (default: the repository's parent)",
    )
    parser.add_argument(
        "--allow-untracked",
        action="store_true",
        help="do not fail on imported files that git does not track (local experiments)",
    )
    parser.add_argument("--no-prune", action="store_true", help="keep files the rules do not want")
    parser.add_argument("--json", action="store_true", help="machine-readable report")
    parser.add_argument("--quiet", action="store_true", help="only report problems")
    args = parser.parse_args(argv)

    repo_root = REPO_ROOT
    skills_dir = SKILLS_DIR
    rules_path = Path(args.rules).resolve() if args.rules else RULES_PATH
    snapshot_root = Path(args.snapshot_root).resolve() if args.snapshot_root else None
    sources_path = skills_dir / "SOURCES.json"

    if args.local_only and not args.check:
        print("ERROR --local-only only applies to --check", file=sys.stderr)
        return 2
    if args.source and not args.check:
        print(
            "ERROR --source requires --check: applying always rewrites the full provenance file",
            file=sys.stderr,
        )
        return 2

    try:
        rules = load_rules(rules_path)
        plans = build_plans(
            rules,
            repo_root,
            snapshot_root,
            only=args.source or None,
            need_upstream=not args.local_only,
            previous=_load_previous_sources(sources_path),
        )
    except RuleError as exc:
        print(f"ERROR {exc}", file=sys.stderr)
        return 2

    report: dict[str, object] = {"mode": "check" if args.check else "apply", "sources": []}
    problems: list[Problem] = []

    if args.check:
        for plan in plans:
            sid = plan.spec["id"]
            if plan.repo is None:
                found = check_local_only(plan, skills_dir, repo_root)
            else:
                found = check_source(plan, skills_dir, repo_root, args.allow_untracked)
            problems += found
            files = sum(len(f) for f in destination_files(plan).values()) if plan.repo else 0
            report["sources"].append(
                {"id": sid, "skills": len(plan.skills), "files": files,
                 "problems": [str(p) for p in found],
                 "snapshot": str(plan.repo) if plan.repo else None,
                 "pin": plan.spec.get("commit", "")}
            )
            if not args.quiet:
                verdict = "ok" if not found else f"{len(found)} problem(s)"
                label = f"{sid:<32}"
                counts = f"{len(plan.skills):>3} skills"
                file_count = f"{files:>4} files" if files else "     local"
                print(f"  {label} {counts} {file_count}  {verdict}")
            if plan.repo is not None and not args.quiet:
                delta = head_delta(plan.repo, plan.spec["commit"])
                if delta:
                    print(
                        f"    note: snapshot HEAD is {delta} commit(s) ahead of the pin "
                        f"{plan.spec['commit'][:8]} (content verified at the pin)"
                    )
        if not args.source:
            extra = check_attribution(plans, rules, skills_dir) + check_index(skills_dir)
            problems += extra
            for problem in extra:
                print(f"  {problem}", file=sys.stderr)
    else:
        totals = ApplyStats()
        for plan in plans:
            stats = apply_plan(plan, skills_dir, repo_root, prune=not args.no_prune)
            totals.written += stats.written
            totals.unchanged += stats.unchanged
            totals.removed_files += stats.removed_files
            totals.removed_skills += stats.removed_skills
            report["sources"].append(
                {
                    "id": plan.spec["id"],
                    "skills": len(plan.skills),
                    "written": stats.written,
                    "unchanged": stats.unchanged,
                    "removed_files": stats.removed_files,
                    "removed_skills": stats.removed_skills,
                }
            )
            if not args.quiet:
                print(
                    f"  {plan.spec['id']:<32} {len(plan.skills):>3} skills  "
                    f"{stats.written:>4} written  {stats.unchanged:>4} unchanged"
                )
        wrote = write_sources_payload(build_sources_payload(rules, plans), sources_path)
        regenerate_index(skills_dir)
        if not args.quiet:
            print(f"  provenance: {'rewritten' if wrote else 'already current'} ({sources_path.name})")
            if totals.removed_files:
                print(f"  pruned {len(totals.removed_files)} stale file(s)")
            if totals.removed_skills:
                print(f"  dropped {len(totals.removed_skills)} de-selected skill dir(s)")

        # An apply that leaves drift behind is a failure, not a success.
        for plan in plans:
            if plan.repo is not None:
                problems += check_source(plan, skills_dir, repo_root, args.allow_untracked)
        problems += check_attribution(plans, rules, skills_dir) + check_index(skills_dir)

    report["problems"] = [str(p) for p in problems]
    report["ok"] = not problems
    if args.json:
        print(json.dumps(report, indent=2, ensure_ascii=False))
    elif not problems:
        skills_total = sum(len(p.skills) for p in plans)
        files_total = sum(
            len(f) for plan in plans if plan.repo for f in destination_files(plan).values()
        )
        scope = "local-only" if args.local_only else "3 pinned snapshots"
        print(
            f"OK {skills_total} skills"
            + (f", {files_total} files verified against {scope}" if files_total else f" ({scope})")
            + ", 0 drift"
        )
    else:
        for problem in problems:
            print(f"  {problem}", file=sys.stderr)
        print(
            f"ERROR {len(problems)} drift problem(s); "
            + ("fix the imports or the rules" if args.check else "apply did not converge"),
            file=sys.stderr,
        )
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())

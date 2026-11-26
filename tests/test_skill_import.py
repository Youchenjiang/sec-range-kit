"""Tests for ``tools/skill_import.py``.

Everything runs against throw-away git repositories built in a temp directory, so the
suite never touches the real ``skills/`` tree or the external snapshots. The two
integration tests at the bottom do look at the real workspace, but degrade gracefully:
the full upstream re-hash is skipped when the snapshots are not on this machine, and the
local-only check needs nothing but the repository itself.
"""

import contextlib
import io
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


TOOLS_DIR = Path(__file__).resolve().parents[1] / "tools"
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

import skill_import as si  # noqa: E402


def _git(cwd: Path, *args: str) -> str:
    proc = subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, check=False)
    if proc.returncode != 0:
        raise AssertionError(
            f"git {' '.join(args)} failed in {cwd}: {proc.stderr.decode('utf-8', 'replace')}"
        )
    return proc.stdout.decode("utf-8", "replace")


def make_repo(path: Path, autocrlf: str = "false") -> Path:
    path.mkdir(parents=True, exist_ok=True)
    _git(path, "init", "-q")
    _git(path, "config", "core.autocrlf", autocrlf)
    _git(path, "config", "user.name", "test")
    _git(path, "config", "user.email", "test@example.invalid")
    return path


def commit_all(path: Path, message: str = "fixture") -> None:
    _git(path, "add", "-A")
    _git(path, "commit", "-q", "-m", message, "--no-gpg-sign")


class Upstream:
    """A synthetic external snapshot with a handful of skills."""

    def __init__(self, root: Path):
        self.path = make_repo(root / "snapshots" / "upstream")
        files = {
            # verbatim skill: entry file already well-formed
            "alpha/SKILL.md": "---\nname: alpha\ndescription: Alpha skill\n---\nbody\n",
            "alpha/extra.md": "alpha reference\n",
            # needs the documented normalisation: entry renamed + frontmatter tidied
            "beta/skill.md": (
                "---\n# Skill metadata\nname: \"Beta skill\"\n"
                "description: \"Beta skill description\"\nversion: \"1.0\"\n---\nbody\n"
            ),
            "beta/notes.md": "beta notes\n",
            # excluded by the subdomain rule
            "gamma/SKILL.md": "---\nname: gamma\ndescription: Gamma\nsubdomain: red-teaming\n---\nx\n",
            # kept by the memory-forensics tag (flush-left YAML list)
            "delta/SKILL.md": (
                "---\nname: delta\ndescription: Delta\ndomain: cybersecurity\n"
                "tags:\n- memory-forensics\n- windows\n---\nbody\n"
            ),
            "delta/scripts/probe.py": "print('probe')\n",
            "epsilon/SKILL.md": "---\nname: epsilon\ndescription: Epsilon\n---\nbody\n",
            "LICENSE": "MIT License\n\nfixture licence text\n",
        }
        for rel, text in files.items():
            target = self.path / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text, encoding="utf-8", newline="\n")
        commit_all(self.path)
        self.commit = _git(self.path, "rev-parse", "HEAD").strip()


def rules_for(upstream: Upstream, **overrides) -> dict:
    """Rules whose three sources together select alpha, beta and delta/epsilon."""
    base = {
        "version": 1,
        "sources": [
            {
                "id": "verbatim",
                "label": "verbatim source",
                "snapshot": str(upstream.path),
                "commit": upstream.commit,
                "license": "MIT",
                "license_file": {
                    "path": "LICENSE",
                    "sha256": si.sha256_normalized((upstream.path / "LICENSE").read_bytes()),
                },
                "select": {"kind": "entry_dirs", "entry": "SKILL.md"},
                "normalize": {"entry_name": "SKILL.md"},
            },
            {
                "id": "normalised",
                "label": "normalised source",
                "snapshot": str(upstream.path),
                "commit": upstream.commit,
                "license": "MIT",
                "selection": "explicit allowlist with entry rename",
                "select": {"kind": "explicit", "entry": "skill.md", "map": {"beta": "beta"}},
                "normalize": {
                    "entry_name": "SKILL.md",
                    "frontmatter": {
                        "strip_comments": True,
                        "unquote": ["name", "description"],
                        "set_name": True,
                    },
                },
            },
            {
                "id": "internal",
                "label": "framework internal",
                "snapshot": "(in-repo)",
                "commit": "",
                "license": "internal",
                "select": {"kind": "in_repo", "skills": ["local-skill"]},
            },
        ],
    }
    base.update(overrides)
    return base


_TEMPLATE: tempfile.TemporaryDirectory | None = None
_TEMPLATE_COMMIT = ""


def _template_root() -> Path:
    """Build the git repositories behind ``Case`` once per module; each Case copies them.

    Every git call costs tens of milliseconds on Windows, and rebuilding the two
    repositories for each of ~40 tests dominated the run.
    """
    global _TEMPLATE, _TEMPLATE_COMMIT
    if _TEMPLATE is None:
        _TEMPLATE = tempfile.TemporaryDirectory()
        root = Path(_TEMPLATE.name)
        repo = make_repo(root / "repo")
        (repo / "skills").mkdir(parents=True)
        _TEMPLATE_COMMIT = Upstream(root).commit
    return Path(_TEMPLATE.name)


def tearDownModule() -> None:
    if _TEMPLATE is not None:
        _TEMPLATE.cleanup()


class _CopiedUpstream:
    """The template's upstream snapshot at its copied location (same commit)."""

    def __init__(self, path: Path, commit: str):
        self.path = path
        self.commit = commit


class Case:
    """A temp workspace: one destination repo plus one upstream snapshot."""

    def __init__(self, tmp: str):
        self.root = Path(tmp)
        shutil.copytree(_template_root(), self.root, dirs_exist_ok=True)
        self.repo = self.root / "repo"
        self.skills = self.repo / "skills"
        self.upstream = _CopiedUpstream(self.root / "snapshots" / "upstream", _TEMPLATE_COMMIT)
        self.rules_path = self.skills / "import-rules.json"
        # the rules hold absolute snapshot paths, so they are written after the copy
        self.rules = rules_for(self.upstream)
        self.write_rules()
        local = self.skills / "local-skill"
        local.mkdir()
        (local / "SKILL.md").write_text(
            "---\nname: local-skill\ndescription: Internal skill\n---\nbody\n", encoding="utf-8"
        )
        commit_all(self.repo, "fixture baseline")

    def write_rules(self, rules: dict | None = None) -> None:
        self.rules_path.write_text(
            json.dumps(rules or self.rules, indent=2), encoding="utf-8"
        )

    def plans(self, **kwargs) -> list:
        return si.build_plans(
            si.load_rules(self.rules_path), self.repo, None, **kwargs
        )

    def plan(self, source_id: str):
        return next(((p for p in self.plans() if p.spec["id"] == source_id)), None)

    def run(self, argv: list[str]) -> tuple[int, str, str]:
        """Drive ``main`` against this workspace, capturing its output."""
        stdout, stderr = io.StringIO(), io.StringIO()
        with (
            patch.object(si, "REPO_ROOT", self.repo),
            patch.object(si, "SKILLS_DIR", self.skills),
            patch.object(si, "RULES_PATH", self.rules_path),
            contextlib.redirect_stdout(stdout),
            contextlib.redirect_stderr(stderr),
        ):
            code = si.main(argv)
        return code, stdout.getvalue(), stderr.getvalue()

    def apply(self) -> tuple[int, str, str]:
        # apply verifies its own result; freshly written imports are not committed yet.
        return self.run(["--allow-untracked"])

    def check(self, *extra: str) -> tuple[int, str, str]:
        return self.run(["--check", *extra])


class SelectionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.case = Case(self.tmp.name)

    def test_entry_dirs_selects_every_directory_with_the_entry_file(self):
        plan = self.case.plan("verbatim")
        self.assertEqual(sorted(plan.skills), ["alpha", "delta", "epsilon", "gamma"])
        self.assertIsNone(plan.universe)

    def test_explicit_rule_uses_the_declared_upstream_directory(self):
        plan = self.case.plan("normalised")
        self.assertEqual(list(plan.skills), ["beta"])
        self.assertEqual(plan.skills["beta"].upstream_dir, "beta")
        self.assertEqual(plan.skills["beta"].entry, "skill.md")
        self.assertEqual(
            sorted(plan.skills["beta"].files), ["notes.md", "skill.md"]
        )

    def test_frontmatter_rule_matches_subdomain_or_flush_left_tags(self):
        rules = si.load_rules(self.case.rules_path)
        rules["sources"][0]["select"] = {
            "kind": "frontmatter",
            "root": "",
            "entry": "SKILL.md",
            "expect_universe": 4,
            "where": {
                "any": [
                    {"key": "subdomain", "in": ["digital-forensics", "incident-response"]},
                    {"key": "tags", "contains_any": ["memory-forensics"]},
                ]
            },
        }
        plan = si.build_plans(rules, self.case.repo, None)[0]
        # gamma is red-teaming and alpha/epsilon carry neither key (dropped);
        # delta is kept by its flush-left tag list
        self.assertEqual(sorted(plan.skills), ["delta"])
        self.assertEqual(plan.universe, 4)

    def test_universe_mismatch_is_a_configuration_error(self):
        rules = si.load_rules(self.case.rules_path)
        rules["sources"][0]["select"] = {
            "kind": "frontmatter",
            "root": "",
            "entry": "SKILL.md",
            "expect_universe": 818,
            "where": {"any": [{"key": "name", "in": ["alpha"]}]},
        }
        with self.assertRaises(si.RuleError) as ctx:
            si.build_plans(rules, self.case.repo, None)
        self.assertIn("expects", str(ctx.exception))

    def test_rules_reject_unknown_selection_kind(self):
        rules = si.load_rules(self.case.rules_path)
        rules["sources"][0]["select"] = {"kind": "guesswork"}
        self.case.write_rules(rules)
        with self.assertRaises(si.RuleError):
            si.load_rules(self.case.rules_path)

    def test_missing_snapshot_points_at_the_tried_paths(self):
        rules = si.load_rules(self.case.rules_path)
        rules["sources"][0]["snapshot"] = str(self.case.root / "nowhere")
        self.case.write_rules(rules)
        with self.assertRaises(si.RuleError) as ctx:
            self.case.plans()
        self.assertIn("snapshot not found", str(ctx.exception))

    def test_unknown_pin_is_a_configuration_error(self):
        rules = si.load_rules(self.case.rules_path)
        rules["sources"][0]["commit"] = "0" * 40
        self.case.write_rules(rules)
        with self.assertRaises(si.RuleError) as ctx:
            self.case.plans()
        self.assertIn("not in the snapshot", str(ctx.exception))

    def test_relative_snapshot_is_found_next_to_the_repository(self):
        rules = si.load_rules(self.case.rules_path)
        rules["sources"][0]["snapshot"] = "snapshots/upstream"
        self.case.write_rules(rules)
        plan = si.build_plans(rules, self.case.repo, None, only=["verbatim"])[0]
        self.assertEqual(plan.repo, self.case.upstream.path)


class NormalisationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.case = Case(self.tmp.name)

    def test_entry_is_renamed_and_frontmatter_tidied(self):
        plan = self.case.plan("normalised")
        files = si.destination_files(plan)["beta"]
        self.assertIn("SKILL.md", files)
        self.assertNotIn("skill.md", files)
        text = files["SKILL.md"].content.decode()
        self.assertIn("name: beta\n", text)
        self.assertIn("description: Beta skill description\n", text)
        self.assertNotIn("# Skill metadata", text)
        # only the keys the rule names are unquoted; other lines keep their bytes
        self.assertNotIn('"Beta', text.split("---")[1])
        self.assertTrue(text.endswith("body\n"))

    def test_untouched_lines_keep_their_bytes(self):
        plan = self.case.plan("normalised")
        files = si.destination_files(plan)["beta"]
        self.assertIn('version: "1.0"', files["SKILL.md"].content.decode())

    def test_no_op_normalisation_reproduces_the_upstream_blob(self):
        plan = self.case.plan("verbatim")
        files = si.destination_files(plan)
        for sha in plan.skills["alpha"].files.values():
            self.assertIn(sha, {f.upstream_sha for f in files["alpha"].values()})
        self.assertEqual(
            files["alpha"]["SKILL.md"].blob_sha,
            plan.skills["alpha"].files["SKILL.md"],
        )

    def test_frontmatter_parser_reads_scalars_and_flush_left_lists(self):
        text = (
            "---\nname: delta\nsubdomain: threat-hunting\n"
            "tags:\n- memory-forensics\n- windows\n---\nbody\n"
        )
        frontmatter = si.parse_frontmatter(text)
        self.assertEqual(frontmatter["name"], "delta")
        self.assertEqual(frontmatter["subdomain"], "threat-hunting")
        self.assertEqual(frontmatter["tags"], ["memory-forensics", "windows"])

    def test_entry_without_frontmatter_is_a_configuration_error(self):
        with self.assertRaises(si.RuleError):
            si.normalize_entry(b"no frontmatter here\n", "beta", {"frontmatter": {"set_name": True}})


class VerificationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.case = Case(self.tmp.name)
        code, _, _ = self.case.apply()
        self.assertEqual(code, 0, "fixture apply should succeed")
        commit_all(self.case.repo, "import skills")

    def problems(self, source_id: str, **kwargs) -> list:
        plan = self.case.plan(source_id)
        return si.check_source(plan, self.case.skills, self.case.repo, **kwargs)

    def test_apply_materialises_the_selection(self):
        self.assertTrue((self.case.skills / "alpha" / "SKILL.md").is_file())
        self.assertTrue((self.case.skills / "beta" / "SKILL.md").is_file())
        self.assertTrue((self.case.skills / "delta" / "scripts" / "probe.py").is_file())
        # entry_dirs selects every directory carrying the entry file, gamma included
        self.assertTrue((self.case.skills / "gamma" / "SKILL.md").is_file())

    def test_fresh_tree_verifies_clean(self):
        self.assertEqual(self.problems("verbatim"), [])
        self.assertEqual(self.problems("normalised"), [])

    def test_tampered_file_is_reported_as_changed(self):
        target = self.case.skills / "alpha" / "extra.md"
        target.write_text("tampered\n", encoding="utf-8", newline="\n")
        problems = [str(p) for p in self.problems("verbatim")]
        self.assertTrue(any("alpha/extra.md" in p and "changed" in p for p in problems), problems)

    def test_deleted_file_is_reported_as_missing(self):
        (self.case.skills / "alpha" / "extra.md").unlink()
        problems = [str(p) for p in self.problems("verbatim")]
        self.assertTrue(any("missing: alpha/extra.md" in p for p in problems), problems)

    def test_extra_file_is_reported(self):
        (self.case.skills / "alpha" / "smuggled.md").write_text("x\n", encoding="utf-8")
        problems = [str(p) for p in self.problems("verbatim")]
        self.assertTrue(any("extra: alpha/smuggled.md" in p for p in problems), problems)

    def test_untracked_import_is_reported_unless_allowed(self):
        # tracking is checked for selected files; a stray file is reported as "extra"
        _git(self.case.repo, "rm", "-q", "--cached", "skills/alpha/extra.md")
        problems = [str(p) for p in self.problems("verbatim")]
        self.assertTrue(any("untracked: alpha/extra.md" in p for p in problems), problems)
        problems = [str(p) for p in self.problems("verbatim", allow_untracked=True)]
        self.assertFalse(any("untracked" in p for p in problems), problems)

    def test_ignored_import_names_the_gitignore_rule(self):
        # a selected file that an ignore rule keeps out of the index names that rule
        _git(self.case.repo, "rm", "-q", "--cached", "skills/delta/scripts/probe.py")
        (self.case.repo / ".gitignore").write_text("*.py\n", encoding="utf-8")
        commit_all(self.case.repo, "ignore rule")
        problems = [str(p) for p in self.problems("verbatim")]
        self.assertTrue(
            any("probe.py" in p and ".gitignore" in p for p in problems), problems
        )

    def test_directory_name_and_frontmatter_name_must_agree(self):
        entry = self.case.skills / "alpha" / "SKILL.md"
        entry.write_text(
            entry.read_text(encoding="utf-8").replace("name: alpha", "name: alpha-renamed"),
            encoding="utf-8",
            newline="\n",
        )
        problems = [str(p) for p in self.problems("verbatim")]
        self.assertTrue(any("contract" in p for p in problems), problems)

    def test_license_pin_is_verified(self):
        rules = json.loads(self.case.rules_path.read_text(encoding="utf-8"))
        rules["sources"][0]["license_file"]["sha256"] = "0" * 64
        self.case.write_rules(rules)
        problems = [str(p) for p in self.problems("verbatim")]
        self.assertTrue(any("license" in p for p in problems), problems)

    def test_local_only_still_fails_on_untracked_files(self):
        (self.case.skills / "alpha" / "smuggled.md").write_text("x\n", encoding="utf-8")
        code, _, stderr = self.case.check("--local-only")
        self.assertEqual(code, 1)
        self.assertIn("smuggled.md", stderr)

    def test_local_only_passes_on_a_clean_committed_tree(self):
        code, _, stderr = self.case.check("--local-only")
        self.assertEqual(code, 0, stderr)


class ApplyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.case = Case(self.tmp.name)

    def test_apply_then_check_is_clean_and_idempotent(self):
        code, _, stderr = self.case.apply()
        self.assertEqual(code, 0, stderr)
        commit_all(self.case.repo, "import skills")
        code, _, stderr = self.case.check()
        self.assertEqual(code, 0, stderr)
        code, stdout, _ = self.case.apply()
        self.assertEqual(code, 0)
        self.assertIn("0 written", stdout)

    def test_apply_rewrites_provenance_from_the_rules(self):
        self.case.apply()
        payload = json.loads((self.case.skills / "SOURCES.json").read_text(encoding="utf-8"))
        self.assertEqual(payload["rules"], "skills/import-rules.json")
        self.assertIn("--check", payload["verified_by"])
        by_id = {source["id"]: source for source in payload["sources"]}
        self.assertEqual(by_id["verbatim"]["skills"], ["alpha", "delta", "epsilon", "gamma"])
        self.assertEqual(by_id["normalised"]["skills"], ["beta"])
        self.assertEqual(by_id["internal"]["skills"], ["local-skill"])
        self.assertEqual(by_id["normalised"]["commit"], self.case.upstream.commit)
        self.assertEqual(by_id["normalised"]["label"], "normalised source")

    def test_apply_prunes_files_that_the_rules_do_not_want(self):
        self.case.apply()
        stale = self.case.skills / "alpha" / "stale.md"
        stale.write_text("stale\n", encoding="utf-8")
        code, stdout, stderr = self.case.apply()
        self.assertEqual(code, 0, stderr)
        self.assertFalse(stale.exists())
        self.assertIn("pruned", stdout)

    def test_apply_drops_a_deselected_skill_directory(self):
        self.case.apply()
        self.assertTrue((self.case.skills / "epsilon").is_dir())
        rules = json.loads(self.case.rules_path.read_text(encoding="utf-8"))
        rules["sources"][0]["select"] = {
            "kind": "explicit",
            "entry": "SKILL.md",
            "map": {"alpha": "alpha", "delta": "delta"},
        }
        self.case.write_rules(rules)
        code, stdout, stderr = self.case.apply()
        self.assertEqual(code, 0, stderr)
        self.assertFalse((self.case.skills / "epsilon").exists())
        self.assertIn("dropped", stdout)

    def test_apply_refreshes_the_index_and_a_stale_index_fails_check(self):
        self.case.apply()
        index = (self.case.skills / "INDEX.md").read_text(encoding="utf-8")
        self.assertIn("| 名稱 | 描述 |", index)
        self.assertIn("`beta`", index)
        (self.case.skills / "INDEX.md").write_text("# stale\n", encoding="utf-8")
        problems = [str(p) for p in si.check_index(self.case.skills)]
        self.assertTrue(any("index" in p for p in problems), problems)

    def test_apply_refuses_source_filter(self):
        code, _, stderr = self.case.run(["--source", "verbatim"])
        self.assertEqual(code, 2)
        self.assertIn("--source requires --check", stderr)

    def test_local_only_cannot_apply(self):
        code, _, stderr = self.case.run(["--local-only"])
        self.assertEqual(code, 2)
        self.assertIn("--local-only", stderr)

    def test_check_json_report_is_machine_readable(self):
        self.case.apply()
        commit_all(self.case.repo, "import skills")
        # --quiet suppresses the per-source progress lines so stdout is pure JSON
        code, stdout, _ = self.case.check("--json", "--quiet")
        self.assertEqual(code, 0)
        report = json.loads(stdout)
        self.assertTrue(report["ok"])
        self.assertEqual(report["mode"], "check")
        self.assertEqual(
            sorted(source["id"] for source in report["sources"]),
            ["internal", "normalised", "verbatim"],
        )

    def test_attribution_rejects_a_skill_no_rule_selects(self):
        self.case.apply()
        intruder = self.case.skills / "intruder"
        intruder.mkdir()
        (intruder / "SKILL.md").write_text(
            "---\nname: intruder\ndescription: smuggled\n---\n", encoding="utf-8"
        )
        problems = [str(p) for p in si.check_attribution(self.case.plans(), self.case.rules, self.case.skills)]
        self.assertTrue(any("intruder" in p for p in problems), problems)


class BlobHashingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def test_working_tree_crlf_still_matches_the_lf_blob(self):
        repo = make_repo(self.root / "crlf", autocrlf="true")
        target = repo / "note.md"
        target.write_bytes(b"first\nsecond\n")
        expected = si.blob_sha1(b"first\nsecond\n")
        target.write_bytes(b"first\r\nsecond\r\n")
        self.assertEqual(si.local_blob_sha(repo, target), expected)
        self.assertNotEqual(si.blob_sha1(target.read_bytes()), expected)

    def test_sha256_normalization_matches_crlf_variants(self):
        self.assertEqual(
            si.sha256_normalized(b"a\r\nb\r\n"), si.sha256_normalized(b"a\nb\n")
        )

    def test_untracked_detection_uses_the_index(self):
        repo = make_repo(self.root / "plain")
        tracked = repo / "tracked.txt"
        tracked.write_text("x\n", encoding="utf-8")
        commit_all(repo)
        untracked = repo / "loose.txt"
        untracked.write_text("y\n", encoding="utf-8")
        self.assertTrue(si.is_tracked(repo, tracked))
        self.assertFalse(si.is_tracked(repo, untracked))
        self.assertIsNone(si.ignore_rule(repo, untracked))
        self.assertEqual(si.tracked_files(repo), {"tracked.txt"})

    def test_batched_hashes_match_single_calls_including_crlf(self):
        repo = make_repo(self.root / "batch", autocrlf="true")
        files = []
        for i, body in enumerate([b"a\r\nb\r\n", b"plain\n", b""]):
            path = repo / "dir with space" / f"n{i}.md"
            path.parent.mkdir(exist_ok=True)
            path.write_bytes(body)
            files.append(path)
        batched = si.local_blob_shas(repo, files)
        self.assertEqual(batched, {p: si.local_blob_sha(repo, p) for p in files})
        self.assertEqual(si.local_blob_shas(repo, []), {})

    def test_batched_blob_reads_match_single_reads(self):
        repo = make_repo(self.root / "blobs")
        bodies = [b"one\n", b"two\nlines\n", b"", b"\x00binary\xff"]
        shas = []
        for i, body in enumerate(bodies):
            (repo / f"f{i}").write_bytes(body)
            shas.append(si.blob_sha1(body))
        commit_all(repo)
        si._BLOB_CACHE.clear()
        self.assertEqual(si.read_blobs(repo, shas), dict(zip(shas, bodies)))
        self.assertEqual(si.read_blob(repo, shas[1]), bodies[1])

    def test_batched_blob_read_reports_a_missing_object(self):
        repo = make_repo(self.root / "missing")
        (repo / "f").write_bytes(b"x\n")
        commit_all(repo)
        with self.assertRaises(si.RuleError):
            si.read_blobs(repo, ["0" * 40])


class RealWorkspaceTests(unittest.TestCase):
    """Integration: the committed tree must satisfy its own rules."""

    def test_rules_file_is_valid_and_covers_every_skill(self):
        rules = si.load_rules(si.RULES_PATH)
        # without snapshots, imported skill lists come from the recorded SOURCES.json
        previous = json.loads((si.SKILLS_DIR / "SOURCES.json").read_text(encoding="utf-8"))
        plans = si.build_plans(
            rules, si.REPO_ROOT, None, need_upstream=False, previous=previous
        )
        claimed = {name for plan in plans for name in plan.skills}
        on_disk = {path.parent.name for path in si.SKILLS_DIR.glob("*/SKILL.md")}
        self.assertEqual(claimed, on_disk)

    def test_local_only_check_passes_on_the_committed_tree(self):
        code, _, stderr = self._run(["--check", "--local-only"])
        self.assertEqual(code, 0, stderr)

    @unittest.skipUnless(
        all(
            (si.REPO_ROOT.parents[1] / source["snapshot"]).is_dir()
            or (si.REPO_ROOT.parent / source["snapshot"]).is_dir()
            for source in json.loads(si.RULES_PATH.read_text(encoding="utf-8"))["sources"]
            if source.get("select", {}).get("kind") != "in_repo"
        ),
        "external snapshots are not present on this machine",
    )
    def test_full_check_rehashes_every_imported_file(self):
        code, stdout, stderr = self._run(["--check"])
        self.assertEqual(code, 0, stderr + stdout)

    @staticmethod
    def _run(argv: list[str]) -> tuple[int, str, str]:
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            code = si.main(argv)
        return code, stdout.getvalue(), stderr.getvalue()


class GitArgvTests(unittest.TestCase):
    """Every git call goes through an allowlist of subcommands, flags and revisions."""

    def test_the_calls_this_tool_makes_are_allowed(self):
        for args in (
            ("ls-tree", "-r", "-z", "0123abcd"),
            ("cat-file", "blob", "0123456789abcdef0123456789abcdef01234567"),
            ("cat-file", "-e", "0123abcd^{commit}"),
            ("rev-parse", "HEAD"),
            ("rev-list", "--count", "0123abcd..HEAD"),
            ("hash-object", "--", "skills/a/SKILL.md"),
            ("check-ignore", "-v", "--", "skills/a/SKILL.md"),
        ):
            with self.subTest(args=args):
                argv = si._git_argv(Path("."), args)
                self.assertEqual(list(args), argv[3:])

    def test_unexpected_arguments_are_refused(self):
        for args in (
            ("push", "origin"),
            ("ls-tree", "--output=/tmp/x", "HEAD"),
            ("rev-list", "--count", "main..HEAD"),
            ("hash-object", "--", "--stdin"),
            ("hash-object", "--", str(Path(__file__).resolve())),
            (),
        ):
            with self.subTest(args=args), self.assertRaises(si.RuleError):
                si._git_argv(Path("."), args)


if __name__ == "__main__":
    unittest.main()

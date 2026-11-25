import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


TOOLS_DIR = Path(__file__).resolve().parents[1] / "tools"
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

import generate_skill_index as gsi


class SkillIndexTests(unittest.TestCase):
    def test_committed_index_is_current(self) -> None:
        """The published index must match a fresh regeneration (no drift)."""
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(gsi.main(["--check"]), 0)

    def test_records_cover_every_skill_directory(self) -> None:
        on_disk = sorted(
            path.parent.name for path in gsi.SKILLS_DIR.glob("*/SKILL.md")
        )
        indexed = [record["directory"] for record in gsi.collect_records()]
        self.assertEqual(indexed, on_disk)
        self.assertGreaterEqual(len(indexed), 1)

    def test_every_record_has_description_licence_source_and_path(self) -> None:
        for record in gsi.collect_records():
            with self.subTest(skill=record["directory"]):
                self.assertTrue(record["name"], "name is empty")
                self.assertTrue(record["description"], "description is empty")
                self.assertTrue(record["license"], "license is empty")
                self.assertTrue(record["source"], "source is empty")
                self.assertEqual(record["path"].count("SKILL.md"), 1)
                self.assertTrue(
                    (gsi.REPO_ROOT / record["path"]).is_file(),
                    f"indexed path does not exist: {record['path']}",
                )

    def test_directory_name_matches_frontmatter_name(self) -> None:
        for record in gsi.collect_records():
            with self.subTest(skill=record["directory"]):
                self.assertEqual(record["name"], record["directory"])

    def test_folded_description_scalar_is_flattened(self) -> None:
        """hitcon-dfir-vm-ops uses `description: >-` spanning several lines."""
        record = next(((
            r for r in gsi.collect_records() if r["directory"] == "hitcon-dfir-vm-ops"
        )), None)
        self.assertTrue(record["description"].startswith("Connect to and operate"))
        self.assertNotIn(">", record["description"])
        self.assertNotIn("\n", record["description"])
        self.assertGreater(len(record["description"]), 60)

    def test_missing_licence_falls_back_to_source_licence(self) -> None:
        """The 5 dfir skills without a frontmatter license inherit Apache-2.0."""
        records = {r["directory"]: r for r in gsi.collect_records()}
        for name in ("admiralty-system", "malware-analysis", "osquery-query-helper"):
            with self.subTest(skill=name):
                self.assertEqual(records[name]["license"], "Apache-2.0")
                self.assertEqual(records[name]["license_origin"], "source")
        self.assertEqual(records["ctf-crypto"]["license"], "MIT")
        self.assertEqual(records["ctf-crypto"]["license_origin"], "frontmatter")

    def test_anthropic_import_is_attributed_apache2_and_pinned(self) -> None:
        """The 132-skill import stays Apache-2.0, fully attributed, one commit pin."""
        sources = {s["id"]: s for s in gsi.load_sources()["sources"]}
        source = sources["anthropic-cybersecurity-skills"]
        self.assertEqual(
            source["commit"], "54a798831d2266a3ca61ce68a7acb80b81160d57"
        )
        self.assertEqual(source["license"], "Apache-2.0")
        self.assertEqual(len(source["skills"]), 132)

        records = {r["directory"]: r for r in gsi.collect_records()}
        imported = [name for name in records if name in set(source["skills"])]
        self.assertEqual(sorted(imported), sorted(source["skills"]))
        for name in imported:
            with self.subTest(skill=name):
                self.assertEqual(records[name]["license"], "Apache-2.0")
                self.assertEqual(records[name]["source"], source["label"])
        self.assertIn(source["commit"], gsi.render(gsi.collect_records()))

    def test_anthropic_import_ships_upstream_licence_verbatim(self) -> None:
        """Every imported directory carries the unmodified upstream Apache-2.0 text."""
        source = next(((
            s
            for s in gsi.load_sources()["sources"]
            if s["id"] == "anthropic-cybersecurity-skills"
        )), None)
        digests = set()
        for name in source["skills"]:
            directory = gsi.SKILLS_DIR / name
            with self.subTest(skill=name):
                self.assertTrue((directory / "SKILL.md").is_file())
                licence = directory / "LICENSE"
                self.assertTrue(licence.is_file(), "imported skill lost its LICENSE")
                text = licence.read_text(encoding="utf-8")
                self.assertIn("Apache License", text)
                digests.add(licence.read_bytes())
        self.assertEqual(len(digests), 1, "licence files diverged between skills")

    def test_render_lists_every_skill_and_provenance(self) -> None:
        text = gsi.render(gsi.collect_records())
        for record in gsi.collect_records():
            self.assertIn(f"`{record['name']}`", text)
        self.assertIn("## 載入端如何發現", text)
        self.assertIn("## 來源與授權", text)
        self.assertIn("c332c7be1b27cb64639a20124ac55ba916adef92", text)  # ctf-skills pin
        self.assertIn("Apache-2.0", text)

    def test_check_fails_on_stale_index(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            stale = Path(tmp) / "INDEX.md"
            stale.write_text("# wrong index\n", encoding="utf-8")
            with (
                patch.object(gsi, "INDEX_PATH", stale),
                contextlib.redirect_stderr(io.StringIO()),
            ):
                self.assertEqual(gsi.main(["--check"]), 1)

    def test_check_fails_when_index_is_absent(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            absent = Path(tmp) / "INDEX.md"
            with (
                patch.object(gsi, "INDEX_PATH", absent),
                contextlib.redirect_stderr(io.StringIO()),
            ):
                self.assertEqual(gsi.main(["--check"]), 1)

    def test_unattributed_skill_is_rejected(self) -> None:
        """A skill missing from SOURCES.json must fail, not be silently indexed."""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "mystery-skill").mkdir()
            (root / "mystery-skill" / "SKILL.md").write_text(
                "---\nname: mystery-skill\ndescription: who\n---\n# x\n",
                encoding="utf-8",
            )
            (root / "SOURCES.json").write_text(
                json.dumps({"sources": [{"id": "x", "license": "MIT", "skills": []}]}),
                encoding="utf-8",
            )
            with (
                patch.object(gsi, "SKILLS_DIR", root),
                patch.object(gsi, "SOURCES_PATH", root / "SOURCES.json"),
                self.assertRaises(ValueError) as ctx,
            ):
                gsi.collect_records()
        self.assertIn("unattributed", str(ctx.exception))

    def test_skill_listed_but_absent_is_rejected(self) -> None:
        """SOURCES.json cannot drift ahead of the directory either."""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            root.mkdir(exist_ok=True)
            (root / "SOURCES.json").write_text(
                json.dumps(
                    {"sources": [{"id": "x", "license": "MIT", "skills": ["ghost"]}]}
                ),
                encoding="utf-8",
            )
            with (
                patch.object(gsi, "SKILLS_DIR", root),
                patch.object(gsi, "SOURCES_PATH", root / "SOURCES.json"),
                self.assertRaises(ValueError) as ctx,
            ):
                gsi.collect_records()
        self.assertIn("ghost", str(ctx.exception))

    def test_check_is_idempotent_after_generation(self) -> None:
        """Generate into a temp index, then --check must pass against it."""
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "INDEX.md"
            with patch.object(gsi, "INDEX_PATH", target):
                with contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(gsi.main([]), 0)
                with contextlib.redirect_stderr(io.StringIO()):
                    self.assertEqual(gsi.main(["--check"]), 0)


if __name__ == "__main__":
    unittest.main()
